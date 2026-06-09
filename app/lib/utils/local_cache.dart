import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalCache {
  static const _prefix = 'lc_';
  static SharedPreferences? _prefs;

  // 앱 시작 시 한 번만 초기화 — 이후 동기적으로 재사용
  static Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  static Future<void> set(String key, dynamic value) async {
    final prefs = await _getPrefs();
    await prefs.setString(
      '$_prefix$key',
      jsonEncode({'d': value, 't': DateTime.now().millisecondsSinceEpoch}),
    );
  }

  static Future<dynamic> get(String key, {int maxAgeSeconds = 86400}) async {
    try {
      final prefs = await _getPrefs();
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

  // TTL 무시하고 있으면 무조건 반환 (stale-while-revalidate용)
  static Future<dynamic> getStale(String key) async {
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString('$_prefix$key');
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map['d'];
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String key) async {
    final prefs = await _getPrefs();
    await prefs.remove('$_prefix$key');
  }

  // 1회성 flag (coachmark, onboarding 등 — TTL 없음, 영구 보존)
  static Future<bool> hasFlag(String key) async {
    final prefs = await _getPrefs();
    return prefs.getBool('${_prefix}flag_$key') ?? false;
  }

  static Future<void> setFlag(String key) async {
    final prefs = await _getPrefs();
    await prefs.setBool('${_prefix}flag_$key', true);
  }

  static Future<void> removeFlag(String key) async {
    final prefs = await _getPrefs();
    await prefs.remove('${_prefix}flag_$key');
  }

  // 설정 초기화 — UI 환경설정/토글/도움말 힌트만 제거 (로그인·즐겨찾기 데이터는 유지)
  static Future<void> resetSettings() async {
    final prefs = await _getPrefs();
    final keys = prefs.getKeys().where((k) =>
        k.startsWith('${_prefix}flag_') ||            // 1회성 도움말/온보딩 힌트
        k.startsWith('${_prefix}core_keys_') ||       // 선수별 핵심 기록 커스텀
        k.contains('compact') ||                      // compact 뷰 토글
        k.contains('strip') ||                        // 날짜/구장 스트립 확장 상태
        k.contains('toggle') || k.contains('view_')   // 기타 뷰 토글
    ).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  // 로그아웃 시 호출 — 유저 개인 데이터 캐시 삭제
  static Future<void> clearUser() async {
    final prefs = await _getPrefs();
    final toRemove = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final k in toRemove) {
      await prefs.remove(k);
    }
  }
}
