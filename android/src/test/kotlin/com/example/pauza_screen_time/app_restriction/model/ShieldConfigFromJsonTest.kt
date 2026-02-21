package com.example.pauza_screen_time.app_restriction.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

internal class ShieldConfigFromJsonTest {

    @Test
    fun fromJson_parsesValidJson() {
        val json = """
            {
              "title": "Blocked",
              "subtitle": "Go away",
              "backgroundColor": -15658735,
              "titleColor": -1,
              "subtitleColor": -5263441,
              "backgroundBlurStyle": null,
              "primaryButtonLabel": "OK",
              "primaryButtonBackgroundColor": null,
              "primaryButtonTextColor": null,
              "secondaryButtonLabel": null,
              "secondaryButtonTextColor": null
            }
        """.trimIndent()
        val config = ShieldConfig.fromJson(json)
        assertEquals("Blocked", config.title)
        assertEquals("Go away", config.subtitle)
        assertNull(config.iconBytes)
        assertEquals("OK", config.primaryButtonLabel)
    }

    @Test
    fun fromJson_throwsOnInvalidJson() {
        assertFailsWith<org.json.JSONException> {
            ShieldConfig.fromJson("not-json")
        }
    }

    @Test
    fun fromJson_throwsOnInvalidBase64Icon() {
        val json = """{"title":"T","subtitle":null,"backgroundColor":0,"titleColor":0,"subtitleColor":0,"backgroundBlurStyle":null,"iconBase64":"!!invalid!!", "primaryButtonLabel":null,"primaryButtonBackgroundColor":null,"primaryButtonTextColor":null,"secondaryButtonLabel":null,"secondaryButtonTextColor":null}"""
        assertFailsWith<IllegalArgumentException> {
            ShieldConfig.fromJson(json)
        }
    }

    @Test
    fun toJson_fromJson_roundTrips() {
        val original = ShieldConfig.DEFAULT
        val restored = ShieldConfig.fromJson(ShieldConfig.toJson(original))
        assertEquals(original.title, restored.title)
        assertEquals(original.backgroundColor, restored.backgroundColor)
        assertNull(restored.iconBytes)
    }
}
