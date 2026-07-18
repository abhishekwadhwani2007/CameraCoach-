import 'package:pose_coach/services/pose_comparison_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PoseComparisonService', () {
    test('scores identical poses as a strong match', () {
      final pose = _standingPose();
      final result = PoseComparisonService.evaluate(pose, pose);

      expect(result.score, greaterThan(95.0));
      expect(result.isReliable, isTrue);
    });

    test('returns low reliability when lower body is missing', () {
      final reference = _standingPose();
      final live = Map<String, dynamic>.from(reference)..remove('leftHip');

      final result = PoseComparisonService.evaluate(live, reference);

      expect(result.isReliable, isFalse);
      expect(result.feedback.first, contains('body'));
    });
  });
}

Map<String, dynamic> _standingPose() => {
      'nose': _lm(100, 40),
      'leftEar': _lm(82, 45),
      'rightEar': _lm(118, 45),
      'leftShoulder': _lm(70, 100),
      'rightShoulder': _lm(130, 100),
      'leftElbow': _lm(62, 160),
      'rightElbow': _lm(138, 160),
      'leftWrist': _lm(58, 220),
      'rightWrist': _lm(142, 220),
      'leftHip': _lm(78, 220),
      'rightHip': _lm(122, 220),
      'leftKnee': _lm(78, 320),
      'rightKnee': _lm(122, 320),
      'leftAnkle': _lm(78, 430),
      'rightAnkle': _lm(122, 430),
    };

Map<String, dynamic> _lm(double x, double y) => {'x': x, 'y': y, 'lh': 0.99};
