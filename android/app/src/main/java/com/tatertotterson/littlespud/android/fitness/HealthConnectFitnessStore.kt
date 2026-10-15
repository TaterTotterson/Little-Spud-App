package com.tatertotterson.littlespud.android.fitness

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.BloodPressureRecord
import androidx.health.connect.client.records.BodyFatRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RespiratoryRateRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.tatertotterson.littlespud.android.model.FitnessDay
import com.tatertotterson.littlespud.android.model.LittleSpudSession
import org.json.JSONObject
import java.time.Duration
import java.time.LocalDate
import java.time.ZoneId
import java.security.MessageDigest
import kotlin.reflect.KClass

data class FitnessHealthSyncPlan(
    val days: List<FitnessDay>,
    val completedFullReconciliation: Boolean,
)

class HealthConnectFitnessStore(private val context: Context) {
    private val syncPreferences = context.getSharedPreferences("little-spud-fitness-sync", Context.MODE_PRIVATE)
    private val foregroundPermissions: Set<String> = setOf(
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(DistanceRecord::class),
        HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class),
        HealthPermission.getReadPermission(HeartRateRecord::class),
        HealthPermission.getReadPermission(RestingHeartRateRecord::class),
        HealthPermission.getReadPermission(HeartRateVariabilityRmssdRecord::class),
        HealthPermission.getReadPermission(BloodPressureRecord::class),
        HealthPermission.getReadPermission(OxygenSaturationRecord::class),
        HealthPermission.getReadPermission(RespiratoryRateRecord::class),
        HealthPermission.getReadPermission(WeightRecord::class),
        HealthPermission.getReadPermission(BodyFatRecord::class),
    )

    val sdkStatus: Int get() = HealthConnectClient.getSdkStatus(context)
    val isAvailable: Boolean get() = sdkStatus == HealthConnectClient.SDK_AVAILABLE

    private val client: HealthConnectClient
        get() {
            check(isAvailable) { "Health Connect is not available on this device." }
            return HealthConnectClient.getOrCreate(context)
        }

    val supportsBackgroundRead: Boolean
        get() = isAvailable && runCatching {
            client.features.getFeatureStatus(
                HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND,
            ) == HealthConnectFeatures.FEATURE_STATUS_AVAILABLE
        }.getOrDefault(false)

    val requiredPermissions: Set<String>
        get() = buildSet {
            addAll(foregroundPermissions)
            if (supportsBackgroundRead) add(HealthPermission.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND)
        }

    suspend fun grantedPermissions(): Set<String> = if (isAvailable) {
        client.permissionController.getGrantedPermissions()
    } else emptySet()

    suspend fun hasReadAccess(): Boolean = grantedPermissions().any {
        it != HealthPermission.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND
    }

    fun hasReadAccess(permissions: Set<String>): Boolean = permissions.any {
        it != HealthPermission.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND
    }

    suspend fun hasBackgroundReadAccess(): Boolean =
        HealthPermission.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND in grantedPermissions()

    fun coreAvailable(session: LittleSpudSession): Boolean =
        syncPreferences.getBoolean(coreAvailabilityKey(syncScope(session)), false)

    fun setCoreAvailable(available: Boolean, session: LittleSpudSession) {
        syncPreferences.edit().putBoolean(coreAvailabilityKey(syncScope(session)), available).apply()
    }

    suspend fun pendingDailyTotals(session: LittleSpudSession): FitnessHealthSyncPlan {
        val scope = syncScope(session)
        val cached = syncFingerprints(scope)
        val today = LocalDate.now(ZoneId.systemDefault()).toString()
        val fullReconciliation = cached.isEmpty() || syncPreferences.getString(fullDayKey(scope), "") != today
        val candidates = readDailyTotals(if (fullReconciliation) 30 else 2)
        return FitnessHealthSyncPlan(
            days = candidates.filter { cached[it.date] != fingerprint(it) },
            completedFullReconciliation = fullReconciliation,
        )
    }

    fun markDailyTotalsSynced(plan: FitnessHealthSyncPlan, session: LittleSpudSession) {
        val scope = syncScope(session)
        val cached = syncFingerprints(scope).toMutableMap()
        plan.days.forEach { cached[it.date] = fingerprint(it) }
        val retained = cached.keys.sortedDescending().take(120)
        val json = JSONObject()
        retained.forEach { day -> cached[day]?.let { json.put(day, it) } }
        syncPreferences.edit()
            .putString(fingerprintsKey(scope), json.toString())
            .apply {
                if (plan.completedFullReconciliation) {
                    putString(fullDayKey(scope), LocalDate.now(ZoneId.systemDefault()).toString())
                }
            }
            .apply()
    }

    fun resetSyncHistory(session: LittleSpudSession) {
        val scope = syncScope(session)
        syncPreferences.edit()
            .remove(fingerprintsKey(scope))
            .remove(fullDayKey(scope))
            .apply()
    }

    private fun syncFingerprints(scope: String): Map<String, String> = runCatching {
        val json = JSONObject(syncPreferences.getString(fingerprintsKey(scope), "{}") ?: "{}")
        json.keys().asSequence().associateWith { key -> json.optString(key) }
    }.getOrDefault(emptyMap())

    private fun syncScope(session: LittleSpudSession): String = sha256("${session.hubUrl}|${session.token}").take(20)

    private fun fingerprintsKey(scope: String): String = "fitness-fingerprints-$scope"

    private fun fullDayKey(scope: String): String = "fitness-full-day-$scope"

    private fun coreAvailabilityKey(scope: String): String = "fitness-core-available-$scope"

    private fun fingerprint(day: FitnessDay): String = sha256(
        listOf(
            day.date, day.steps, day.distanceMeters, day.activeEnergyKcal, day.exerciseMinutes, day.workouts,
            day.sleepMinutes, day.sleepCoreMinutes, day.sleepDeepMinutes, day.sleepRemMinutes,
            day.sleepAwakeMinutes, day.heartRateAverage, day.heartRateMinimum, day.heartRateMaximum,
            day.restingHeartRate, day.heartRateVariability, day.bloodPressureSystolic,
            day.bloodPressureDiastolic, day.oxygenSaturationPercent, day.respiratoryRate,
            day.weightKilograms, day.bodyFatPercent,
        ).joinToString("|") { it?.toString() ?: "-" },
    )

    private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it.toInt() and 0xff) }

    suspend fun readDailyTotals(count: Int = 30): List<FitnessDay> {
        check(hasReadAccess()) { "Allow Health Connect access to sync fitness totals." }
        val granted = grantedPermissions()
        fun canRead(recordType: KClass<out Record>): Boolean =
            HealthPermission.getReadPermission(recordType) in granted
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        return (0 until count.coerceIn(1, 120)).map { offset ->
            val day = today.minusDays(offset.toLong())
            val start = day.atStartOfDay(zone).toInstant()
            val end = day.plusDays(1).atStartOfDay(zone).toInstant()
            val range = TimeRangeFilter.between(start, end)
            val aggregateMetrics = buildSet {
                if (canRead(StepsRecord::class)) add(StepsRecord.COUNT_TOTAL)
                if (canRead(DistanceRecord::class)) add(DistanceRecord.DISTANCE_TOTAL)
                if (canRead(ActiveCaloriesBurnedRecord::class)) add(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL)
            }
            val aggregate = if (aggregateMetrics.isEmpty()) null else client.aggregate(
                AggregateRequest(metrics = aggregateMetrics, timeRangeFilter = range),
            )
            val exercises = if (canRead(ExerciseSessionRecord::class)) client.readRecords(
                ReadRecordsRequest(recordType = ExerciseSessionRecord::class, timeRangeFilter = range),
            ).records else emptyList()
            val sleep = if (canRead(SleepSessionRecord::class)) client.readRecords(
                ReadRecordsRequest(recordType = SleepSessionRecord::class, timeRangeFilter = range),
            ).records else emptyList()
            val heart = if (canRead(HeartRateRecord::class)) client.readRecords(
                ReadRecordsRequest(recordType = HeartRateRecord::class, timeRangeFilter = range),
            ).records.flatMap { it.samples }.map { it.beatsPerMinute.toDouble() } else emptyList()
            val resting = if (canRead(RestingHeartRateRecord::class)) client.readRecords(
                ReadRecordsRequest(recordType = RestingHeartRateRecord::class, timeRangeFilter = range),
            ).records else emptyList()
            val variability = if (canRead(HeartRateVariabilityRmssdRecord::class)) client.readRecords(
                ReadRecordsRequest(recordType = HeartRateVariabilityRmssdRecord::class, timeRangeFilter = range),
            ).records else emptyList()
            val pressures = if (canRead(BloodPressureRecord::class)) client.readRecords(
                ReadRecordsRequest(recordType = BloodPressureRecord::class, timeRangeFilter = range),
            ).records else emptyList()
            val oxygen = if (canRead(OxygenSaturationRecord::class)) client.readRecords(
                ReadRecordsRequest(recordType = OxygenSaturationRecord::class, timeRangeFilter = range),
            ).records else emptyList()
            val respiration = if (canRead(RespiratoryRateRecord::class)) client.readRecords(
                ReadRecordsRequest(recordType = RespiratoryRateRecord::class, timeRangeFilter = range),
            ).records else emptyList()
            val weights = if (canRead(WeightRecord::class)) client.readRecords(
                ReadRecordsRequest(recordType = WeightRecord::class, timeRangeFilter = range),
            ).records else emptyList()
            val bodyFat = if (canRead(BodyFatRecord::class)) client.readRecords(
                ReadRecordsRequest(recordType = BodyFatRecord::class, timeRangeFilter = range),
            ).records else emptyList()
            val stages = sleep.flatMap { it.stages }
            fun stageMinutes(vararg kinds: Int): Double? {
                val matching = stages.filter { it.stage in kinds }
                if (matching.isEmpty()) return null
                return matching.sumOf { Duration.between(it.startTime, it.endTime).toMinutes().coerceAtLeast(0) }.toDouble()
            }
            val sleepMinutes = stageMinutes(
                SleepSessionRecord.STAGE_TYPE_SLEEPING,
                SleepSessionRecord.STAGE_TYPE_LIGHT,
                SleepSessionRecord.STAGE_TYPE_DEEP,
                SleepSessionRecord.STAGE_TYPE_REM,
            ) ?: sleep.takeIf { it.isNotEmpty() }?.sumOf {
                Duration.between(it.startTime, it.endTime).toMinutes().coerceAtLeast(0)
            }?.toDouble()
            FitnessDay(
                date = day.toString(),
                steps = aggregate?.get(StepsRecord.COUNT_TOTAL)?.coerceAtMost(Int.MAX_VALUE.toLong())?.toInt(),
                distanceMeters = aggregate?.get(DistanceRecord.DISTANCE_TOTAL)?.inMeters,
                activeEnergyKcal = aggregate?.get(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL)?.inKilocalories,
                exerciseMinutes = exercises.takeIf { it.isNotEmpty() }?.sumOf {
                    Duration.between(it.startTime, it.endTime).toMinutes().coerceAtLeast(0)
                }?.toDouble(),
                workouts = exercises.takeIf { it.isNotEmpty() }?.size,
                sleepMinutes = positiveOrNull(sleepMinutes),
                sleepCoreMinutes = positiveOrNull(stageMinutes(SleepSessionRecord.STAGE_TYPE_LIGHT)),
                sleepDeepMinutes = positiveOrNull(stageMinutes(SleepSessionRecord.STAGE_TYPE_DEEP)),
                sleepRemMinutes = positiveOrNull(stageMinutes(SleepSessionRecord.STAGE_TYPE_REM)),
                sleepAwakeMinutes = positiveOrNull(stageMinutes(
                    SleepSessionRecord.STAGE_TYPE_AWAKE,
                    SleepSessionRecord.STAGE_TYPE_AWAKE_IN_BED,
                )),
                heartRateAverage = positiveOrNull(heart.takeIf { it.isNotEmpty() }?.average()),
                heartRateMinimum = positiveOrNull(heart.minOrNull()),
                heartRateMaximum = positiveOrNull(heart.maxOrNull()),
                restingHeartRate = positiveOrNull(
                    resting.takeIf { it.isNotEmpty() }?.map { it.beatsPerMinute.toDouble() }?.average(),
                ),
                heartRateVariability = positiveOrNull(
                    variability.takeIf { it.isNotEmpty() }
                        ?.map { it.heartRateVariabilityMillis }?.average(),
                ),
                bloodPressureSystolic = positiveOrNull(
                    pressures.takeIf { it.isNotEmpty() }
                        ?.map { it.systolic.inMillimetersOfMercury }?.average(),
                ),
                bloodPressureDiastolic = positiveOrNull(
                    pressures.takeIf { it.isNotEmpty() }
                        ?.map { it.diastolic.inMillimetersOfMercury }?.average(),
                ),
                oxygenSaturationPercent = positiveOrNull(
                    oxygen.takeIf { it.isNotEmpty() }?.map { it.percentage.value }?.average(),
                ),
                respiratoryRate = positiveOrNull(
                    respiration.takeIf { it.isNotEmpty() }?.map { it.rate }?.average(),
                ),
                weightKilograms = positiveOrNull(weights.maxByOrNull { it.time }?.weight?.inKilograms),
                bodyFatPercent = positiveOrNull(bodyFat.maxByOrNull { it.time }?.percentage?.value),
            )
        }
    }

    private fun positiveOrNull(value: Double?): Double? = value?.takeIf { it.isFinite() && it > 0.0 }
}
