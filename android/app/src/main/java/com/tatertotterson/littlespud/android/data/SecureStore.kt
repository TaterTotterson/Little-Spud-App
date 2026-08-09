package com.tatertotterson.littlespud.android.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.tatertotterson.littlespud.android.model.LittleSpudSession
import com.tatertotterson.littlespud.android.model.PushRegistration
import org.json.JSONObject
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class SecureStore(context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    @Synchronized
    fun loadSession(): LittleSpudSession? = readJson(KEY_SESSION)?.let { json ->
        runCatching { LittleSpudSession.fromJson(json) }.getOrNull()
    }

    @Synchronized
    fun saveSession(session: LittleSpudSession) = writeJson(KEY_SESSION, session.toJson())

    @Synchronized
    fun clearSession() = preferences.edit().remove(KEY_SESSION).apply()

    @Synchronized
    fun loadPushRegistration(): PushRegistration? = readJson(KEY_PUSH_REGISTRATION)?.let { json ->
        runCatching { PushRegistration.fromJson(json) }.getOrNull()
    }

    @Synchronized
    fun savePushRegistration(registration: PushRegistration) =
        writeJson(KEY_PUSH_REGISTRATION, registration.toJson())

    @Synchronized
    fun clearPushRegistration() = preferences.edit().remove(KEY_PUSH_REGISTRATION).apply()

    @Synchronized
    fun installId(): String {
        val existing = readString(KEY_INSTALL_ID)
        if (!existing.isNullOrBlank()) return existing
        return UUID.randomUUID().toString().lowercase().also { writeString(KEY_INSTALL_ID, it) }
    }

    @Synchronized
    fun fcmToken(): String = readString(KEY_FCM_TOKEN).orEmpty()

    @Synchronized
    fun saveFcmToken(token: String) = writeString(KEY_FCM_TOKEN, token.trim())

    private fun readJson(key: String): JSONObject? = readString(key)?.let { value ->
        runCatching { JSONObject(value) }.getOrElse {
            preferences.edit().remove(key).apply()
            null
        }
    }

    private fun writeJson(key: String, json: JSONObject) = writeString(key, json.toString())

    private fun readString(key: String): String? {
        val encoded = preferences.getString(key, null) ?: return null
        return runCatching { decrypt(encoded) }.getOrElse {
            preferences.edit().remove(key).apply()
            null
        }
    }

    private fun writeString(key: String, value: String) {
        preferences.edit().putString(key, encrypt(value)).apply()
    }

    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        return JSONObject().apply {
            put("v", 1)
            put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            put("data", Base64.encodeToString(encrypted, Base64.NO_WRAP))
        }.toString()
    }

    private fun decrypt(value: String): String {
        val envelope = JSONObject(value)
        require(envelope.optInt("v") == 1) { "Unsupported secure-store value." }
        val iv = Base64.decode(envelope.getString("iv"), Base64.NO_WRAP)
        val encrypted = Base64.decode(envelope.getString("data"), Base64.NO_WRAP)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
        return cipher.doFinal(encrypted).toString(Charsets.UTF_8)
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setRandomizedEncryptionRequired(true)
                    .build(),
            )
            generateKey()
        }
    }

    private companion object {
        const val PREFERENCES_NAME = "little-spud-secure"
        const val KEY_ALIAS = "little-spud-android-storage-v1"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val KEY_SESSION = "session"
        const val KEY_PUSH_REGISTRATION = "push-registration"
        const val KEY_INSTALL_ID = "install-id"
        const val KEY_FCM_TOKEN = "fcm-token"
    }
}
