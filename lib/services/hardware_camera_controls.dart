import 'package:flutter/services.dart';
import '../utils/logger.dart';

/// Sensor capability envelope supported by the hardware camera.
class SensorRanges {
  final int minIso;
  final int maxIso;
  final int minExposureNs;
  final int maxExposureNs;
  final bool manualSupported;
  final List<String> wbModes;

  const SensorRanges({
    required this.minIso,
    required this.maxIso,
    required this.minExposureNs,
    required this.maxExposureNs,
    required this.manualSupported,
    required this.wbModes,
  });

  int clampIso(int iso) => iso.clamp(minIso, maxIso);
  int clampExposureNs(int ns) => ns.clamp(minExposureNs, maxExposureNs);

  @override
  String toString() => 'SensorRanges(iso: $minIso–$maxIso, '
      'exp: ${minExposureNs}ns–${maxExposureNs}ns, '
      'manual: $manualSupported, wb: $wbModes)';
}

/// Standard shutter speed denominator table in nanoseconds.
const Map<String, int> kShutterToNs = {
  '1/4000': 250000,
  '1/2000': 500000,
  '1/1000': 1000000,
  '1/500': 2000000,
  '1/125': 8000000,
  '1/60': 16666667,
  '1/15': 66666667,
};

/// Maps UI labels to native AWB mode strings recognised by platform plugins.
const Map<String, String> kWbLabelToMode = {
  'AWB': 'auto',
  '2300K': 'incandescent',
  '3200K': 'warm_fluorescent',
  '5500K': 'daylight',
  '6500K': 'cloudy_daylight',
  '8000K': 'shade',
};

/// Bridges Dart and native platform camera APIs (Camera2 / AVFoundation) for
/// real hardware manual camera controls: ISO, Shutter Speed, White Balance.
class HardwareCameraControls {
  static const MethodChannel _channel =
      MethodChannel('com.posecoach.pose_coach/manual_camera');

  HardwareCameraControls._();

  static Future<SensorRanges> getSensorRanges() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getSensorRanges',
      );
      if (result == null) return _unsupportedRanges();

      return SensorRanges(
        minIso: (result['minIso'] as int?) ?? 50,
        maxIso: (result['maxIso'] as int?) ?? 800,
        minExposureNs: (result['minExposureNs'] as int?) ?? 250000,
        maxExposureNs: (result['maxExposureNs'] as int?) ?? 66666667,
        manualSupported: (result['manualSupported'] as bool?) ?? false,
        wbModes: List<String>.from(
            (result['wbModes'] as List<dynamic>?) ?? ['auto']),
      );
    } catch (e) {
      AppLogger.error('HardwareCameraControls.getSensorRanges: $e');
      return _unsupportedRanges();
    }
  }

  static Future<void> setManualExposure({
    required int iso,
    required String shutterLabel,
    required SensorRanges ranges,
  }) async {
    if (!ranges.manualSupported) return;

    final rawNs = kShutterToNs[shutterLabel] ?? 2000000;
    final clampedIso = ranges.clampIso(iso);
    final clampedNs = ranges.clampExposureNs(rawNs);

    try {
      await _channel.invokeMethod<void>('setManualExposure', {
        'iso': clampedIso,
        'exposureTimeNs': clampedNs,
      });
    } catch (e) {
      AppLogger.error('HardwareCameraControls.setManualExposure: $e');
    }
  }

  static Future<void> setWhiteBalance({required String wbLabel}) async {
    final mode = kWbLabelToMode[wbLabel] ?? 'auto';
    try {
      await _channel.invokeMethod<void>('setWhiteBalance', {'mode': mode});
    } catch (e) {
      AppLogger.error('HardwareCameraControls.setWhiteBalance: $e');
    }
  }

  static Future<void> setAutoExposure() async {
    try {
      await _channel.invokeMethod<void>('setAutoExposure');
    } catch (e) {
      AppLogger.error('HardwareCameraControls.setAutoExposure: $e');
    }
  }

  static Future<void> lockAutoExposure() async {
    try {
      await _channel.invokeMethod<void>('lockAutoExposure');
    } catch (e) {
      AppLogger.error('HardwareCameraControls.lockAutoExposure: $e');
    }
  }

  static SensorRanges _unsupportedRanges() => const SensorRanges(
        minIso: 50,
        maxIso: 800,
        minExposureNs: 250000,
        maxExposureNs: 66666667,
        manualSupported: false,
        wbModes: ['auto'],
      );
}
