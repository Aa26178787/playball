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
    // _cb: Safari 캐시 오염 우회용 캐시버스터 (값 바뀌면 강제 재요청).
    // _cb=3 (2026-06-11): 과거 no-cors 빌드가 박은 immutable 캐시 엔트리를 엔진의
    // CORS 모드(crossOrigin=anonymous) 요청이 받아 "EncodingError: Loading error."
    // — imgtest 6(신규URL)=PASS/앱(캐시URL)=FAIL로 확정. 범프로 전 URL 신규화.
    final sep = m.group(2)!.contains('?') ? '&' : '?';
    return 'https://playball.duckdns.org/ni/${m.group(1)}/${m.group(2)}${sep}_cb=3';
  }
  return url;
}

/// 플랫폼 안전 ImageProvider (CircleAvatar.backgroundImage 등):
/// web=NetworkImage / native=CachedNetworkImageProvider. URL 자동 프록시 변환.
/// ⚠️ web에서 provider 경로 = CanvasKit 엔진 디코드 = iOS Safari GPU 메모리 누수
/// (flutter#152709, 5-10회 내비 후 크래시) → 웹 도달 위젯은 netCircleAvatar/netImage 사용.
ImageProvider netImageProvider(String url) {
  final u = webSafeImageUrl(url);
  return kIsWeb ? NetworkImage(u) : CachedNetworkImageProvider(u);
}

/// CircleAvatar 대체 — web은 ClipOval+netImage(<img> 엘리먼트)로 그려
/// CanvasKit 디코드(iOS 누수 크래시)를 회피. native는 기존 CircleAvatar 동작.
Widget netCircleAvatar({
  required double radius,
  String? url,
  Color? backgroundColor,
  Widget? child,
}) {
  final has = url != null && url.isNotEmpty;
  if (!kIsWeb) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      backgroundImage: has ? netImageProvider(url) : null,
      child: has ? null : child,
    );
  }
  return SizedBox(
    width: radius * 2,
    height: radius * 2,
    child: ClipOval(
      child: Container(
        color: backgroundColor,
        alignment: Alignment.center,
        child: has
            ? netImage(url, width: radius * 2, height: radius * 2,
                fit: BoxFit.cover, error: () => child ?? const SizedBox.shrink())
            : child,
      ),
    ),
  );
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
    // ⚠️ webHtmlElementStrategy.prefer(<img> 플랫폼뷰) 최종 금지 — A/B 5회 결론:
    // iOS Safari 26에서 플랫폼뷰 포함 빌드 = Safari 탭/standalone 불문 크래시,
    // CanvasKit-only = 유일 안정. iOS 이미지 미표시는 별도 추적(디코드 실패 의심
    // — errorBuilder가 조용히 삼킴. 프록시 재인코딩/CPU렌더/wasm 실험 예정).
    return Image.network(
      u,
      width: width,
      height: height,
      fit: fit,
      filterQuality: filterQuality,
      // 임시 진단(웹): 에러 전문 노출 — 탭하면 다이얼로그로 전체 메시지+스택.
      // 원인 확정 후 SizedBox.shrink()로 되돌릴 것.
      errorBuilder: (ctx, err, stack) => GestureDetector(
        onTap: () => showDialog(
          context: ctx,
          builder: (_) => AlertDialog(
            title: const Text('이미지 에러 전문', style: TextStyle(fontSize: 14)),
            content: SingleChildScrollView(
              child: Text('URL: $u\n\n$err\n\n$stack',
                  style: const TextStyle(fontSize: 11)),
            ),
          ),
        ),
        child: Container(
          width: width,
          height: height,
          color: const Color(0x33FF0000),
          alignment: Alignment.center,
          child: Text('$err', maxLines: 10,
              style: const TextStyle(fontSize: 8, color: Color(0xFFFF5252))),
        ),
      ),
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
