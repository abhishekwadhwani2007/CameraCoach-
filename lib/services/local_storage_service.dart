import 'dart:io';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../utils/logger.dart';

/// Stores reference photos locally and their metadata in encrypted storage.
class LocalStorageService {
  static const String _activeReferenceKey = 'active_reference';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static final List<String> _inMemoryRefs = [];

  // ---------------------------------------------------------------------------
  // Scoped temp directory — all CameraCoach temp files live here, never in the
  // system temp root, so cleanup never risks touching unrelated app files.
  // ---------------------------------------------------------------------------
  static Future<Directory> _getScopedTempDir() async {
    final systemTemp = await getTemporaryDirectory();
    final scopedDir = Directory('${systemTemp.path}/camera_coach_temp');
    if (!await scopedDir.exists()) {
      await scopedDir.create(recursive: true);
    }
    return scopedDir;
  }

  /// Returns the scoped temp directory path for use by other services.
  static Future<String> getScopedTempPath() async {
    return (await _getScopedTempDir()).path;
  }

  static Future<void> saveReference({
    required String originalImagePath,
    required String keypointsJson,
    required double width,
    required double height,
    String? outlinePath,
    String? proSettingsJson,
  }) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final String id = const Uuid().v4();
      final String fileName = '$id.jpg';
      final String localPath = '${directory.path}/$fileName';
      String? persistedOutlinePath;

      final File imageFile = File(originalImagePath);
      await imageFile.copy(localPath);
      if (outlinePath != null && outlinePath.isNotEmpty) {
        final outlineFile = File(outlinePath);
        if (await outlineFile.exists()) {
          persistedOutlinePath = '${directory.path}/${id}_overlay.png';
          await outlineFile.copy(persistedOutlinePath);
        }
      }

      final Map<String, dynamic> metadata = {
        'id': id,
        'imagePath': localPath,
        'outlinePath': persistedOutlinePath,
        'keypointsJson': keypointsJson,
        'proSettingsJson': proSettingsJson,
        'width': width,
        'height': height,
        'createdAt': DateTime.now().toIso8601String(),
      };

      final encoded = jsonEncode(metadata);
      await _storage.write(key: _activeReferenceKey, value: encoded);

      _inMemoryRefs
        ..clear()
        ..add(encoded);

      AppLogger.info('Reference saved (encrypted): $id');
    } catch (e) {
      AppLogger.error('Failed to save reference: $e');
      rethrow;
    }
  }

  static Future<void> clearSessionReference() async {
    await _storage.delete(key: _activeReferenceKey);
    _inMemoryRefs.clear();
  }

  static Future<Map<String, dynamic>?> getSessionReference() async {
    String? encoded;
    if (_inMemoryRefs.isNotEmpty) {
      encoded = _inMemoryRefs.first;
    } else {
      encoded = await _storage.read(key: _activeReferenceKey);
      if (encoded != null) _inMemoryRefs.add(encoded);
    }

    if (encoded == null) return null;

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) {
        AppLogger.error('Corrupt reference data: unexpected type');
        await _storage.delete(key: _activeReferenceKey);
        return null;
      }
      return decoded;
    } catch (e) {
      AppLogger.error('Failed to parse session reference: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getAllReferences() async {
    try {
      return _inMemoryRefs
          .map((item) => jsonDecode(item) as Map<String, dynamic>)
          .toList()
          .reversed
          .toList();
    } catch (e) {
      AppLogger.error('Failed to load local references: $e');
      return [];
    }
  }

  static Future<void> deleteReference(String id) async {
    try {
      // Remove the matching entry from the in-memory list while also cleaning
      // up the stored image and overlay files from disk.
      _inMemoryRefs.removeWhere((item) {
        final map = jsonDecode(item) as Map<String, dynamic>;
        if (map['id'] == id) {
          // Fire-and-forget file deletion — errors are non-fatal here.
          final imagePath = map['imagePath'] as String?;
          if (imagePath != null) File(imagePath).delete().catchError((_) {});
          final outlinePath = map['outlinePath'] as String?;
          if (outlinePath != null) File(outlinePath).delete().catchError((_) {});
          return true;
        }
        return false;
      });

      final active = await _storage.read(key: _activeReferenceKey);
      if (active != null) {
        try {
          final map = jsonDecode(active);
          if (map is Map<String, dynamic> && map['id'] == id) {
            await _storage.delete(key: _activeReferenceKey);
          }
        } catch (_) {}
      }
    } catch (e) {
      AppLogger.error('Failed to delete reference: $e');
    }
  }

  /// Removes temporary CameraCoach files left behind by interrupted capture
  /// flows. Only touches the scoped camera_coach_temp/ subdirectory — this
  /// method will never delete files belonging to other apps.
  static Future<void> cleanOrphanedReferences() async {
    try {
      final scopedDir = await _getScopedTempDir();
      if (!await scopedDir.exists()) return;

      final entities = scopedDir.listSync();
      for (final entity in entities) {
        if (entity is File) {
          try {
            await entity.delete();
            AppLogger.info(
              'Cleaned orphaned temp file: '
              '${entity.path.split(Platform.pathSeparator).last}',
            );
          } catch (_) {
            // Non-fatal — skip locked or already-deleted files.
          }
        }
      }
    } catch (e) {
      AppLogger.error('Startup cleanup failed: $e');
    }
  }
}
