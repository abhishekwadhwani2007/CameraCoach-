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
      final List<String> toKeep = [];
      for (var item in _inMemoryRefs) {
        final map = jsonDecode(item);
        if (map['id'] == id) {
          final file = File(map['imagePath'] as String);
          if (await file.exists()) await file.delete();
          final outlinePath = map['outlinePath'] as String?;
          if (outlinePath != null) {
            final outline = File(outlinePath);
            if (await outline.exists()) await outline.delete();
          }
        } else {
          toKeep.add(item);
        }
      }
      _inMemoryRefs.clear();
      _inMemoryRefs.addAll(toKeep);

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

  /// Removes temporary images left behind by interrupted capture flows.
  static Future<void> cleanOrphanedReferences() async {
    try {
      final List<Directory> dirsToClean = [];
      try {
        dirsToClean.add(await getTemporaryDirectory());
      } catch (_) {}
      final uuidPattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$',
        caseSensitive: false,
      );

      for (var dir in dirsToClean) {
        if (await dir.exists()) {
          final files = dir.listSync();
          for (var file in files) {
            if (file is File) {
              final name = file.path.split('/').last.split('\\').last;
              if (uuidPattern.hasMatch(name) ||
                  name.toLowerCase().endsWith('.jpg') ||
                  name.toLowerCase().endsWith('.jpeg')) {
                await file.delete();
                AppLogger.info('Cleaned up orphaned session image');
              }
            }
          }
        }
      }
    } catch (e) {
      AppLogger.error('Startup cleanup failed: $e');
    }
  }
}
