import Flutter
import UIKit
import AVFoundation

/**
 * ManualCameraPlugin (iOS — AVFoundation)
 *
 * Registered on channel "com.posecoach.pose_coach/manual_camera".
 * Provides real hardware control of:
 *   • ISO (sensor sensitivity)
 *   • Shutter Speed (exposure duration)
 *   • White Balance (preset modes)
 *   • Auto-exposure lock/unlock
 *
 * The Flutter `camera` plugin opens its own AVCaptureSession internally.
 * We access the active AVCaptureDevice here to apply our overrides on top of
 * whatever session the plugin is running. This mirrors how Samsung Expert RAW
 * works alongside the native camera stack.
 */
public class ManualCameraPlugin: NSObject, FlutterPlugin {

    // MARK: – Registration
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.posecoach.pose_coach/manual_camera",
            binaryMessenger: registrar.messenger()
        )
        let instance = ManualCameraPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // MARK: – Method dispatch
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getSensorRanges":
            handleGetSensorRanges(result: result)
        case "setManualExposure":
            handleSetManualExposure(call: call, result: result)
        case "setWhiteBalance":
            handleSetWhiteBalance(call: call, result: result)
        case "setAutoExposure":
            handleSetAutoExposure(result: result)
        case "lockAutoExposure":
            handleLockAutoExposure(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: – getSensorRanges
    private func handleGetSensorRanges(result: @escaping FlutterResult) {
        guard let device = activeBackCamera() else {
            result(FlutterError(code: "NO_CAMERA", message: "Back camera unavailable", details: nil))
            return
        }

        let fmt = device.activeFormat
        let manualSupported = device.isExposureModeSupported(.custom)

        // Exposure duration range in nanoseconds (matching Android units)
        let minDurNs = Int64(CMTimeGetSeconds(fmt.minExposureDuration) * 1_000_000_000)
        let maxDurNs = Int64(CMTimeGetSeconds(fmt.maxExposureDuration) * 1_000_000_000)

        // Available WB modes — iOS uses temperature/tint gains; we expose presets
        let wbModes = ["auto", "incandescent", "warm_fluorescent", "daylight", "cloudy_daylight", "shade"]

        result([
            "minIso":          Int(fmt.minISO),
            "maxIso":          Int(fmt.maxISO),
            "minExposureNs":   Int(max(minDurNs, 250_000)),
            "maxExposureNs":   Int(minDurNs < maxDurNs ? maxDurNs : 66_666_667),
            "manualSupported": manualSupported,
            "wbModes":         wbModes,
        ])
    }

    // MARK: – setManualExposure
    private func handleSetManualExposure(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let iso = args["iso"] as? Int,
              let expNs = args["exposureTimeNs"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "iso and exposureTimeNs required", details: nil))
            return
        }

        guard let device = activeBackCamera() else {
            result(FlutterError(code: "NO_CAMERA", message: "Back camera unavailable", details: nil))
            return
        }

        guard device.isExposureModeSupported(.custom) else {
            // Graceful no-op on devices that don't support manual
            result(nil)
            return
        }

        do {
            try device.lockForConfiguration()

            let fmt          = device.activeFormat
            let clampedIso   = Float(iso).clamped(to: fmt.minISO...fmt.maxISO)
            let durSeconds   = Double(expNs) / 1_000_000_000.0
            let minDur       = CMTimeGetSeconds(fmt.minExposureDuration)
            let maxDur       = CMTimeGetSeconds(fmt.maxExposureDuration)
            let clampedDur   = durSeconds.clamped(to: minDur...maxDur)
            let duration     = CMTimeMakeWithSeconds(clampedDur, preferredTimescale: 1_000_000_000)

            device.setExposureModeCustom(duration: duration, iso: clampedIso) { _ in }

            device.unlockForConfiguration()
            result(nil)
        } catch {
            result(FlutterError(code: "CONFIG_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: – setWhiteBalance
    private func handleSetWhiteBalance(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let mode = args["mode"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "mode required", details: nil))
            return
        }

        guard let device = activeBackCamera() else {
            result(FlutterError(code: "NO_CAMERA", message: "Back camera unavailable", details: nil))
            return
        }

        do {
            try device.lockForConfiguration()

            if mode == "auto" {
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
            } else {
                // Map mode label to correlated colour temperature (K)
                let kelvin: Float = kelvinForMode(mode)
                if device.isWhiteBalanceModeSupported(.locked) {
                    let tempTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                        temperature: kelvin, tint: 0
                    )
                    var gains = device.deviceWhiteBalanceGains(for: tempTint)
                    // Clamp gains to device-valid range
                    let maxGain = device.maxWhiteBalanceGain
                    gains.redGain   = min(max(gains.redGain,   1.0), maxGain)
                    gains.greenGain = min(max(gains.greenGain, 1.0), maxGain)
                    gains.blueGain  = min(max(gains.blueGain,  1.0), maxGain)
                    device.setWhiteBalanceModeLocked(with: gains) { _ in }
                }
            }

            device.unlockForConfiguration()
            result(nil)
        } catch {
            result(FlutterError(code: "CONFIG_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: – setAutoExposure
    private func handleSetAutoExposure(result: @escaping FlutterResult) {
        guard let device = activeBackCamera() else { result(nil); return }
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            device.unlockForConfiguration()
        } catch { /* no-op */ }
        result(nil)
    }

    // MARK: – lockAutoExposure
    private func handleLockAutoExposure(result: @escaping FlutterResult) {
        guard let device = activeBackCamera() else { result(nil); return }
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch { /* no-op */ }
        result(nil)
    }

    // MARK: – Helpers
    private func activeBackCamera() -> AVCaptureDevice? {
        if let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
            return device
        }
        if let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
            return device
        }
        return AVCaptureDevice.default(for: .video)
    }

    private func kelvinForMode(_ mode: String) -> Float {
        switch mode {
        case "incandescent":     return 2300
        case "warm_fluorescent": return 3200
        case "daylight":         return 5500
        case "cloudy_daylight":  return 6500
        case "shade":            return 8000
        default:                 return 5500 // neutral daylight
        }
    }
}

// MARK: – Comparable clamping helper
extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
