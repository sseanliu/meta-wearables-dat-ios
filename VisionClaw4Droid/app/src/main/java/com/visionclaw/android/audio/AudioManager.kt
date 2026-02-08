package com.visionclaw.android.audio

import android.media.*
import android.media.audiofx.AcousticEchoCanceler
import android.util.Log
import com.visionclaw.android.service.gemini.GeminiConfig
import kotlinx.coroutines.*

/**
 * Bidirectional audio manager: captures PCM Int16 @ 16 kHz and sends to Gemini,
 * plays back PCM Int16 @ 24 kHz from Gemini through the speaker.
 *
 * Equivalent to iOS AudioManager.swift.
 */
class AudioManager {

    var onAudioCaptured: ((ByteArray) -> Unit)? = null

    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private var aec: AcousticEchoCanceler? = null
    private var captureJob: Job? = null
    private var isCapturing = false

    // Accumulate ~100 ms chunks before sending (same as iOS: 1600 frames * 2 bytes = 3200)
    private val minSendBytes = 3200

    fun setupAudioSession(usePhoneMode: Boolean) {
        Log.i(TAG, "Audio session: ${if (usePhoneMode) "phone (communication)" else "glasses (normal)"}")
    }

    fun startCapture() {
        if (isCapturing) return

        val sampleRate = GeminiConfig.INPUT_AUDIO_SAMPLE_RATE
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val encoding = AudioFormat.ENCODING_PCM_16BIT
        val bufferSize = maxOf(
            AudioRecord.getMinBufferSize(sampleRate, channelConfig, encoding),
            minSendBytes * 2
        )

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            sampleRate,
            channelConfig,
            encoding,
            bufferSize,
        ).also { record ->
            if (record.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "AudioRecord failed to initialize")
                return
            }
            // Enable acoustic echo canceler if available
            if (AcousticEchoCanceler.isAvailable()) {
                aec = AcousticEchoCanceler.create(record.audioSessionId)?.also {
                    it.enabled = true
                    Log.i(TAG, "AcousticEchoCanceler enabled")
                }
            } else {
                Log.w(TAG, "AcousticEchoCanceler not available on this device")
            }
        }

        // Setup playback track at 24 kHz
        val outSampleRate = GeminiConfig.OUTPUT_AUDIO_SAMPLE_RATE
        val outBufferSize = AudioTrack.getMinBufferSize(
            outSampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )

        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(outSampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .build()
            )
            .setBufferSizeInBytes(maxOf(outBufferSize, 4096))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()

        audioRecord?.startRecording()
        audioTrack?.play()
        isCapturing = true

        // Capture loop on a background coroutine
        captureJob = CoroutineScope(Dispatchers.IO).launch {
            val readBuffer = ByteArray(minSendBytes)
            var accumulated = ByteArray(0)

            while (isActive && isCapturing) {
                val bytesRead = audioRecord?.read(readBuffer, 0, readBuffer.size) ?: -1
                if (bytesRead > 0) {
                    accumulated += readBuffer.copyOfRange(0, bytesRead)
                    if (accumulated.size >= minSendBytes) {
                        val chunk = accumulated.copyOf()
                        accumulated = ByteArray(0)
                        onAudioCaptured?.invoke(chunk)
                    }
                }
            }
            // Flush remaining
            if (accumulated.isNotEmpty()) {
                onAudioCaptured?.invoke(accumulated)
            }
        }

        Log.i(TAG, "Capture started (${sampleRate}Hz, mono, Int16)")
    }

    /** Play audio data received from Gemini (PCM Int16 @ 24 kHz). */
    fun playAudio(data: ByteArray) {
        if (!isCapturing || data.isEmpty()) return
        audioTrack?.write(data, 0, data.size)
    }

    fun stopPlayback() {
        audioTrack?.pause()
        audioTrack?.flush()
        audioTrack?.play()
    }

    fun stopCapture() {
        if (!isCapturing) return
        isCapturing = false
        captureJob?.cancel()
        captureJob = null

        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null

        aec?.release()
        aec = null

        audioTrack?.stop()
        audioTrack?.release()
        audioTrack = null

        Log.i(TAG, "Capture stopped")
    }

    companion object {
        private const val TAG = "AudioManager"
    }
}
