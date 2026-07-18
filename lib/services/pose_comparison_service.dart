import 'dart:math';
import 'package:flutter/material.dart';

/// Result of evaluating a live pose against a target reference pose.
class PoseMatchResult {
  final double score;
  final List<String> feedback;
  final Map<String, double> components;
  final bool isReliable;

  const PoseMatchResult({
    required this.score,
    required this.feedback,
    required this.components,
    required this.isReliable,
  });
}

class _JointTriplet {
  final String name;
  final String a, b, c;
  final double weight;
  final double maxDevDeg;
  final String feedHigh;
  final String feedLow;

  const _JointTriplet({
    required this.name,
    required this.a,
    required this.b,
    required this.c,
    required this.weight,
    this.maxDevDeg = 45.0,
    required this.feedHigh,
    required this.feedLow,
  });
}

/// Hybrid scoring engine measuring anatomical joint angles and cosine similarity.
class PoseComparisonService {
  static const double visibilityThreshold = 0.50;
  static const double zVisibilityThreshold = 0.70;
  static const double feedbackThreshold = 85.0;

  static const List<_JointTriplet> _triplets = [
    _JointTriplet(
      name: 'Left elbow',
      a: 'leftShoulder', b: 'leftElbow', c: 'leftWrist',
      weight: 0.12, maxDevDeg: 45.0,
      feedHigh: 'Bend your left elbow more',
      feedLow: 'Straighten your left arm',
    ),
    _JointTriplet(
      name: 'Right elbow',
      a: 'rightShoulder', b: 'rightElbow', c: 'rightWrist',
      weight: 0.12, maxDevDeg: 45.0,
      feedHigh: 'Bend your right elbow more',
      feedLow: 'Straighten your right arm',
    ),
    _JointTriplet(
      name: 'Left shoulder',
      a: 'leftElbow', b: 'leftShoulder', c: 'leftHip',
      weight: 0.10, maxDevDeg: 40.0,
      feedHigh: 'Lower your left arm',
      feedLow: 'Raise your left arm',
    ),
    _JointTriplet(
      name: 'Right shoulder',
      a: 'rightElbow', b: 'rightShoulder', c: 'rightHip',
      weight: 0.10, maxDevDeg: 40.0,
      feedHigh: 'Lower your right arm',
      feedLow: 'Raise your right arm',
    ),
    _JointTriplet(
      name: 'Left knee',
      a: 'leftHip', b: 'leftKnee', c: 'leftAnkle',
      weight: 0.12, maxDevDeg: 40.0,
      feedHigh: 'Bend your left knee more',
      feedLow: 'Straighten your left leg',
    ),
    _JointTriplet(
      name: 'Right knee',
      a: 'rightHip', b: 'rightKnee', c: 'rightAnkle',
      weight: 0.12, maxDevDeg: 40.0,
      feedHigh: 'Bend your right knee more',
      feedLow: 'Straighten your right leg',
    ),
    _JointTriplet(
      name: 'Left hip',
      a: 'leftShoulder', b: 'leftHip', c: 'leftKnee',
      weight: 0.09, maxDevDeg: 35.0,
      feedHigh: 'Open your left hip angle',
      feedLow: 'Bring your left leg closer to centre',
    ),
    _JointTriplet(
      name: 'Right hip',
      a: 'rightShoulder', b: 'rightHip', c: 'rightKnee',
      weight: 0.09, maxDevDeg: 35.0,
      feedHigh: 'Open your right hip angle',
      feedLow: 'Bring your right leg closer to centre',
    ),
    _JointTriplet(
      name: 'Left ankle',
      a: 'leftKnee', b: 'leftAnkle', c: 'leftFootIndex',
      weight: 0.03, maxDevDeg: 30.0,
      feedHigh: 'Flex your left foot up',
      feedLow: 'Point your left foot more',
    ),
    _JointTriplet(
      name: 'Right ankle',
      a: 'rightKnee', b: 'rightAnkle', c: 'rightFootIndex',
      weight: 0.03, maxDevDeg: 30.0,
      feedHigh: 'Flex your right foot up',
      feedLow: 'Point your right foot more',
    ),
  ];

  static const double _trunkWeight = 0.08;
  static const double _trunkMaxDev = 30.0;

