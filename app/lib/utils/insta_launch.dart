import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:url_launcher/url_launcher.dart';

/// 인스타 핸들 또는 URL → 인스타 **앱**으로 열기.
/// 네이티브: `instagram://user?username=` 딥링크(앱) 우선 → 미설치 시 https 폴백.
/// 웹: 딥링크 불가 → https 새 탭(모바일 웹은 앱 전환 프롬프트가 뜰 수 있음).
Future<void> launchInstagram(String handleOrUrl) async {
  if (handleOrUrl.trim().isEmpty) return;
  // 핸들 추출: URL이면 첫 path segment, '@'·슬래시·쿼리 제거
  var handle = handleOrUrl.trim();
  if (handle.contains('instagram.com')) {
    final u = Uri.tryParse(handle);
    final segs = u?.pathSegments.where((s) => s.isNotEmpty).toList() ?? const [];
    if (segs.isNotEmpty) handle = segs.first;
  }
  handle = handle.replaceAll('@', '').replaceAll('/', '').trim();
  if (handle.isEmpty) return;
  final webUri = Uri.parse('https://www.instagram.com/$handle');

  if (!kIsWeb) {
    // 1) 인스타 앱 딥링크 (설치돼 있으면 앱으로 전환)
    try {
      final appUri = Uri.parse('instagram://user?username=$handle');
      final ok = await launchUrl(appUri, mode: LaunchMode.externalNonBrowserApplication);
      if (ok) return;
    } catch (e) { debugPrint('insta: $e'); }
  }
  // 2) 폴백: https (외부 브라우저 / 미설치 시 인스타 웹)
  try {
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  } catch (e) {
    try { await launchUrl(webUri, mode: LaunchMode.platformDefault); } catch (_) {}
  }
}
