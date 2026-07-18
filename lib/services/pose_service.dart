import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/logger.dart';

/// Shared ML Kit pose detector helpers.
class PoseService {
  static PoseDetector? _poseDetector;

  static PoseDetector _getDetector() {
    _poseDetector ??= PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.single,
        model: PoseDetectionModel.base,
      ),
    );
    return _poseDetector!;
  }

  static Future<List<Pose>> detectPose(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final List<Pose> poses = await _getDetector().processImage(inputImage);

      AppLogger.info(
          'Pose detection complete: ${poses.length} person(s) found.');
      return poses;
    } catch (e) {
      AppLogger.error('Failed to detect pose: $e');
      return [];
    }
  }

  static Future<List<Pose>> detectPoseFromCameraImage({
    required CameraImage image,
    required int sensorOrientation,
  }) async {
    try {
      final rotation =
          InputImageRotationValue.fromRawValue(sensorOrientation) ??
              InputImageRotation.rotation0deg;
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return [];

      final bytes = WriteBuffer();
      for (final plane in image.planes) {
        bytes.putUint8List(plane.bytes);
      }

      final inputImage = InputImage.fromBytes(
        bytes: bytes.done().buffer.asUint8List(),
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
      return _getDetector().processImage(inputImage);
    } catch (e) {
      AppLogger.error('Failed to detect camera pose: $e');
      return [];
    }
  }

  /// Serializes landmarks for storage; older references without depth remain
  /// compatible with 2D matching.
  static Map<String, dynamic> poseToMap(Pose pose) {
    final Map<String, dynamic> landmarks = {};

    pose.landmarks.forEach((type, landmark) {
      landmarks[type.name] = {
        'x': landmark.x,
        'y': landmark.y,
        'z': landmark.z,
        'lh': landmark.likelihood,
      };
    });

    return landmarks;
  }
  static void dispose() {
    _poseDetector?.close();
    _poseDetector = null;
  }
}
