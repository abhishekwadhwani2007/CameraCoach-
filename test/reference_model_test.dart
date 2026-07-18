import 'package:flutter_test/flutter_test.dart';
import 'package:pose_coach/models/reference_model.dart';

void main() {
  group('ReferenceModel', () {
    test('should serialize to correctly mapped Map', () {
      final now = DateTime.now();
      final model = ReferenceModel(
        id: '123',
        imagePath: '/local/ref.jpg',
        outlinePath: '/local/ref_overlay.png',
        createdAt: now,
        keypointsJson: '{"nose": {"x": 100, "y": 200, "lh": 0.99}}',
        proSettingsJson: '{"iso":200}',
        width: 1080,
        height: 1920,
      );

      final map = model.toMap();

      expect(map['id'], '123');
      expect(map['imagePath'], '/local/ref.jpg');
      expect(map['outlinePath'], '/local/ref_overlay.png');
      expect(map['createdAt'], now);
      expect(
          map['keypointsJson'], '{"nose": {"x": 100, "y": 200, "lh": 0.99}}');
      expect(map['proSettingsJson'], '{"iso":200}');
      expect(map['width'], 1080);
      expect(map['height'], 1920);
    });

    test('should handle nullable keypointsJson', () {
      final model = ReferenceModel(
        id: '456',
        createdAt: DateTime.now(),
      );

      final map = model.toMap();
      expect(map['keypointsJson'], isNull);
    });
  });
}
