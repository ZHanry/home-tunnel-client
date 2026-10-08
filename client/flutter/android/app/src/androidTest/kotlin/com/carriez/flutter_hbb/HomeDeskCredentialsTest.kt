package com.carriez.flutter_hbb

// HOMEDESK: Actual AndroidKeyStore tests; fixture bytes never represent user credentials.
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.security.KeyStore

@RunWith(AndroidJUnit4::class)
class HomeDeskCredentialsTest {
    @Test fun realKeystoreRoundTripUsesRandomNonceAndNonExportableKey() {
        val plain = "synthetic-instrumentation-token".toByteArray()
        val aad = "homedesk-fixture-aad".toByteArray()
        val first = HomeDeskCredentials.crypt(plain, aad, true)
        val second = HomeDeskCredentials.crypt(plain, aad, true)
        assertFalse(first.contentEquals(second))
        assertArrayEquals(plain, HomeDeskCredentials.crypt(first, aad, false))
        val key = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            .getKey("homedesk.portal.credentials.v1", null)
        assertNull(key.encoded)
        assertEquals("AES", key.algorithm)
    }

    @Test fun authenticationRejectsChangedPayloadNonceAadAndVersion() {
        val aad = "fixture-aad".toByteArray()
        val sealed = HomeDeskCredentials.crypt(byteArrayOf(42, 43), aad, true)
        for (index in listOf(0, 1, sealed.lastIndex)) {
            val changed = sealed.copyOf().apply { this[index] = (this[index].toInt() xor 1).toByte() }
            try { HomeDeskCredentials.crypt(changed, aad, false); fail("Tampered blob accepted") }
            catch (_: Exception) { }
        }
        try { HomeDeskCredentials.crypt(sealed, "other-product".toByteArray(), false); fail("Changed AAD accepted") }
        catch (_: Exception) { }
        try { HomeDeskCredentials.crypt(byteArrayOf(1), aad, false); fail("Truncated blob accepted") }
        catch (_: Exception) { }
    }
}
