import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../utils/logger.dart';

/// Communicates with the Python overlay-generation backend.
///
/// BASE URL is injected at build time via --dart-define so no IP/URL ever
/// lives in source code or version control. Example:
///   flutter run --dart-define=BACKEND_URL=http://192.168.1.10:8000
class BackendApiService {
  static const String _baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: '',
  );

  /// 10 MB client-side guard before any bytes leave the device.
  static const int _maxFileSizeBytes = 10 * 1024 * 1024;

  /// 30-second wall-clock limit for upload + server processing.
  static const Duration _requestTimeout = Duration(seconds: 30);

  static Future<String?> generateOverlay(String imagePath) async {
    if (_baseUrl.trim().isEmpty) {
      AppLogger.error(
        'generateOverlay: BACKEND_URL is not configured. '
        'Run with --dart-define=BACKEND_URL=http://YOUR_PC_IP:8000.',
      );
      return null;
    }

    AppLogger.debug('generateOverlay POST $_baseUrl/api/generate_overlay');
    try {
      final fileSize = await File(imagePath).length();
      if (fileSize > _maxFileSizeBytes) {
        AppLogger.error('generateOverlay: file too large ($fileSize B)');
        return null;
      }

      final uri = Uri.parse('$_baseUrl/api/generate_overlay');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('file', imagePath));

      final streamed = await request.send().timeout(_requestTimeout);

      AppLogger.debug('generateOverlay: HTTP ${streamed.statusCode}');
      if (streamed.statusCode != 200) {
        AppLogger.error('generateOverlay failed: HTTP ${streamed.statusCode}');
        return null;
      }

      final bytes = await streamed.stream.toBytes();
      final directory = await getTemporaryDirectory();
      final output = File(
        '${directory.path}/dynamic_silhouette_'
        '${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await output.writeAsBytes(bytes, flush: true);

      AppLogger.debug('generateOverlay: saved overlay (${bytes.length} B)');
      return output.path;
    } on TimeoutException {
      AppLogger.error(
        'generateOverlay: timed out after ${_requestTimeout.inSeconds}s',
      );
      return null;
    } on SocketException catch (e) {
      AppLogger.error('generateOverlay: network error $e');
      return null;
    } catch (e) {
      AppLogger.error('generateOverlay: $e');
      return null;
    }
  }
}
