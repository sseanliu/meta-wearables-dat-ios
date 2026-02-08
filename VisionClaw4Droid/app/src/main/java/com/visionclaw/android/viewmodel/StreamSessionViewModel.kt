package com.visionclaw.android.viewmodel

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import androidx.camera.view.PreviewView
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ViewModel
import com.visionclaw.android.camera.CameraManager
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject

/**
 * ViewModel for video streaming session management.
 * Supports phone camera mode (CameraX) and glasses mode (DAT SDK).
 *
 * Equivalent to iOS StreamSessionViewModel.swift.
 */
@HiltViewModel
class StreamSessionViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
) : ViewModel() {

    enum class StreamingStatus { STREAMING, WAITING, STOPPED }
    enum class StreamingMode { GLASSES, PHONE }

    private val _currentVideoFrame = MutableStateFlow<Bitmap?>(null)
    val currentVideoFrame: StateFlow<Bitmap?> = _currentVideoFrame.asStateFlow()

    private val _hasReceivedFirstFrame = MutableStateFlow(false)
    val hasReceivedFirstFrame: StateFlow<Boolean> = _hasReceivedFirstFrame.asStateFlow()

    private val _streamingStatus = MutableStateFlow(StreamingStatus.STOPPED)
    val streamingStatus: StateFlow<StreamingStatus> = _streamingStatus.asStateFlow()

    private val _streamingMode = MutableStateFlow(StreamingMode.GLASSES)
    val streamingMode: StateFlow<StreamingMode> = _streamingMode.asStateFlow()

    private val _showError = MutableStateFlow(false)
    val showError: StateFlow<Boolean> = _showError.asStateFlow()

    private val _errorMessage = MutableStateFlow("")
    val errorMessage: StateFlow<String> = _errorMessage.asStateFlow()

    private val _hasActiveDevice = MutableStateFlow(false)
    val hasActiveDevice: StateFlow<Boolean> = _hasActiveDevice.asStateFlow()

    // Photo capture (glasses mode only, via DAT SDK)
    private val _capturedPhoto = MutableStateFlow<Bitmap?>(null)
    val capturedPhoto: StateFlow<Bitmap?> = _capturedPhoto.asStateFlow()

    private val _showPhotoPreview = MutableStateFlow(false)
    val showPhotoPreview: StateFlow<Boolean> = _showPhotoPreview.asStateFlow()

    val isStreaming: Boolean get() = _streamingStatus.value != StreamingStatus.STOPPED

    // Gemini VM reference for video frame forwarding
    var geminiSessionVM: GeminiSessionViewModel? = null

    private var cameraManager: CameraManager? = null

    // ---- Phone Camera Mode ----

    fun startPhoneCamera(lifecycleOwner: LifecycleOwner, previewView: PreviewView?) {
        _streamingMode.value = StreamingMode.PHONE
        val camera = CameraManager(context)
        camera.onFrameCaptured = { bitmap ->
            _currentVideoFrame.value = bitmap
            if (!_hasReceivedFirstFrame.value) {
                _hasReceivedFirstFrame.value = true
            }
            geminiSessionVM?.sendVideoFrameIfThrottled(bitmap)
        }
        camera.start(lifecycleOwner, previewView)
        cameraManager = camera
        _streamingStatus.value = StreamingStatus.STREAMING
        Log.i(TAG, "Phone camera mode started")
    }

    fun stopPhoneCamera() {
        cameraManager?.stop()
        cameraManager = null
        _currentVideoFrame.value = null
        _hasReceivedFirstFrame.value = false
        _streamingStatus.value = StreamingStatus.STOPPED
        _streamingMode.value = StreamingMode.GLASSES
        Log.i(TAG, "Phone camera mode stopped")
    }

    // ---- Glasses Mode (DAT SDK) ----

    fun startGlassesStreaming() {
        _streamingMode.value = StreamingMode.GLASSES
        _streamingStatus.value = StreamingStatus.WAITING
        // DAT SDK integration will be wired in WearablesViewModel / Phase 8
        Log.i(TAG, "Glasses streaming requested (DAT SDK)")
    }

    fun stopStreaming() {
        if (_streamingMode.value == StreamingMode.PHONE) {
            stopPhoneCamera()
        } else {
            // DAT SDK stop will be wired in Phase 8
            _currentVideoFrame.value = null
            _hasReceivedFirstFrame.value = false
            _streamingStatus.value = StreamingStatus.STOPPED
        }
    }

    /** Called by DAT SDK when glasses deliver a video frame. */
    fun onGlassesFrame(bitmap: Bitmap) {
        _currentVideoFrame.value = bitmap
        if (!_hasReceivedFirstFrame.value) {
            _hasReceivedFirstFrame.value = true
        }
        if (_streamingStatus.value != StreamingStatus.STREAMING) {
            _streamingStatus.value = StreamingStatus.STREAMING
        }
        geminiSessionVM?.sendVideoFrameIfThrottled(bitmap)
    }

    fun setActiveDevice(active: Boolean) {
        _hasActiveDevice.value = active
    }

    // ---- Photo ----

    fun capturePhoto() {
        // DAT SDK photo capture wired in Phase 8
    }

    fun dismissPhotoPreview() {
        _showPhotoPreview.value = false
        _capturedPhoto.value = null
    }

    // ---- Error ----

    fun showError(message: String) {
        _errorMessage.value = message
        _showError.value = true
    }

    fun dismissError() {
        _showError.value = false
        _errorMessage.value = ""
    }

    override fun onCleared() {
        super.onCleared()
        cameraManager?.stop()
    }

    companion object {
        private const val TAG = "StreamSession"
    }
}
