import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../api/api_service.dart';

/// 서버 원격 설정 (/app-config) — 강제 업데이트 · 기능 킬스위치 · 공지 배너 · 시즌 단계
///
/// 앱 시작 시 [load] 1회. 서버 값 변경은 psql(app_config 테이블), 60초 캐시 후 전파.
class AppConfig {
  static Map<String, dynamic> _cfg = {};
  static String appVersion = '';

  /// 공지 배너 {message, level(info|warn), url?} — 홈 상단이 구독
  static final ValueNotifier<Map<String, dynamic>?> bannerNotifier =
      ValueNotifier(null);

  static Future<void> load() async {
    try {
      appVersion = (await PackageInfo.fromPlatform()).version;
    } catch (e) {
      debugPrint('app_config: $e');
    }
    _cfg = await ApiService.getAppConfig() ?? {};
    final b = _cfg['banner'];
    bannerNotifier.value =
        (b is Map && (b['message'] as String?)?.isNotEmpty == true)
            ? Map<String, dynamic>.from(b)
            : null;
  }

  /// 현재 버전 < min_version → 강제 업데이트 (네트워크 실패/파싱 실패 시 false)
  static bool get forceUpdate {
    final min = _cfg['min_version'];
    if (min is! String || appVersion.isEmpty) return false;
    return _compare(appVersion, min) < 0;
  }

  /// 기능 킬스위치 — kill_switches에서 명시적으로 false인 기능만 비활성
  /// 예: AppConfig.enabled('prediction')
  static bool enabled(String feature) {
    final ks = _cfg['kill_switches'];
    if (ks is Map) return ks[feature] != false;
    return true;
  }

  /// preseason | regular | postseason | offseason
  static String get seasonPhase =>
      (_cfg['season_phase'] as String?) ?? 'regular';

  static int _compare(String a, String b) {
    final pa = a
        .split('.')
        .map((s) => int.tryParse(s.replaceAll(RegExp(r'\D'), '')) ?? 0)
        .toList();
    final pb = b
        .split('.')
        .map((s) => int.tryParse(s.replaceAll(RegExp(r'\D'), '')) ?? 0)
        .toList();
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}
