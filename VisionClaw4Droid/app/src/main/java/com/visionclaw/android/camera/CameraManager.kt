package com.visionclaw.android.camera

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.util.Log
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * CameraX-based camera manager for phone camera mode.
 * Equivalent to iOS IPhoneCameraManager.swift.
 *
 * Captures frames from the back camera, converts YUV to Bitmap, and delivers
 * them via [onFrameCaptured] at native frame rate. The ViewModel applies
 * the 1-fps throttle before sending to Gemini.
 */
class CameraManager(private val context: Context) {

    var onFrameCaptured: ((Bitmap) -> Unit)? = null

    private var cameraProvider: ProcessCameraProvider? = null
    private val analysisExecutor = Executors.newSingleThreadExecutor()
    private var isRunning = false

    fun start(lifecycleOwner: LifecycleOwner, previewView: PreviewView?) {
        if (isRunning) return
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            val provider = future.get()
            cameraProvider = provider
            bindCamera(provider, lifecycleOwner, previewView)
            isRunning = true
            Log.i(TAG, "Camera started")
        }, ContextCompat.getMainExecutor(context))
    }

    fun stop() {
        if (!isRunning) return
        cameraProvider?.unbindAll()
        cameraProvider = null
        isRunning = false
        Log.i(TAG, "Camera stopped")
    }

    private fun bindCamera(
        provider: ProcessCameraProvider,
        lifecycleOwner: LifecycleOwner,
        previewView: PreviewView?,
    ) {
        provider.unbindAll()

        val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

        val preview = Preview.Builder().build().also {
            it.surfaceProvider = previewView?.surfaceProvider
        }

        val analysis = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()

        analysis.setAnalyzer(analysisExecutor) { imageProxy ->
            val bitmap = imageProxyToBitmap(imageProxy)
            if (bitmap != null) {
                onFrameCaptured?.invoke(bitmap)
            }
            imageProxy.close()
        }

        provider.bindToLifecycle(lifecycleOwner, cameraSelector, preview, analysis)
    }

    private fun imageProxyToBitmap(image: ImageProxy): Bitmap? {
        return try {
            val yBuffer = image.planes[0].buffer
            val uBuffer = image.planes[1].buffer
            val vBuffer = image.planes[2].buffer
            val ySize = yBuffer.remaining()
            val uSize = uBuffer.remaining()
            val vSize = vBuffer.remaining()
            val nv21 = ByteArray(ySize + uSize + vSize)
            yBuffer.get(nv21, 0, ySize)
            vBuffer.get(nv21, ySize, vSize)
            uBuffer.get(nv21, ySize + vSize, uSize)

            val yuvImage = YuvImage(nv21, ImageFormat.NV21, image.width, image.height, null)
            val baos = ByteArrayOutputStream()
            yuvImage.compressToJpeg(Rect(0, 0, image.width, image.height), 80, baos)
            val jpegBytes = baos.toByteArray()
            BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
        } catch (e: Exception) {
            Log.e(TAG, "Frame conversion failed", e)
            null
        }
    }

    companion object {
        private const val TAG = "CameraManager"
    }
}
