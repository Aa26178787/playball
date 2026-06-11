import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

// js_interop 조건: dart2js와 dart2wasm 양쪽에서 web 구현 사용 (html 조건이면 wasm서 스텁)
import 'web_update/web_bitmap_stub.dart'
    if (dart.library.js_interop) 'web_update/web_bitmap_web.dart';

/// Flutter web CanvasKit는 CORS 헤더 없는 외부 이미지를 canvas에 렌더 못 함.
/// 네이버(pstatic) 이미지를 같은 도메인 nginx 프록시(`/ni/<host>/<path>`)로 우회.
/// web에서만 변환 — 네이티브 앱(Android/iOS)은 원본 URL 직접 로드.
String webSafeImageUrl(String? url) {
  if (url == null || url.isEmpty) return url ?? '';
  if (!kIsWeb) return url;
  // https://<host>/<path> → /ni/<host>/<path> (pstatic 계열 + 위키 로고)
  // 위키: 승팀 워터마크(kTeamOverlayLogoUrls) — _FetchImage(fetch)는 CSP
  // connect-src 적용이라 외부 직접 fetch 불가 → 프록시 필수
  final m = RegExp(
          r'^https?://((?:sports-phinf|phinf|ssl)\.pstatic\.net|upload\.wikimedia\.org)/(.*)$')
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

/// 웹 전용 ImageProvider — Safari 26의 <img> 네트워크 로더가 200 응답에도
/// error 이벤트를 내는 문제 우회: fetch(XHR)로 바이트를 직접 받아 엔진 디코더에
/// 전달 (blob 경유라 네트워크 <img> 미사용). 실기기 진단: fetch=PASS 검증.
class _FetchImage extends ImageProvider<_FetchImage> {
  final String url;
  const _FetchImage(this.url);

  @override
  Future<_FetchImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FetchImage>(this);

  @override
  ImageStreamCompleter loadImage(_FetchImage key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(_loadInfo(key));
  }

  static final Dio _dio = Dio();

  Future<ImageInfo> _loadInfo(_FetchImage key) async {
    final res = await _dio.get<List<int>>(key.url,
        options: Options(responseType: ResponseType.bytes));
    final bytes = Uint8List.fromList(res.data ?? const []);
    if (bytes.isEmpty) {
      throw Exception('빈 이미지 응답: ${key.url}');
    }
    // fetch(PASS) → createImageBitmap(PASS) → 엔진 주입 — <img> 경로 0%
    final image = await bytesToUiImage(bytes);
    return ImageInfo(image: image);
  }

  @override
  bool operator ==(Object other) => other is _FetchImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
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
    // iOS Safari 26에서 플랫폼뷰 포함 빌드 = Safari 탭/standalone 불문 크래시.
    // 네트워크 로드는 _FetchImage(fetch bytes)로 — Safari 26이 <img> 네트워크
    // 로더에 error 이벤트를 내는 문제(200 수신에도) 우회. fetch 경로는 실기기 PASS.
    return Image(
      image: _FetchImage(u),
      width: width,
      height: height,
      fit: fit,
      filterQuality: filterQuality,
      errorBuilder: (_, err, __) => error?.call() ?? const SizedBox.shrink(),
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
