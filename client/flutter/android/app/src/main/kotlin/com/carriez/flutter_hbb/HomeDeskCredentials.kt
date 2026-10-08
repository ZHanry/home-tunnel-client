package com.carriez.flutter_hbb

// HOMEDESK: Only encrypted blobs cross this channel; the key is non-exportable.
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

object HomeDeskCredentials {
    private const val ALIAS = "homedesk.portal.credentials.v1"
    private val worker = Executors.newSingleThreadExecutor()
    private val ui = Handler(Looper.getMainLooper())

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).setKeySize(256).build())
        }.generateKey()
    }

    // HOMEDESK: The same native boundary is exercised by AndroidKeyStore instrumentation.
    internal fun crypt(bytes: ByteArray, entropy: ByteArray, protect: Boolean): ByteArray {
        require(bytes.isNotEmpty() && bytes.size <= 65536 && entropy.isNotEmpty() && entropy.size <= 1024)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        return if (protect) {
            cipher.init(Cipher.ENCRYPT_MODE, key())
            cipher.updateAAD(entropy)
            byteArrayOf(1) + cipher.iv + cipher.doFinal(bytes)
        } else {
            require(bytes.size > 29 && bytes[0] == 1.toByte())
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(1, 13)))
            cipher.updateAAD(entropy)
            cipher.doFinal(bytes.copyOfRange(13, bytes.size))
        }
    }

    fun attach(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "homedesk/credentials")
            .setMethodCallHandler { call, result ->
                if (call.method !in listOf("protect", "unprotect")) {
                    result.notImplemented()
                } else {
                    val bytes = call.argument<ByteArray>("bytes")
                    val entropy = call.argument<ByteArray>("entropy")
                    if (bytes == null || bytes.isEmpty() || bytes.size > 65536 ||
                        entropy == null || entropy.isEmpty() || entropy.size > 1024) {
                        result.error("STORAGE_INVALID", "Invalid credential payload", null)
                    } else worker.execute {
                        try {
                            val output = crypt(bytes, entropy, call.method == "protect")
                            ui.post { result.success(output) }
                        } catch (_: Exception) {
                            // Never log credential data or fall back to plaintext.
                            ui.post { result.error("KEYSTORE_FAILED", "Please sign in again", null) }
                        } finally { bytes.fill(0) }
                    }
                }
            }
    }
}
