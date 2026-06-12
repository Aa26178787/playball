// 웹 PWA 인앱 갱신 감지 — 빌드 산출물(flutter_bootstrap.js)의 ETag를 주기 비교,
// 바뀌면 콜백 (홈에서 "새 버전" 스낵바 → 탭 시 리로드).
// no-cache 헤더가 cold start 갱신을 보장하고, 이 체커는 켜둔 세션의 갱신을 커버.
// 앱(모바일)은 no-op (kIsWeb 가드).
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'web_reload_stub.dart' if (dart.library.js_interop) 'web_reload_web.dart';

class WebUpdateChecker {
  static String? _etag;
  static Timer? _timer;
  static bool _notified = false;

  /// onUpdate는 새 빌드 감지 시 1회 호출 (UI 알림용)
  static void start(String baseUrl, void Function() onUpdate) {
    if (!kIsWeb || _timer != null) return;
    Future<void> check() async {
      try {
        final res = await Dio().head('$baseUrl/app/flutter_bootstrap.js',
            options: Options(receiveTimeout: const Duration(seconds: 5)));
        final tag = res.headers.value('etag');
        if (tag == null) return;
        if (_etag == null) {
          _etag = tag; // 첫 측정 = 현재 빌드 기준점
          return;
        }
        if (tag != _etag && !_notified) {
          _notified = true;
          onUpdate();
        }
      } catch (_) {/* 네트워크 일시 오류 무시 */}
    }

    check();
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => check());
  }

  static void applyUpdate() => reloadPage();
}
