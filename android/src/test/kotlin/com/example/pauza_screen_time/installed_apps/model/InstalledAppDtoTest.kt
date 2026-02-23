package com.example.pauza_screen_time.installed_apps.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull

internal class InstalledAppDtoTest {

    private fun validMap(overrides: Map<String, Any?> = emptyMap()): Map<String, Any?> {
        val base = mutableMapOf<String, Any?>(
            "platform" to "android",
            "packageId" to "com.example.app",
            "name" to "Example App",
            "icon" to null,
            "category" to null,
            "isSystemApp" to false,
        )
        base.putAll(overrides)
        return base
    }

    // -------------------------------------------------------------------------
    // fromMap – happy path
    // -------------------------------------------------------------------------

    @Test
    fun fromMap_parsesValidPayload() {
        val icon = byteArrayOf(1, 2, 3)
        val dto = InstalledAppDto.fromMap(
            validMap(mapOf("icon" to icon, "category" to "Social", "isSystemApp" to true))
        )
        assertEquals("android", dto.platform)
        assertEquals("com.example.app", dto.packageId)
        assertEquals("Example App", dto.name)
        assertNotNull(dto.icon)
        assertEquals("Social", dto.category)
        assertEquals(true, dto.isSystemApp)
    }

    @Test
    fun fromMap_allowsNullIconAndCategory() {
        val dto = InstalledAppDto.fromMap(validMap())
        assertNull(dto.icon)
        assertNull(dto.category)
        assertFalse(dto.isSystemApp)
    }

    @Test
    fun fromMap_defaultsIsSystemAppToFalse_whenAbsent() {
        val map = validMap(mapOf("isSystemApp" to null))
        val dto = InstalledAppDto.fromMap(map)
        assertFalse(dto.isSystemApp)
    }

    // -------------------------------------------------------------------------
    // fromMap – validation failures
    // -------------------------------------------------------------------------

    @Test
    fun fromMap_throwsOnMissingPlatform() {
        assertFailsWith<IllegalArgumentException> {
            InstalledAppDto.fromMap(validMap(mapOf("platform" to null)))
        }
    }

    @Test
    fun fromMap_throwsOnWrongPlatform() {
        assertFailsWith<IllegalArgumentException> {
            InstalledAppDto.fromMap(validMap(mapOf("platform" to "ios")))
        }
    }

    @Test
    fun fromMap_throwsOnMissingPackageId() {
        assertFailsWith<IllegalArgumentException> {
            InstalledAppDto.fromMap(validMap(mapOf("packageId" to null)))
        }
    }

    @Test
    fun fromMap_throwsOnBlankPackageId() {
        assertFailsWith<IllegalArgumentException> {
            InstalledAppDto.fromMap(validMap(mapOf("packageId" to "   ")))
        }
    }

    @Test
    fun fromMap_throwsOnMissingName() {
        assertFailsWith<IllegalArgumentException> {
            InstalledAppDto.fromMap(validMap(mapOf("name" to null)))
        }
    }

    @Test
    fun fromMap_throwsOnWrongIconType() {
        assertFailsWith<IllegalArgumentException> {
            InstalledAppDto.fromMap(validMap(mapOf("icon" to "not-bytes")))
        }
    }

    // -------------------------------------------------------------------------
    // toChannelMap round-trip
    // -------------------------------------------------------------------------

    @Test
    fun toChannelMap_roundTrips() {
        val icon = byteArrayOf(10, 20, 30)
        val original = InstalledAppDto(
            platform = "android",
            packageId = "com.example.app",
            name = "Example App",
            icon = icon,
            category = "Games",
            isSystemApp = false,
        )
        val map = original.toChannelMap()
        val restored = InstalledAppDto.fromMap(map)

        assertEquals(original.platform, restored.platform)
        assertEquals(original.packageId, restored.packageId)
        assertEquals(original.name, restored.name)
        assertEquals(original.category, restored.category)
        assertEquals(original.isSystemApp, restored.isSystemApp)
        // ByteArray content equality
        assertEquals(original, restored)
    }

    // -------------------------------------------------------------------------
    // equals / hashCode – ByteArray content equality
    // -------------------------------------------------------------------------

    @Test
    fun equals_sameContent_returnsTrue() {
        val a = InstalledAppDto("android", "com.x", "X", byteArrayOf(1, 2), null, false)
        val b = InstalledAppDto("android", "com.x", "X", byteArrayOf(1, 2), null, false)
        assertEquals(a, b)
        assertEquals(a.hashCode(), b.hashCode())
    }

    @Test
    fun equals_differentPackageId_returnsFalse() {
        val a = InstalledAppDto("android", "com.x", "X", null, null, false)
        val b = InstalledAppDto("android", "com.y", "X", null, null, false)
        assertFalse(a == b)
    }

    @Test
    fun equals_differentIconContent_returnsFalse() {
        val a = InstalledAppDto("android", "com.x", "X", byteArrayOf(1), null, false)
        val b = InstalledAppDto("android", "com.x", "X", byteArrayOf(2), null, false)
        assertFalse(a == b)
    }

    // -------------------------------------------------------------------------
    // toString
    // -------------------------------------------------------------------------

    @Test
    fun toString_includesKeyFields() {
        val dto = InstalledAppDto("android", "com.x", "X", byteArrayOf(1), null, true)
        val str = dto.toString()
        assert("com.x" in str)
        assert("true" in str || "isSystemApp=true" in str)
    }
}
