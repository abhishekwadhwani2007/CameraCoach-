package com.posecoach.pose_coach

import android.hardware.camera2.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** Android Camera2 bridge for manual exposure and white-balance controls. */
class ManualCameraPlugin : FlutterPlugin, MethodCallHandler {

    companion object {
        const val CHANNEL = "com.posecoach.pose_coach/manual_camera"

        private val WB_MODE_MAP = mapOf(
            "auto"            to CaptureRequest.CONTROL_AWB_MODE_AUTO,
            "incandescent"    to CaptureRequest.CONTROL_AWB_MODE_INCANDESCENT,
            "warm_fluorescent" to CaptureRequest.CONTROL_AWB_MODE_WARM_FLUORESCENT,
            "daylight"        to CaptureRequest.CONTROL_AWB_MODE_DAYLIGHT,
            "cloudy_daylight" to CaptureRequest.CONTROL_AWB_MODE_CLOUDY_DAYLIGHT,
            "shade"           to CaptureRequest.CONTROL_AWB_MODE_SHADE,
        )
    }

    private lateinit var channel: MethodChannel
    private var cameraManager: CameraManager? = null

    // References arrive after the Flutter camera plugin creates its session.
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var previewRequestBuilder: CaptureRequest.Builder? = null

    private var currentIso: Int = 200
    private var currentExposureNs: Long = 2_000_000L
    private var currentWbMode: Int = CaptureRequest.CONTROL_AWB_MODE_AUTO
    private var isManualMode: Boolean = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cameraManager = binding.applicationContext
            .getSystemService(CameraManager::class.java)
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        closeSession()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getSensorRanges"    -> handleGetSensorRanges(result)
            "setManualExposure"  -> handleSetManualExposure(call, result)
            "setWhiteBalance"    -> handleSetWhiteBalance(call, result)
            "setAutoExposure"    -> handleSetAutoExposure(result)
            "lockAutoExposure"   -> handleLockAutoExposure(result)
            else                 -> result.notImplemented()
        }
    }

    private fun handleGetSensorRanges(result: Result) {
        try {
            val manager = cameraManager ?: return result.error(
                "NO_CAMERA_MANAGER", "CameraManager unavailable", null)

            val cameraId = getBackCameraId(manager)
                ?: return result.error("NO_CAMERA", "No back camera found", null)

            val chars = manager.getCameraCharacteristics(cameraId)

            val caps = chars.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)
                ?: intArrayOf()
            val manualSupported = caps.contains(
                CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR)

            val isoRange = chars.get(CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE)
            val minIso = isoRange?.lower ?: 50
            val maxIso = isoRange?.upper ?: 3200

            val expRange = chars.get(CameraCharacteristics.SENSOR_INFO_EXPOSURE_TIME_RANGE)
            val minExpNs = expRange?.lower ?: 250_000L
            val maxExpNs = expRange?.upper ?: 200_000_000L

            val awbModes = chars.get(CameraCharacteristics.CONTROL_AWB_AVAILABLE_MODES)
                ?.map { modeIntToLabel(it) }
                ?.filterNotNull()
                ?: listOf("auto")

            result.success(mapOf(
                "minIso"          to minIso,
                "maxIso"          to maxIso,
                "minExposureNs"   to minExpNs,
                "maxExposureNs"   to maxExpNs,
                "manualSupported" to manualSupported,
                "wbModes"         to awbModes,
            ))
        } catch (e: Exception) {
            result.error("QUERY_FAILED", e.message, null)
        }
    }

    private fun handleSetManualExposure(call: MethodCall, result: Result) {
        try {
            val iso  = call.argument<Int>("iso")            ?: 200
            val expNs = call.argument<Int>("exposureTimeNs")?.toLong() ?: 2_000_000L

            currentIso        = iso
            currentExposureNs = expNs
            isManualMode      = true

            applyCurrentSettings()
            result.success(null)
        } catch (e: Exception) {
            result.error("SET_EXPOSURE_FAILED", e.message, null)
        }
    }

    private fun handleSetWhiteBalance(call: MethodCall, result: Result) {
        try {
            val modeStr = call.argument<String>("mode") ?: "auto"
            currentWbMode = WB_MODE_MAP[modeStr] ?: CaptureRequest.CONTROL_AWB_MODE_AUTO
            applyCurrentSettings()
            result.success(null)
        } catch (e: Exception) {
            result.error("SET_WB_FAILED", e.message, null)
        }
    }

    private fun handleSetAutoExposure(result: Result) {
        try {
            isManualMode  = false
            currentWbMode = CaptureRequest.CONTROL_AWB_MODE_AUTO
            applyCurrentSettings()
            result.success(null)
        } catch (e: Exception) {
            result.error("SET_AUTO_FAILED", e.message, null)
        }
    }

    private fun handleLockAutoExposure(result: Result) {
        try {
            applyAeLock(locked = true)
            result.success(null)
        } catch (e: Exception) {
            result.error("LOCK_AE_FAILED", e.message, null)
        }
    }

    private fun applyCurrentSettings() {
        val session = captureSession ?: return
        val builder = previewRequestBuilder ?: return

        if (isManualMode) {
            builder.set(CaptureRequest.CONTROL_AE_MODE,
                        CaptureRequest.CONTROL_AE_MODE_OFF)

            builder.set(CaptureRequest.SENSOR_SENSITIVITY, currentIso)

            builder.set(CaptureRequest.SENSOR_EXPOSURE_TIME, currentExposureNs)

            builder.set(CaptureRequest.CONTROL_AWB_MODE, currentWbMode)
            if (currentWbMode != CaptureRequest.CONTROL_AWB_MODE_AUTO) {
                builder.set(CaptureRequest.CONTROL_AWB_LOCK, true)
            } else {
                builder.set(CaptureRequest.CONTROL_AWB_LOCK, false)
            }

            builder.set(CaptureRequest.CONTROL_AF_MODE,
                        CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
        } else {
            builder.set(CaptureRequest.CONTROL_MODE,
                        CaptureRequest.CONTROL_MODE_AUTO)
            builder.set(CaptureRequest.CONTROL_AE_MODE,
                        CaptureRequest.CONTROL_AE_MODE_ON)
            builder.set(CaptureRequest.CONTROL_AWB_MODE,
                        CaptureRequest.CONTROL_AWB_MODE_AUTO)
            builder.set(CaptureRequest.CONTROL_AWB_LOCK, false)
            builder.set(CaptureRequest.CONTROL_AE_LOCK,  false)
        }

        try {
            session.setRepeatingRequest(builder.build(), null, null)
        } catch (_: CameraAccessException) {
            // The Flutter camera plugin can replace the session between frames.
        }
    }

    private fun applyAeLock(locked: Boolean) {
        val session = captureSession ?: return
        val builder = previewRequestBuilder ?: return
        builder.set(CaptureRequest.CONTROL_AE_LOCK, locked)
        try { session.setRepeatingRequest(builder.build(), null, null) } catch (_: Exception) {}
    }

    fun attachSession(
        device: CameraDevice,
        session: CameraCaptureSession,
        builder: CaptureRequest.Builder,
    ) {
        cameraDevice          = device
        captureSession        = session
        previewRequestBuilder = builder
    }

    fun closeSession() {
        try { captureSession?.close() } catch (_: Exception) {}
        try { cameraDevice?.close()  } catch (_: Exception) {}
        captureSession        = null
        cameraDevice          = null
        previewRequestBuilder = null
    }

    private fun getBackCameraId(manager: CameraManager): String? {
        for (id in manager.cameraIdList) {
            val facing = manager.getCameraCharacteristics(id)
                .get(CameraCharacteristics.LENS_FACING)
            if (facing == CameraCharacteristics.LENS_FACING_BACK) return id
        }
        return manager.cameraIdList.firstOrNull()
    }

    private fun modeIntToLabel(mode: Int): String? = when (mode) {
        CaptureRequest.CONTROL_AWB_MODE_AUTO             -> "auto"
        CaptureRequest.CONTROL_AWB_MODE_INCANDESCENT     -> "incandescent"
        CaptureRequest.CONTROL_AWB_MODE_WARM_FLUORESCENT -> "warm_fluorescent"
        CaptureRequest.CONTROL_AWB_MODE_DAYLIGHT         -> "daylight"
        CaptureRequest.CONTROL_AWB_MODE_CLOUDY_DAYLIGHT  -> "cloudy_daylight"
        CaptureRequest.CONTROL_AWB_MODE_SHADE            -> "shade"
        else                                              -> null
    }
}
