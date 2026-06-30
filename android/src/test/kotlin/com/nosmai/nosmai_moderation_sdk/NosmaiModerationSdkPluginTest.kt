package com.nosmai.nosmai_moderation_sdk

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

/*
 * Unit test of the Kotlin plugin. Until the native Nosmai SDK is attached, the
 * host methods return neutral SAFE stubs — this confirms the bridge wiring.
 *
 * Run from `example/android/` with `./gradlew testDebugUnitTest`.
 */
internal class NosmaiModerationSdkPluginTest {
    @Test
    fun moderateText_stub_returnsAllowed() {
        val plugin = NosmaiModerationSdkPlugin()
        var result: NosmaiTextResult? = null
        plugin.moderateText("hello world") { r -> result = r.getOrNull() }
        assertNotNull(result)
        assertEquals(false, result?.blocked)
    }

    @Test
    fun setThreshold_stub_doesNotThrow() {
        val plugin = NosmaiModerationSdkPlugin()
        plugin.setThreshold(NosmaiCategory.WEAPON, 0.9)
        plugin.shutdown()
    }
}
