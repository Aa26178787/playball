// 웹 뒤로가기(브라우저 back/스와이프백) → 앱 내 Navigator.pop 매핑.
// Flutter 웹 SPA는 푸시 라우트가 브라우저 히스토리에 안 쌓여, back 하면
// /app/ 문서 자체를 이탈 → 흰화면/앱 종료. 더미 히스토리 1칸을 유지하며
// popstate를 가로채 앱 내 뒤로가기로 변환.
//
// ⚠️ dart:js_interop 기반 — wasm(dart2wasm)은 dart:html 미지원이라
// 구 dart:html 버전은 wasm 본판에서 통째로 스텁 처리돼 죽어 있었음 (06-12 발견).
// 조건 import도 dart.library.js_interop 사용.
import 'dart:js_interop';

@JS('window.history.pushState')
external void _pushState(JSAny? data, String unused, String url);

@JS('window.history.state')
external JSAny? get _historyState;

@JS('window.location.href')
external String get _href;

@JS('window.addEventListener')
external void _addEventListener(String type, JSFunction callback);

void installWebBackHandler(bool Function() onBack) {
  // ⚠️ Flutter 엔진도 history.state(serialCount)를 사용 — null로 덮으면
  // 엔진 popstate 처리가 깨질 수 있어 현재 state를 그대로 보존해 재푸시
  _pushState(_historyState, '', _href);
  _addEventListener(
    'popstate',
    ((JSAny? event) {
      onBack();
      // 루트여도 잔류 — PWA에서 문서 이탈 = 흰화면이라 '나가기'가 의미 없음
      _pushState(_historyState, '', _href);
    }).toJS,
  );
}