  static PoseMatchResult evaluate(
    Map<String, dynamic> live,
    Map<String, dynamic> reference, {
    Size viewfinderSize = const Size(360, 480),
    Size liveImageSize = const Size(480, 640),
    Size referenceImageSize = const Size(480, 640),
    bool mirrorLive = false,
  }) {
    if (live.isEmpty || reference.isEmpty) {
      return const PoseMatchResult(
        score: 0,
        feedback: ['No human detected. Please step into the frame.'],
        components: {},
        isReliable: false,
      );
    }

    final liveKp = _extractPoints(live, mirrorX: mirrorLive);
    final refKp = _extractPoints(reference);

    final components = <String, double>{};
    final directionSigns = <String, double>{};

    double angleWeightedSum = 0.0;
    double angleWeightTotal = 0.0;

    for (final t in _triplets) {
      final refA = refKp[t.a], refB = refKp[t.b], refC = refKp[t.c];
      final liveA = liveKp[t.a], liveB = liveKp[t.b], liveC = liveKp[t.c];

      if (refA == null || refB == null || refC == null) {
        components[t.name] = 100.0;
        continue;
      }

      if (liveA == null || liveB == null || liveC == null) {
        components[t.name] = 0.0;
        angleWeightedSum += 0.0;
        angleWeightTotal += t.weight;
        continue;
      }

      final liveConf = [liveA.visibility, liveB.visibility, liveC.visibility].reduce(min);
      final confWeight = t.weight * liveConf;

      final useZ = _shouldUseZ(liveA, liveB, liveC) && _shouldUseZ(refA, refB, refC);

      final refAngle = _tripletAngle(refA, refB, refC, useZ: useZ);
      final liveAngle = _tripletAngle(liveA, liveB, liveC, useZ: useZ);

      final signedDev = liveAngle - refAngle;
      final score = max(0.0, 100.0 * (1.0 - signedDev.abs() / t.maxDevDeg));

      components[t.name] = score;
      directionSigns[t.name] = signedDev;
      angleWeightedSum += score * confWeight;
      angleWeightTotal += confWeight;
    }

    final trunkScore = _trunkLeanScore(liveKp, refKp);
    final trunkSign = _trunkLeanAngle(liveKp) - _trunkLeanAngle(refKp);
    components['Trunk lean'] = trunkScore;
    directionSigns['Trunk lean'] = trunkSign;
    angleWeightedSum += trunkScore * _trunkWeight;
    angleWeightTotal += _trunkWeight;

    final primaryScore = angleWeightTotal > 1e-9
        ? (angleWeightedSum / angleWeightTotal).clamp(0.0, 100.0)
        : 0.0;

    final secondaryScore = _normalisedCosineScore(liveKp, refKp);

    final finalScore =
        (primaryScore * 0.70 + secondaryScore * 0.30).clamp(0.0, 100.0);

    final extraWarnings = <String>[];
    const legKeys = [
      'leftHip', 'rightHip', 'leftKnee', 'rightKnee', 'leftAnkle', 'rightAnkle'
    ];
    if (legKeys.every(refKp.containsKey) && !legKeys.every(liveKp.containsKey)) {
      extraWarnings.add('Step back so your whole body is in frame.');
    }

    final feedback = [
      ...extraWarnings,
      ..._makeFeedback(components, directionSigns),
    ];

    return PoseMatchResult(
      score: finalScore,
      feedback: feedback.isEmpty
          ? ['Perfect pose! Hold it right there!']
          : feedback.take(2).toList(),
      components: components,
      isReliable: _isReliable(liveKp),
    );
  }

  static double _trunkLeanAngle(Map<String, _Vector3D> kp) {
    final lSh = kp['leftShoulder'], rSh = kp['rightShoulder'];
    final lHip = kp['leftHip'], rHip = kp['rightHip'];
    if (lSh == null || rSh == null || lHip == null || rHip == null) return 0.0;
    final midSh = (lSh + rSh) * 0.5;
    final midHip = (lHip + rHip) * 0.5;
    final spine = midSh - midHip;
    const up = _Vector3D(0, -1, 0);
    final u = spine.unit();
    if (u == null) return 0.0;
    return acos(u.dot(up).clamp(-1.0, 1.0)) * 180.0 / pi;
  }

  static double _trunkLeanScore(
      Map<String, _Vector3D> live, Map<String, _Vector3D> ref) {
    final dev = (_trunkLeanAngle(live) - _trunkLeanAngle(ref)).abs();
    return max(0.0, 100.0 * (1.0 - dev / _trunkMaxDev));
  }

  static double _tripletAngle(_Vector3D a, _Vector3D b, _Vector3D c, {bool useZ = false}) {
    final vBA = useZ
        ? (a - b)
        : _Vector3D(a.x - b.x, a.y - b.y, 0.0);
    final vBC = useZ
        ? (c - b)
        : _Vector3D(c.x - b.x, c.y - b.y, 0.0);
    final uBA = vBA.unit();
    final uBC = vBC.unit();
    if (uBA == null || uBC == null) return 0.0;
    return acos(uBA.dot(uBC).clamp(-1.0, 1.0)) * 180.0 / pi;
  }

  static bool _shouldUseZ(_Vector3D a, _Vector3D b, _Vector3D c) {
    return a.visibility >= zVisibilityThreshold &&
        b.visibility >= zVisibilityThreshold &&
        c.visibility >= zVisibilityThreshold &&
        (a.z.abs() + b.z.abs() + c.z.abs()) > 0.01;
  }

