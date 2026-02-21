package com.example.pauza_screen_time.app_restriction.schedule

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

internal class RestrictionScheduledModesStorageCodecTest {

    @Test
    fun fromStorageJson_parsesValidModes() {
        val json = """
            [{"modeId":"focus","blockedAppIds":["com.example.app"],"schedule":{"daysOfWeekIso":[1,2],"startMinutes":480,"endMinutes":960}}]
        """.trimIndent()
        val modes = RestrictionScheduledModesStorageCodec.fromStorageJson(json)
        assertEquals(1, modes.size)
        assertEquals("focus", modes[0].modeId)
        assertEquals(listOf("com.example.app"), modes[0].blockedAppIds)
    }

    @Test
    fun fromStorageJson_throwsStorageDecodeExceptionOnCorruptJson() {
        assertFailsWith<StorageDecodeException> {
            RestrictionScheduledModesStorageCodec.fromStorageJson("not-json")
        }
    }

    @Test
    fun fromStorageJson_throwsStorageDecodeExceptionOnTruncatedJson() {
        assertFailsWith<StorageDecodeException> {
            RestrictionScheduledModesStorageCodec.fromStorageJson("[{\"modeId\":")
        }
    }

    @Test
    fun toStorageJson_fromStorageJson_roundTrips() {
        val original = listOf(
            RestrictionScheduledModeEntry(
                modeId = "night",
                schedule = RestrictionScheduleEntry(
                    daysOfWeekIso = setOf(1, 2, 3),
                    startMinutes = 0,
                    endMinutes = 360,
                ),
                blockedAppIds = listOf("com.social.app"),
            )
        )
        val serialized = RestrictionScheduledModesStorageCodec.toStorageJson(original)
        val restored = RestrictionScheduledModesStorageCodec.fromStorageJson(serialized)
        assertEquals(1, restored.size)
        assertEquals(original[0].modeId, restored[0].modeId)
        assertEquals(original[0].blockedAppIds, restored[0].blockedAppIds)
        assertEquals(original[0].schedule?.startMinutes, restored[0].schedule?.startMinutes)
    }

    @Test
    fun fromStorageJson_skipsModesWithMissingModeId() {
        val json = """[{"blockedAppIds":["com.app"]}]"""
        val modes = RestrictionScheduledModesStorageCodec.fromStorageJson(json)
        assertEquals(0, modes.size)
    }
}
