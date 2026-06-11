// 웹 작업표시줄(브라우저 툴바/주소창) 색 동기화 — meta theme-color 동적 갱신.
// Safari 15+/Android Chrome이 이 값으로 툴바를 칠함. 테마 토글 시 호출.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void setWebThemeColor(String hex) {
  var meta = html.document.querySelector('meta[name="theme-color"]');
  if (meta == null) {
    meta = html.MetaElement()..name = 'theme-color';
    html.document.head?.append(meta);
  }
  meta.setAttribute('content', hex);
}
