import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pose_coach/main.dart';

void main() {
  testWidgets('PoseCoach smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PoseCoachApp(showOnboarding: false));
    await tester.pumpAndSettle();

    expect(find.text('PoseCoach'), findsOneWidget);
    expect(find.text('Upload Reference'), findsOneWidget);
    expect(find.byIcon(Icons.add_photo_alternate_rounded), findsOneWidget);
  });
}