  static double _normalisedCosineScore(
    Map<String, _Vector3D> live,
    Map<String, _Vector3D> ref,
  ) {
    final lHipL = live['leftHip'], lHipR = live['rightHip'];
    final rHipL = ref['leftHip'], rHipR = ref['rightHip'];
    if (lHipL == null || lHipR == null || rHipL == null || rHipR == null) {
      return 50.0;
    }

    final liveHipCentre = (lHipL + lHipR) * 0.5;
    final refHipCentre = (rHipL + rHipR) * 0.5;
    final liveScale = _torsoScale(live);
    final refScale = _torsoScale(ref);
    if (liveScale < 1e-6 || refScale < 1e-6) return 50.0;

    final commonKeys = live.keys.toSet().intersection(ref.keys.toSet());
    if (commonKeys.isEmpty) return 50.0;

    double dot = 0.0, normL = 0.0, normR = 0.0;
    for (final key in commonKeys) {
      final lv = (live[key]! - liveHipCentre) * (1.0 / liveScale);
      final rv = (ref[key]! - refHipCentre) * (1.0 / refScale);
      dot += lv.x * rv.x + lv.y * rv.y + lv.z * rv.z;
      normL += lv.x * lv.x + lv.y * lv.y + lv.z * lv.z;
      normR += rv.x * rv.x + rv.y * rv.y + rv.z * rv.z;
    }

    final denom = sqrt(normL) * sqrt(normR);
    if (denom < 1e-9) return 50.0;
    final cosSim = (dot / denom).clamp(-1.0, 1.0);
    return ((cosSim + 1.0) / 2.0) * 100.0;
  }

  static double _torsoScale(Map<String, _Vector3D> kp) {
    final lSh = kp['leftShoulder'], rSh = kp['rightShoulder'];
    final lHip = kp['leftHip'], rHip = kp['rightHip'];
    if (lSh == null || rSh == null || lHip == null || rHip == null) return 1.0;
    final avg = ((lSh - lHip).norm() +
            (rSh - rHip).norm() +
            (lSh - rHip).norm() +
            (rSh - lHip).norm()) /
        4.0;
    return avg < 1e-6 ? 1.0 : avg;
  }

  static Map<String, _Vector3D> _extractPoints(
    Map<String, dynamic> pose, {
    bool mirrorX = false,
  }) {
    final result = <String, _Vector3D>{};
    for (final entry in pose.entries) {
      final v = entry.value;
      if (v is! Map) continue;
      final vis = (v['lh'] as num?)?.toDouble() ?? 0.0;
      if (vis < visibilityThreshold) continue;
      final x = (v['x'] as num).toDouble();
      final y = (v['y'] as num).toDouble();
      final z = (v['z'] as num?)?.toDouble() ?? 0.0;
      result[entry.key] = _Vector3D(mirrorX ? -x : x, y, z, vis);
    }
    return result;
  }

  static List<String> _makeFeedback(
    Map<String, double> components,
    Map<String, double> directionSigns,
  ) {
    final bad = components.entries
        .where((e) => e.value < feedbackThreshold)
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final result = <String>[];
    for (final entry in bad.take(2)) {
      final name = entry.key;
      final score = entry.value;
      final sign = directionSigns[name] ?? 0.0;

      String msg;
      if (name == 'Trunk lean') {
        msg = score < 50.0
            ? (sign > 0
                ? 'Lean your torso forward more'
                : 'Stand more upright')
            : (sign > 0
                ? 'Lean your torso forward slightly'
                : 'Straighten your posture slightly');
      } else {
        final triplet = _triplets.firstWhere(
          (t) => t.name == name,
          orElse: () => _triplets.first,
        );
        if (score < 50.0) {
          msg = sign > 0 ? triplet.feedHigh : triplet.feedLow;
        } else {
          final base = sign > 0 ? triplet.feedHigh : triplet.feedLow;
          msg = 'Fine-tune: ${base[0].toLowerCase()}${base.substring(1)}';
        }
      }
      result.add(msg);
    }
    return result;
  }

  static bool _isReliable(Map<String, _Vector3D> p) {
    return const ['leftShoulder', 'rightShoulder', 'leftHip', 'rightHip']
        .every(p.containsKey);
  }

  static double calculateMatch(
    Map<String, dynamic> live,
    Map<String, dynamic> reference,
  ) =>
      evaluate(live, reference).score;

  static String getGuidance(
    Map<String, dynamic> live,
    Map<String, dynamic> reference,
  ) {
    final result = evaluate(live, reference);
    return result.feedback.isEmpty ? 'Hold it right there' : result.feedback.first;
  }
}

class _Vector3D {
  final double x, y, z, visibility;
  const _Vector3D(this.x, this.y, this.z, [this.visibility = 1.0]);

  _Vector3D operator +(_Vector3D o) =>
      _Vector3D(x + o.x, y + o.y, z + o.z, (visibility + o.visibility) / 2.0);
  _Vector3D operator -(_Vector3D o) =>
      _Vector3D(x - o.x, y - o.y, z - o.z, (visibility + o.visibility) / 2.0);
  _Vector3D operator *(double s) => _Vector3D(x * s, y * s, z * s, visibility);

  double dot(_Vector3D o) => x * o.x + y * o.y + z * o.z;

  _Vector3D cross(_Vector3D o) => _Vector3D(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  double norm() => sqrt(x * x + y * y + z * z);

  _Vector3D? unit() {
    final n = norm();
    return n > 1e-6 ? _Vector3D(x / n, y / n, z / n, visibility) : null;
  }
}
