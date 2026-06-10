import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
    // _cb: 프록시 Origin-403 수정 전 캐싱된 실패응답 우회용 캐시버스터 (값 바뀌면 강제 재요청)
    final sep = m.group(2)!.contains('?') ? '&' : '?';
    return 'https://playball.duckdns.org/ni/${m.group(1)}/${m.group(2)}${sep}_cb=2';
  }
  return url;
}

/// 플랫폼 안전 ImageProvider (CircleAvatar.backgroundImage 등):
/// web=NetworkImage / native=CachedNetworkImageProvider. URL 자동 프록시 변환.
ImageProvider netImageProvider(String url) {
  final u = webSafeImageUrl(url);
  return kIsWeb ? NetworkImage(u) : CachedNetworkImageProvider(u);
}

/// 플랫폼 안전 네트워크 이미지 위젯:
/// - web: `Image.network`(CanvasKit 렌더 안정 — cached_network_image web 지원 불안정)
/// - native: `CachedNetworkImage`(디스크 캐시)
/// URL은 자동으로 webSafeImageUrl 변환.
Widget netImage(
  String? url, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  FilterQuality filterQuality = FilterQuality.medium,
  int? memCacheWidth,
  int? memCacheHeight,
  Widget Function()? error,
  Widget Function()? placeholder,
}) {
  final u = webSafeImageUrl(url);
  if (u.isEmpty) return error?.call() ?? const SizedBox.shrink();
  if (kIsWeb) {
    return Image.network(
      u,
      width: width,
      height: height,
      fit: fit,
      filterQuality: filterQuality,
      errorBuilder: (_, __, ___) => error?.call() ?? const SizedBox.shrink(),
      loadingBuilder: (ctx, child, prog) =>
          prog == null ? child : (placeholder?.call() ?? child),
    );
  }
  return CachedNetworkImage(
    imageUrl: u,
    width: width,
    height: height,
    fit: fit,
    filterQuality: filterQuality,
    memCacheWidth: memCacheWidth,
    memCacheHeight: memCacheHeight,
    fadeInDuration: Duration.zero,
    fadeOutDuration: Duration.zero,
    errorWidget: (_, __, ___) => error?.call() ?? const SizedBox.shrink(),
    placeholder: placeholder != null ? (_, __) => placeholder() : null,
  );
}
