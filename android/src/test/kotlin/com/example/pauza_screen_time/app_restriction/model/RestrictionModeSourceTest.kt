package com.example.pauza_screen_time.app_restriction.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

internal class RestrictionModeSourceTest {

    @Test
    fun fromWireValue_parsesAllKnownValues() {
        assertEquals(RestrictionModeSource.NONE, RestrictionModeSource.fromWireValue("none"))
        assertEquals(RestrictionModeSource.MANUAL, RestrictionModeSource.fromWireValue("manual"))
        assertEquals(RestrictionModeSource.SCHEDULE, RestrictionModeSource.fromWireValue("schedule"))
    }

    @Test
    fun fromWireValue_throwsOnUnknownValue() {
        assertFailsWith<IllegalArgumentException> {
            RestrictionModeSource.fromWireValue("unknown")
        }
    }

    @Test
    fun fromWireValue_throwsOnEmptyString() {
        assertFailsWith<IllegalArgumentException> {
            RestrictionModeSource.fromWireValue("")
        }
    }

    @Test
    fun wireValue_roundTrips() {
        RestrictionModeSource.entries.forEach { source ->
            assertEquals(source, RestrictionModeSource.fromWireValue(source.wireValue))
        }
    }
}
