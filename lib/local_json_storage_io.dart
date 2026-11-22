import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class LocalJsonStorage {
  LocalJsonStorage({Directory? customDirectory})
      : _customDirectory = customDirectory;

  final Directory? _customDirectory;
  final Map<String, Future<void>> _pendingWrites = {};
  Directory? _resolvedDirectory;

  Future<File> getFile(String filename) async {
    final dir = await _resolveDirectory();
    return File('${dir.path}/$filename');
  }

  Future<Directory> _resolveDirectory() async {
    if (_customDirectory != null) return _customDirectory!;
    if (_resolvedDirectory != null) return _resolvedDirectory!;

    try {
      final directory = await getApplicationDocumentsDirectory();
      _resolvedDirectory = directory;
      return directory;
    } catch (_) {
      try {
        final directory = await getApplicationSupportDirectory();
        _resolvedDirectory = directory;
        return directory;
      } catch (_) {
        final directory = Directory.current;
        _resolvedDirectory = directory;
        return directory;
      }
    }
  }

  Future<String?> readString(String filename) async {
    try {
      final pendingWrite = _pendingWrites[filename];
      if (pendingWrite != null) await pendingWrite;
      final file = await getFile(filename);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (e) {
      debugPrint('Error reading $filename: $e');
      return null;
    }
  }

  Future<void> writeString(String filename, String content) async {
    final previousWrite = _pendingWrites[filename] ?? Future<void>.value();
    final write = previousWrite.then((_) async {
      try {
        final file = await getFile(filename);
        final parent = file.parent;
        if (!await parent.exists()) {
          await parent.create(recursive: true);
        }
        await file.writeAsString(content, flush: true);
      } catch (e) {
        debugPrint('Error writing $filename: $e');
      }
    });
    _pendingWrites[filename] = write;

    try {
      await write;
    } finally {
      if (identical(_pendingWrites[filename], write)) {
        _pendingWrites.remove(filename);
      }
    }
  }

  Future<Map<String, dynamic>?> readJsonMap(String filename) async {
    final content = await readString(filename);
    if (content == null || content.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(content);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJsonMap(String filename, Map<String, dynamic> data) async {
    await writeString(filename, const JsonEncoder.withIndent('  ').convert(data));
  }

  Future<List<dynamic>?> readJsonList(String filename) async {
    final content = await readString(filename);
    if (content == null || content.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(content);
      return decoded is List<dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJsonList(String filename, List<dynamic> list) async {
    await writeString(filename, const JsonEncoder.withIndent('  ').convert(list));
  }
}
