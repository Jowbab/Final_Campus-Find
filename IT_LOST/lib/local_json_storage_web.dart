import 'dart:convert';

class LocalJsonStorage {
  LocalJsonStorage();

  static final Map<String, String> _memoryStore = {};

  Future<String?> readString(String filename) async => _memoryStore[filename];

  Future<void> writeString(String filename, String content) async {
    _memoryStore[filename] = content;
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

