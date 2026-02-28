package com.example.pauza_screen_time.app_restriction.overlay

import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner

/**
 * @deprecated No longer needed. LockActivity (ComponentActivity) provides its own
 * lifecycle and saved-state registry. Retained for one release cycle alongside
 * ShieldOverlayManager for rollback safety.
 *
 * Contains LifecycleOwner and SavedStateRegistryOwner implementations for
 * hosting a ComposeView in a WindowManager overlay context.
 */

/**
 * @deprecated See [OverlayViewTreeOwners] file-level deprecation note.
 */
@Deprecated("No longer needed; LockActivity provides lifecycle.", level = DeprecationLevel.WARNING)
class OverlayLifecycleOwner : LifecycleOwner {
    private val lifecycleRegistry = LifecycleRegistry(this)

    init {
        lifecycleRegistry.currentState = Lifecycle.State.RESUMED
    }

    override val lifecycle: Lifecycle
        get() = lifecycleRegistry
}

/**
 * @deprecated See [OverlayViewTreeOwners] file-level deprecation note.
 */
@Deprecated("No longer needed; LockActivity provides saved-state.", level = DeprecationLevel.WARNING)
class OverlaySavedStateRegistryOwner : SavedStateRegistryOwner {
    private val lifecycleRegistry = LifecycleRegistry(this)
    private val savedStateRegistryController = SavedStateRegistryController.create(this)

    init {
        savedStateRegistryController.performAttach()
        savedStateRegistryController.performRestore(null)
        lifecycleRegistry.currentState = Lifecycle.State.RESUMED
    }

    override val lifecycle: Lifecycle
        get() = lifecycleRegistry

    override val savedStateRegistry: SavedStateRegistry
        get() = savedStateRegistryController.savedStateRegistry
}
