package com.example.pauza_screen_time.app_restriction

internal data class RestrictionCachedMode(
    val modeId: String,
    val blockedAppIds: List<String>,
)

internal object RestrictionModeUpsertCache {
    private const val maxEntries = 50
    private val modes = object : LinkedHashMap<String, RestrictionCachedMode>(maxEntries, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, RestrictionCachedMode>?): Boolean {
            return size > maxEntries
        }
    }

    @Synchronized
    fun upsert(mode: RestrictionCachedMode) {
        modes[mode.modeId] = mode
    }

    @Synchronized
    fun get(modeId: String): RestrictionCachedMode? {
        return modes[modeId]
    }

    @Synchronized
    fun remove(modeId: String) {
        modes.remove(modeId)
    }
}
