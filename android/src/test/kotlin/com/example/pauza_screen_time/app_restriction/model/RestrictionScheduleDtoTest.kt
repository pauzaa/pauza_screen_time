package com.example.pauza_screen_time.app_restriction.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

internal class RestrictionScheduleDtoTest {

    @Test
    fun fromMap_parsesValidPayload() {
        val map = mapOf(
            "daysOfWeekIso" to listOf(1, 3, 5),
            "startMinutes" to 480,
            "endMinutes" to 960,
        )
        val dto = RestrictionScheduleDto.fromMap(map)
        assertEquals(setOf(1, 3, 5), dto.daysOfWeekIso)
        assertEquals(480, dto.startMinutes)
        assertEquals(960, dto.endMinutes)
    }

    @Test
    fun fromMap_throwsOnMissingDays() {
        val map = mapOf("startMinutes" to 480, "endMinutes" to 960)
        assertFailsWith<IllegalArgumentException> {
            RestrictionScheduleDto.fromMap(map)
        }
    }

    @Test
    fun fromMap_throwsOnEmptyDays() {
        val map = mapOf(
            "daysOfWeekIso" to emptyList<Int>(),
            "startMinutes" to 480,
            "endMinutes" to 960,
        )
        assertFailsWith<IllegalArgumentException> {
            RestrictionScheduleDto.fromMap(map)
        }
    }

    @Test
    fun fromMap_throwsOnMissingStartMinutes() {
        val map = mapOf("daysOfWeekIso" to listOf(1), "endMinutes" to 960)
        assertFailsWith<IllegalArgumentException> {
            RestrictionScheduleDto.fromMap(map)
        }
    }

    @Test
    fun fromMap_throwsOnMissingEndMinutes() {
        val map = mapOf("daysOfWeekIso" to listOf(1), "startMinutes" to 480)
        assertFailsWith<IllegalArgumentException> {
            RestrictionScheduleDto.fromMap(map)
        }
    }

    @Test
    fun toChannelMap_roundTrips() {
        val original = RestrictionScheduleDto(
            daysOfWeekIso = setOf(2, 4),
            startMinutes = 540,
            endMinutes = 1020,
        )
        val map = original.toChannelMap()
        val restored = RestrictionScheduleDto.fromMap(map)
        assertEquals(original.daysOfWeekIso, restored.daysOfWeekIso)
        assertEquals(original.startMinutes, restored.startMinutes)
        assertEquals(original.endMinutes, restored.endMinutes)
    }
}
