package com.tatertotterson.littlespud.android.fitness

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.tatertotterson.littlespud.android.LittleSpudApplication
import com.tatertotterson.littlespud.android.data.SpudLinkException
import java.time.ZoneId
import java.util.concurrent.TimeUnit

class FitnessSyncWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result {
        val app = applicationContext as? LittleSpudApplication ?: return Result.failure()
        val container = app.container
        if (!container.settings.fitnessSyncEnabled) return Result.success()
        val session = container.secureStore.loadSession() ?: return Result.success()
        if (session.isDemo) return Result.success()
        if (!container.fitnessHealth.coreAvailable(session)) return Result.success()
        try {
            container.api.fetchFitness(session, refresh = false)
            container.fitnessHealth.setCoreAvailable(true, session)
        } catch (error: Throwable) {
            if (isCoreUnavailable(error)) {
                container.fitnessHealth.setCoreAvailable(false, session)
                return Result.success()
            }
            return Result.retry()
        }
        if (!container.fitnessHealth.hasReadAccess()) {
            container.settings.fitnessSyncEnabled = false
            return Result.success()
        }
        if (!container.fitnessHealth.hasBackgroundReadAccess()) return Result.success()
        return runCatching {
            val plan = container.fitnessHealth.pendingDailyTotals(session)
            if (plan.days.isNotEmpty()) {
                container.api.syncFitness(
                    session = session,
                    platform = "android-health-connect",
                    timeZone = ZoneId.systemDefault().id,
                    permissions = container.fitnessHealth.grantedPermissions(),
                    days = plan.days,
                )
            }
            container.fitnessHealth.markDailyTotalsSynced(plan, session)
        }.fold(onSuccess = { Result.success() }, onFailure = { Result.retry() })
    }

    companion object {
        private const val UNIQUE_WORK = "little-spud-fitness-sync"

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<FitnessSyncWorker>(1, TimeUnit.HOURS)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_WORK,
                ExistingPeriodicWorkPolicy.UPDATE,
                request,
            )
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_WORK)
        }

        private fun isCoreUnavailable(error: Throwable): Boolean {
            val status = (error as? SpudLinkException)?.statusCode
            return (status == 404 || status == 409) &&
                !error.message.orEmpty().contains("link little spud", ignoreCase = true)
        }
    }
}
