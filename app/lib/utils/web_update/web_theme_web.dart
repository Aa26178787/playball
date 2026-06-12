// 웹 작업표시줄(브라우저 툴바/주소창) 색 동기화 — meta theme-color 동적 갱신.
// Safari 15+/Android Chrome이 이 값으로 툴바를 칠함. 테마 토글 시 호출.
// dart:js_interop 기반 (wasm 호환 — dart:html 버전은 wasm서 스텁 처리됐었음).
import 'dart:js_interop';

@JS('document.querySelector')
external JSObject? _querySelector(String selector);

@JS('document.createElement')
external JSObject _createElement(String tag);

@JS('document.head.appendChild')
external void _headAppend(JSObject node);

extension type _Element._(JSObject _) implements JSObject {
  external void setAttribute(String name, String value);
}

void setWebThemeColor(String hex) {
  var meta = _querySelector('meta[name="theme-color"]');
  if (meta == null) {
    meta = _createElement('meta');
    (_Element._(meta)).setAttribute('name', 'theme-color');
    _headAppend(meta);
  }
  (_Element._(meta)).setAttribute('content', hex);
}
