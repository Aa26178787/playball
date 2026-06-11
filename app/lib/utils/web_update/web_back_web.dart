// 웹 뒤로가기(브라우저 back/스와이프백) → 앱 내 Navigator.pop 매핑.
// Flutter 웹 SPA는 푸시 라우트가 브라우저 히스토리에 안 쌓여, back 하면
// /app/ 문서 자체를 이탈 → 흰화면 + 풀 리로드(오프라인이면 연결불가).
// 더미 히스토리 1칸을 유지하며 popstate를 가로채 앱 내 뒤로가기로 변환.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void installWebBackHandler(bool Function() onBack) {
  html.window.history.pushState(null, '', html.window.location.href);
  html.window.onPopState.listen((_) {
    onBack();
    // 루트여도 잔류 — PWA에서 문서 이탈 = 흰화면이라 '나가기'가 의미 없음
    html.window.history.pushState(null, '', html.window.location.href);
  });
}
