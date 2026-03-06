package com.example.pauza_screen_time.app_restriction.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals

internal class ShieldConfigEqualsTest {

    private fun base(iconBytes: ByteArray? = null): ShieldConfig =
        ShieldConfig.DEFAULT.copy(iconBytes = iconBytes)

    @Test
    fun equals_bothIconBytesNull() {
        val a = base(iconBytes = null)
        val b = base(iconBytes = null)
        assertEquals(a, b)
    }

    @Test
    fun equals_sameIconBytes() {
        val bytes = byteArrayOf(1, 2, 3)
        val a = base(iconBytes = bytes.copyOf())
        val b = base(iconBytes = bytes.copyOf())
        assertEquals(a, b)
    }

    @Test
    fun notEquals_oneIconBytesNull() {
        val a = base(iconBytes = byteArrayOf(1, 2, 3))
        val b = base(iconBytes = null)
        assertNotEquals(a, b)
        assertNotEquals(b, a)
    }

    @Test
    fun notEquals_differentIconBytes() {
        val a = base(iconBytes = byteArrayOf(1, 2, 3))
        val b = base(iconBytes = byteArrayOf(4, 5, 6))
        assertNotEquals(a, b)
    }

    @Test
    fun notEquals_differentTitle_sameIconBytesNull() {
        val a = base(iconBytes = null)
        val b = a.copy(title = "Different")
        assertNotEquals(a, b)
    }

    @Test
    fun notEquals_differentSecondaryButtonLabel() {
        // Ensures fields after iconBytes in the equals chain are compared
        val a = base(iconBytes = null).copy(secondaryButtonLabel = "A")
        val b = base(iconBytes = null).copy(secondaryButtonLabel = "B")
        assertNotEquals(a, b)
    }

    @Test
    fun hashCode_consistentWithEquals() {
        val a = base(iconBytes = byteArrayOf(10, 20))
        val b = base(iconBytes = byteArrayOf(10, 20))
        assertEquals(a, b)
        assertEquals(a.hashCode(), b.hashCode())
    }
}
