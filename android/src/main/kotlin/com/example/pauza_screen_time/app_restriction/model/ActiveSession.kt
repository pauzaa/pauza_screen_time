package com.example.pauza_screen_time.app_restriction.model

import kotlinx.serialization.Serializable

@Serializable
data class ActiveSession(
    val sessionId: String,
    val modeId: String,
    val blockedAppIds: List<String>,
    val source: RestrictionModeSource,
)
