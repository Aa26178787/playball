import 'package:flutter/foundation.dart';

/// Flutter web CanvasKit는 CORS 헤더 없는 외부 이미지를 canvas에 렌더 못 함.
/// 네이버(pstatic) 이미지를 같은 도메인 nginx 프록시(`/ni/<host>/<path>`)로 우회.
/// web에서만 변환 — 네이티브 앱(Android/iOS)은 원본 URL 직접 로드.
String webSafeImageUrl(String? url) {
  if (url == null || url.isEmpty) return url ?? '';
  if (!kIsWeb) return url;
  // https://<host>/<path> → /ni/<host>/<path> (pstatic 계열만)
  final m = RegExp(r'^https?://((?:sports-phinf|phinf|ssl)\.pstatic\.net)/(.*)$')
      .firstMatch(url);
  if (m != null) {
    return 'https://playball.duckdns.org/ni/${m.group(1)}/${m.group(2)}';
  }
  return url;
}
