import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalCache {
  static const _prefix = 'lc_';

  static Future<void> set(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefix$key',
      jsonEncode({'d': value, 't': DateTime.now().millisecondsSinceEpoch}),
    );
  }

  static Future<dynamic> get(String key, {int maxAgeSeconds = 86400}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$key');
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final age = (DateTime.now().millisecondsSinceEpoch - (map['t'] as int)) / 1000;
      if (age > maxAgeSeconds) return null;
      return map['d'];
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
  }

  // 로그아웃 시 호출 — 유저 개인 데이터 캐시 삭제
  static Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    final toRemove = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final k in toRemove) {
      await prefs.remove(k);
    }
  }
}
