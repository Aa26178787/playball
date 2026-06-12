// dart:js_interop 기반 (wasm 호환 — dart:html 버전은 wasm서 스텁 처리됐었음).
import 'dart:js_interop';

@JS('window.location.reload')
external void _reload();

void reloadPage() => _reload();
