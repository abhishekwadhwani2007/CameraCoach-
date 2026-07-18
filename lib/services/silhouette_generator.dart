import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../services/local_storage_service.dart';
import '../utils/logger.dart';

/// Generates on-device silhouette overlays using the TFLite pose landmark model.
class SilhouetteGenerator {
  static Interpreter? _interpreter;

  static Future<void> _loadModel() async {
    if (_interpreter != null) return;
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/pose_landmark_full.tflite',
      );
    } catch (e) {
      AppLogger.error('Error loading silhouette model: $e');
    }
  }

  static double _sigmoid(double x) {
    return 1.0 / (1.0 + exp(-x));
  }

  static Future<String?> generate({
    required String imagePath,
    Map<String, dynamic>? landmarks,
  }) async {
    await _loadModel();
    if (_interpreter == null) return null;

    final bytes = await File(imagePath).readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) return null;

    final width = original.width;
    final height = original.height;

    const targetSize = 256;
    final resized = img.copyResize(original, width: targetSize, height: targetSize);

    final inputFlat = Float32List(targetSize * targetSize * 3);
    int flatIdx = 0;
    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        final p = resized.getPixel(x, y);
        inputFlat[flatIdx++] = p.r.toDouble() / 255.0;
        inputFlat[flatIdx++] = p.g.toDouble() / 255.0;
        inputFlat[flatIdx++] = p.b.toDouble() / 255.0;
      }
    }

    final maskFlat = Float32List(targetSize * targetSize);

    try {
      _interpreter!.allocateTensors();
      _interpreter!.getInputTensor(0).setTo(inputFlat);
      _interpreter!.invoke();
      _interpreter!.getOutputTensor(2).copyTo(maskFlat);
    } catch (e) {
      AppLogger.error('Silhouette inference error: $e');
      _interpreter?.close();
      _interpreter = null;
      return null;
    }

    final canvas = img.Image(width: width, height: height, numChannels: 4);
    img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

    final boolMask =
        List.generate(targetSize, (i) => List.filled(targetSize, false));
    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        boolMask[y][x] = _sigmoid(maskFlat[y * targetSize + x]) > 0.5;
      }
    }

    if (landmarks != null && landmarks.isNotEmpty) {
      double bodyScale = 100.0;
      final lSh = landmarks['leftShoulder'];
      final rSh = landmarks['rightShoulder'];
      if (lSh != null && rSh != null) {
        final lx = (lSh['x'] as num).toDouble();
        final ly = (lSh['y'] as num).toDouble();
        final rx = (rSh['x'] as num).toDouble();
        final ry = (rSh['y'] as num).toDouble();
        final d = sqrt((lx - rx) * (lx - rx) + (ly - ry) * (ly - ry));
        if (d > 20) bodyScale = d;
      }

      Offset? getPt(String key) {
        final pt = landmarks[key];
        if (pt == null) return null;
        final lx = (pt['x'] as num).toDouble();
        final ly = (pt['y'] as num).toDouble();
        final confidence = (pt['lh'] as num).toDouble();
        if (confidence < 0.25) return null;
        return Offset((lx / width) * targetSize, (ly / height) * targetSize);
      }

      void drawThickLine(String keyA, String keyB, double widthRatio) {
        final a = getPt(keyA);
        final b = getPt(keyB);
        if (a == null || b == null) return;

        final thickness =
            max(3.0, (bodyScale * widthRatio / width) * targetSize);

        final x0 = a.dx;
        final y0 = a.dy;
        final x1 = b.dx;
        final y1 = b.dy;

        final minX = (min(x0, x1) - thickness).clamp(0.0, 255.0).toInt();
        final maxX = (max(x0, x1) + thickness).clamp(0.0, 255.0).toInt();
        final minY = (min(y0, y1) - thickness).clamp(0.0, 255.0).toInt();
        final maxY = (max(y0, y1) + thickness).clamp(0.0, 255.0).toInt();

        final dx = x1 - x0;
        final dy = y1 - y0;
        final lenSq = dx * dx + dy * dy;

        for (int y = minY; y <= maxY; y++) {
          for (int x = minX; x <= maxX; x++) {
            double t = 0.0;
            if (lenSq > 0) {
              t = ((x - x0) * dx + (y - y0) * dy) / lenSq;
              t = t.clamp(0.0, 1.0);
            }
            final projX = x0 + t * dx;
            final projY = y0 + t * dy;
            final distSq =
                (x - projX) * (x - projX) + (y - projY) * (y - projY);
            if (distSq <= thickness * thickness) {
              boolMask[y][x] = true;
            }
          }
        }
      }

      void drawCircle(String key, double radiusRatio) {
        final pt = getPt(key);
        if (pt == null) return;

        final radius =
            max(2.5, (bodyScale * radiusRatio / width) * targetSize);

        final cx = pt.dx;
        final cy = pt.dy;

        final minX = (cx - radius).clamp(0.0, 255.0).toInt();
        final maxX = (cx + radius).clamp(0.0, 255.0).toInt();
        final minY = (cy - radius).clamp(0.0, 255.0).toInt();
        final maxY = (cy + radius).clamp(0.0, 255.0).toInt();

        for (int y = minY; y <= maxY; y++) {
          for (int x = minX; x <= maxX; x++) {
            final distSq =
                (x - cx) * (x - cx) + (y - cy) * (y - cy);
            if (distSq <= radius * radius) {
              boolMask[y][x] = true;
            }
          }
        }
      }

      drawThickLine('leftShoulder', 'rightShoulder', 0.35);
      drawThickLine('leftShoulder', 'leftHip', 0.22);
      drawThickLine('rightShoulder', 'rightHip', 0.22);
      drawThickLine('leftHip', 'rightHip', 0.22);
      drawThickLine('leftShoulder', 'leftElbow', 0.27);
      drawThickLine('leftElbow', 'leftWrist', 0.23);
      drawThickLine('rightShoulder', 'rightElbow', 0.27);
      drawThickLine('rightElbow', 'rightWrist', 0.23);
      drawThickLine('leftHip', 'leftKnee', 0.18);
      drawThickLine('leftKnee', 'leftAnkle', 0.14);
      drawThickLine('rightHip', 'rightKnee', 0.18);
      drawThickLine('rightKnee', 'rightAnkle', 0.14);

      drawCircle('nose', 0.15);
      drawCircle('leftEar', 0.12);
      drawCircle('rightEar', 0.12);
      drawCircle('leftShoulder', 0.13);
      drawCircle('rightShoulder', 0.13);
      drawCircle('leftWrist', 0.20);
      drawCircle('rightWrist', 0.20);
      drawCircle('leftAnkle', 0.12);
      drawCircle('rightAnkle', 0.12);
    }

    // Detect edge pixels — those on the boundary of the silhouette — which
    // are where we paint the neon glow rather than filling the whole shape.
    final edgeMask =
        List.generate(targetSize, (i) => List.filled(targetSize, false));
    for (int y = 1; y < targetSize - 1; y++) {
      for (int x = 1; x < targetSize - 1; x++) {
        if (boolMask[y][x]) {
          if (!boolMask[y - 1][x] ||
              !boolMask[y + 1][x] ||
              !boolMask[y][x - 1] ||
              !boolMask[y][x + 1]) {
            edgeMask[y][x] = true;
          }
        }
      }
    }

    final scaleX = width / targetSize;
    final scaleY = height / targetSize;
    final glowRadius = max(4, (max(width, height) * 0.005).toInt());

    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        if (edgeMask[y][x]) {
          final origX = (x * scaleX).round();
          final origY = (y * scaleY).round();

          img.fillCircle(
            canvas,
            x: origX,
            y: origY,
            radius: glowRadius * 2,
            color: img.ColorRgba8(0, 255, 255, 45),
          );
          img.fillCircle(
            canvas,
            x: origX,
            y: origY,
            radius: glowRadius,
            color: img.ColorRgba8(255, 255, 255, 200),
          );
        }
      }
    }

    // Write into the scoped temp directory so startup cleanup can safely
    // remove it without risking files from other apps.
    final scopedPath = await LocalStorageService.getScopedTempPath();
    final out = File(
      '$scopedPath/reference_overlay_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await out.writeAsBytes(img.encodePng(canvas));
    return out.path;
  }
}
