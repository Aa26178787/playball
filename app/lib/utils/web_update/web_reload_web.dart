// 페이지 리로드 — js_interop extension type (직접 함수 바인딩 = this 깨짐).
import 'dart:js_interop';

@JS('location')
external JSObject get _locationObj;

extension type _Location._(JSObject _) implements JSObject {
  external void reload();
}

void reloadPage() => _Location._(_locationObj).reload();
