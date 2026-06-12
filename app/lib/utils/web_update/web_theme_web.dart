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

void setWebThemeColor(String hex) {
  final doc = _Document._(_documentObj);
  var meta = doc.querySelector('meta[name="theme-color"]');
  if (meta == null) {
    meta = doc.createElement('meta');
    _Element._(meta).setAttribute('name', 'theme-color');
    final head = doc.head;
    if (head != null) _Element._(head).appendChild(meta);
  }
  _Element._(meta).setAttribute('content', hex);
}
