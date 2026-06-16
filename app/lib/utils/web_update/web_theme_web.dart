// 웹 작업표시줄(브라우저 툴바/주소창) 색 동기화 — meta theme-color 동적 갱신.
// js_interop extension type 멤버 호출 (직접 함수 바인딩 = this 깨짐 — web_back 참고).
import 'dart:js_interop';

@JS('document')
external JSObject get _documentObj;

extension type _Document._(JSObject _) implements JSObject {
  external JSObject? querySelector(String selector);
  external JSObject createElement(String tag);
  external JSObject? get head;
}

extension type _Element._(JSObject _) implements JSObject {
  external void setAttribute(String name, String value);
  external void appendChild(JSObject node);
}

void _setMeta(String name, String content) {
  final doc = _Document._(_documentObj);
  var meta = doc.querySelector('meta[name="$name"]');
  if (meta == null) {
    meta = doc.createElement('meta');
    _Element._(meta).setAttribute('name', name);
    final head = doc.head;
    if (head != null) _Element._(head).appendChild(meta);
  }
  _Element._(meta).setAttribute('content', content);
}

void setWebThemeColor(String hex) => _setMeta('theme-color', hex);

// color-scheme = **resolved 앱테마 추종**(OS 무관). 앱=라이트 → 'light'면 브라우저가
// 페이지를 라이트로 확정 → Chrome Auto Dark/UA 다크틴트가 팀로고·선수이미지 어둡게 하는 것 차단.
// 앱=다크 → 'dark' 선언(Auto Dark off 유지). 정적 'light dark'는 OS 다크 시 브라우저가
// 다크 적용해 라이트모드 앱서도 이미지 어두워지던 원인(06-14 mega 후속).
void setWebColorScheme(String scheme) => _setMeta('color-scheme', scheme);
