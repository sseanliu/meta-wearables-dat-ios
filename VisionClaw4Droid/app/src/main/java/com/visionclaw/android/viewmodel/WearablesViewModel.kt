package com.visionclaw.android.viewmodel

import android.util.Log
import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject

/**
 * ViewModel for DAT SDK device registration and management.
 * Equivalent to iOS WearablesViewModel.swift.
 *
 * The DAT SDK integration is stubbed here (Phase 8) — the actual SDK calls
 * will mirror the iOS pattern: Wearables.configure(), startRegistration(),
 * devicesStream(), etc.
 */
@HiltViewModel
class WearablesViewModel @Inject constructor() : ViewModel() {

    enum class RegState { UNREGISTERED, REGISTERING, REGISTERED }

    private val _registrationState = MutableStateFlow(RegState.UNREGISTERED)
    val registrationState: StateFlow<RegState> = _registrationState.asStateFlow()

    private val _devices = MutableStateFlow<List<String>>(emptyList())
    val devices: StateFlow<List<String>> = _devices.asStateFlow()

    private val _showError = MutableStateFlow(false)
    val showError: StateFlow<Boolean> = _showError.asStateFlow()

    private val _errorMessage = MutableStateFlow("")
    val errorMessage: StateFlow<String> = _errorMessage.asStateFlow()

    private val _showGettingStartedSheet = MutableStateFlow(false)
    val showGettingStartedSheet: StateFlow<Boolean> = _showGettingStartedSheet.asStateFlow()

    /**
     * Initiate glasses registration via the Meta AI app (DAT SDK).
     * On Android this triggers the OAuth flow through Meta AI.
     */
    fun connectGlasses() {
        if (_registrationState.value == RegState.REGISTERING) return
        _registrationState.value = RegState.REGISTERING
        Log.i(TAG, "Starting DAT SDK registration...")

        // TODO(Phase 8): Replace with actual DAT SDK call:
        //   Wearables.shared.startRegistration()
        // For now, simulate immediate registration for phone-camera testing:
        _registrationState.value = RegState.REGISTERED
        _showGettingStartedSheet.value = true
    }

    fun disconnectGlasses() {
        Log.i(TAG, "Starting DAT SDK unregistration...")
        // TODO(Phase 8): Wearables.shared.startUnregistration()
        _registrationState.value = RegState.UNREGISTERED
        _devices.value = emptyList()
    }

    fun dismissGettingStartedSheet() {
        _showGettingStartedSheet.value = false
    }

    fun showError(message: String) {
        _errorMessage.value = message
        _showError.value = true
    }

    fun dismissError() {
        _showError.value = false
        _errorMessage.value = ""
    }

    companion object {
        private const val TAG = "Wearables"
    }
}
