/// App-wide constants for PoseCoach.
class AppConstants {
  AppConstants._();

  // Pose matching
  static const double poseMatchThreshold = 0.97;
  static const int frameSkip = 4;
  static const int maxKeypoints = 33;

  // SharedPreferences keys
  static const String onboardingDoneKey = 'onboarding_done';
  static const String userIdKey = 'user_id';

  // TFLite model
  static const String poseModelPath = 'models/pose_landmark_full.tflite';

  // Onboarding
  static const int totalOnboardingPages = 3;

  // Camera presets (centralised from live session screen)
  static const List<int> isoPresets = [50, 100, 200, 400, 800];
  static const List<String> shutterPresets = [
    '1/4000', '1/2000', '1/1000', '1/500', '1/125', '1/60', '1/15',
    '1s', '4s', '8s', '30s',
  ];
  static const List<String> whiteBalancePresets = [
    'AWB', '2300K', '3200K', '5500K', '6500K', '8000K',
  ];
}

/// Photographic quality assessment thresholds.
class ProThresholds {
  ProThresholds._();

  // Face luminance
  static const double severeUnderExposed = 85.0;
  static const double slightlyDark = 105.0;
  static const double highlightClipping = 215.0;

  // Depth of field
  static const double shallowPro = 8.0;
  static const double deepLimit = 3.0;

  // Dynamic range
  static const double excellentHdr = 180.0;

  // Color temperature
  static const double warmLimit = 145.0;
  static const double coolLimit = 110.0;
}
