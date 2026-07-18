/// Debug logger stripped from release builds via assert().
class AppLogger {
  static void info(String message) {
    assert(() {
      // ignore: avoid_print
      print('[PoseCoach INFO] $message');
      return true;
    }());
  }

  static void error(String message, [Object? error, StackTrace? stack]) {
    assert(() {
      // ignore: avoid_print
      print('[PoseCoach ERROR] $message ${error ?? ''} ${stack ?? ''}');
      return true;
    }());
  }

  static void debug(String message) {
    assert(() {
      // ignore: avoid_print
      print('[PoseCoach DEBUG] $message');
      return true;
    }());
  }
}
