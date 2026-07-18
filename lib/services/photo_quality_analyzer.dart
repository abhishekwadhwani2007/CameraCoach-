import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart' show Offset;
import 'package:image/image.dart' as img;
import 'package:exif/exif.dart';
import '../core/constants.dart';

/// Analyses a captured still image for Pro-mode photography metrics.
/// Both EXIF metadata and math-based image analysis always run and are merged
/// into a single unified result map.
class PhotoQualityAnalyzer {
  static const int _faceRadius = 40;
  static const int _bgCropSize = 100;

  /// Snap raw EXIF ISO string to nearest available preset.
  static int _snapToNearestIso(String rawIso) {
    const presets = [50, 100, 200, 400, 800];
    final value = int.tryParse(rawIso) ?? 200;
    return presets.reduce((a, b) => (a - value).abs() < (b - value).abs() ? a : b);
  }

  /// Snap raw EXIF shutter string to nearest available preset.
  static String _snapToNearestShutter(String rawShutter) {
    const presets = {
      '1/4000': 0.00025, '1/2000': 0.0005, '1/1000': 0.001,
      '1/500': 0.002, '1/125': 0.008, '1/60': 0.01667,
      '1/15': 0.06667, '1s': 1.0, '4s': 4.0, '8s': 8.0, '30s': 30.0,
    };
    double rawSeconds;
    if (rawShutter.contains('/')) {
      final parts = rawShutter.split('/');
      final num = double.tryParse(parts[0]) ?? 1;
      final den = double.tryParse(parts[1]) ?? 1;
      rawSeconds = num / den;
    } else {
      rawSeconds = double.tryParse(rawShutter) ?? 0.002;
    }
    String closest = '1/500';
    double bestDiff = double.infinity;
    for (final entry in presets.entries) {
      final diff = (entry.value - rawSeconds).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        closest = entry.key;
      }
    }
    return closest;
  }

  static Future<Map<String, dynamic>> analyze(
    String imagePath, {
    Offset? nosePosition,
  }) async {
    final bytes = await File(imagePath).readAsBytes();

    String? exifIso;
    String? exifShutter;
    String? exifAperture;
    String? exifFocalLength;
    String? exifCameraModel;

    try {
      final tags = await readExifFromBytes(bytes);
      if (tags.isNotEmpty) {
        exifIso          = tags['EXIF ISOSpeedRatings']?.toString();
        exifShutter      = tags['EXIF ExposureTime']?.toString();
        exifAperture     = tags['EXIF FNumber']?.toString();
        exifFocalLength  = tags['EXIF FocalLength']?.toString();
        exifCameraModel  = tags['Image Model']?.toString();
      }
    } catch (_) {}

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return {
        'source': 'failed',
        'feedback': ['Could not analyze camera settings.'],
      };
    }

    final int w = decoded.width;
    final int h = decoded.height;

    final int nx = nosePosition != null
        ? nosePosition.dx.round().clamp(0, w - 1)
        : (w / 2).round();
    final int ny = nosePosition != null
        ? nosePosition.dy.round().clamp(0, h - 1)
        : (h / 3).round();

    final int faceX = (nx - _faceRadius).clamp(0, w - 1);
    final int faceY = (ny - _faceRadius).clamp(0, h - 1);
    final int faceW = (_faceRadius * 2).clamp(1, w - faceX);
    final int faceH = (_faceRadius * 2).clamp(1, h - faceY);
    final img.Image faceRoi =
        img.copyCrop(decoded, x: faceX, y: faceY, width: faceW, height: faceH);

    final int bgW = _bgCropSize.clamp(1, w);
    final int bgH = _bgCropSize.clamp(1, h);
    final img.Image bgRoi =
        img.copyCrop(decoded, x: 0, y: 0, width: bgW, height: bgH);

    final double faceLum      = _luminance(faceRoi);
    final double faceBlur     = _laplacianVariance(faceRoi);
    final double bgBlur       = _laplacianVariance(bgRoi);
    final double dofRatio     = faceBlur / (bgBlur + 1.0);
    final double dynamicRange = _dynamicRange(decoded);
    final double wbScore      = _colorTempIndex(faceRoi);

    final feedback = <String>[];

    if (dofRatio > ProThresholds.shallowPro) {
      feedback.add(
          'PRO: Shallow depth of field detected (Wide Aperture / f-1.8). '
          'Background is nicely separated.');
    } else if (dofRatio < ProThresholds.deepLimit) {
      feedback.add(
          'LIMIT: Deep focus detected. Your background is too sharp; '
          'use a lower f-stop or move the subject away from the wall.');
    }

    if (faceLum < ProThresholds.severeUnderExposed) {
      feedback.add(
          "FAIL: Severe under-exposed face. The camera 'lied' because the background "
          'was bright. Increase exposure compensation (+EV).');
    } else if (faceLum < ProThresholds.slightlyDark) {
      feedback.add(
          "LIMIT: Slightly dark face. Consider increasing exposure compensation (+EV).");
    } else if (faceLum > ProThresholds.highlightClipping) {
      feedback.add(
          'FAIL: Highlight clipping on skin. '
          'Lower your ISO or increase Shutter Speed.');
    }

    if (dynamicRange > ProThresholds.excellentHdr) {
      feedback.add(
          'INFO: High Dynamic Range detected. '
          'Image preserves details in both shadows and highlights.');
    }

    final bool hasIssues = feedback.any((f) => f.startsWith('FAIL:') || f.startsWith('LIMIT:'));
    if (!hasIssues) {
      feedback.add('PRO: Lighting, focus, and exposure are perfectly balanced.');
    }

    final int    estIso     = faceLum < ProThresholds.slightlyDark ? 400 : 100;
    final String estShutter = faceLum < ProThresholds.slightlyDark ? '1/125' : '1/500';
    final String estWb      =
        wbScore > ProThresholds.warmLimit ? '3200K' : wbScore < ProThresholds.coolLimit ? '6500K' : 'AWB';
    final double estEv      =
        faceLum < ProThresholds.slightlyDark ? 0.7 : faceLum > ProThresholds.highlightClipping ? -0.7 : 0.0;

    return {
      'source': exifIso != null ? 'merged' : 'estimated',
      if (exifIso         != null) 'exif_iso':          exifIso,
      if (exifShutter     != null) 'exif_shutter':      exifShutter,
      if (exifAperture    != null) 'exif_aperture':     exifAperture,
      if (exifFocalLength != null) 'exif_focalLength':  exifFocalLength,
      if (exifCameraModel != null) 'exif_cameraModel':  exifCameraModel,
      'Face_Luminance':        faceLum.toStringAsFixed(1),
      'Aperture_Depth_Ratio':  dofRatio.toStringAsFixed(2),
      'Dynamic_Range_Width':   dynamicRange.toStringAsFixed(1),
      'Color_Temp_Index':      wbScore.toStringAsFixed(1),
      'iso':           exifIso != null ? _snapToNearestIso(exifIso) : estIso,
      'shutter':       exifShutter != null ? _snapToNearestShutter(exifShutter) : estShutter,
      'whiteBalance':  estWb,
      'ev':            estEv,
      'feedback': feedback,
    };
  }

  static Future<String> analyzeJson(
    String imagePath, {
    Offset? nosePosition,
  }) async =>
      jsonEncode(await analyze(imagePath, nosePosition: nosePosition));

  static double _luminance(img.Image image) {
    double total = 0;
    for (final p in image) {
      total += 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
    }
    return total / (image.width * image.height);
  }

  static double _laplacianVariance(img.Image image) {
    final gray = img.grayscale(img.copyResize(image, width: 100));
    final int gw = gray.width;
    final int gh = gray.height;
    final laplacian = List.filled(gw * gh, 0.0);
    double mean = 0.0;

    for (int y = 1; y < gh - 1; y++) {
      for (int x = 1; x < gw - 1; x++) {
        final double centre = gray.getPixel(x, y).r.toDouble();
        final double up     = gray.getPixel(x, y - 1).r.toDouble();
        final double down   = gray.getPixel(x, y + 1).r.toDouble();
        final double left   = gray.getPixel(x - 1, y).r.toDouble();
        final double right  = gray.getPixel(x + 1, y).r.toDouble();
        final double l = (4 * centre) - up - down - left - right;
        laplacian[y * gw + x] = l;
        mean += l;
      }
    }

    mean /= (gw * gh);
    double variance = 0.0;
    for (final l in laplacian) {
      variance += (l - mean) * (l - mean);
    }
    return variance / (gw * gh);
  }

  static double _dynamicRange(img.Image image) {
    final values = <int>[];
    for (int y = 0; y < image.height; y += 4) {
      for (int x = 0; x < image.width; x += 4) {
        final p = image.getPixel(x, y);
        values.add((0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round());
      }
    }
    if (values.isEmpty) return 0.0;
    values.sort();
    final int p95 = values[(values.length * 0.95).floor().clamp(0, values.length - 1)];
    final int p05 = values[(values.length * 0.05).floor().clamp(0, values.length - 1)];
    return (p95 - p05).toDouble();
  }

  static double _colorTempIndex(img.Image image) {
    double totalBStar = 0.0;
    int count = 0;

    for (final p in image) {
      final double rn = p.r / 255.0;
      final double gn = p.g / 255.0;
      final double bn = p.b / 255.0;

      final double rl = rn > 0.04045 ? pow((rn + 0.055) / 1.055, 2.4).toDouble() : rn / 12.92;
      final double gl = gn > 0.04045 ? pow((gn + 0.055) / 1.055, 2.4).toDouble() : gn / 12.92;
      final double bl = bn > 0.04045 ? pow((bn + 0.055) / 1.055, 2.4).toDouble() : bn / 12.92;

      final double y = 0.2126 * rl + 0.7152 * gl + 0.0722 * bl;
      final double z = 0.0193 * rl + 0.1192 * gl + 0.9505 * bl;

      double labF(double t) {
        return t > 0.008856
            ? pow(t, 1.0 / 3.0).toDouble()
            : 7.787 * t + 16.0 / 116.0;
      }

      final double bStar = 200.0 * (labF(y) - labF(z / 1.0891));
      totalBStar += bStar + 128.0;
      count++;
    }

    return count > 0 ? totalBStar / count : 128.0;
  }
}
