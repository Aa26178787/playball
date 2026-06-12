// 웹 뒤로가기(브라우저 back·안드로이드 제스처·iOS 스와이프) → 앱 내 Navigator.pop.
//
// 이 앱은 Navigator 1.0(MaterialApp home + push)이라 엔진이 브라우저 히스토리에
// 엔트리를 안 쌓음 → OS back = 즉시 문서 이탈(이전 사이트). didPopRoute도 호출
// 기회가 없음. 더미 히스토리 1칸 유지 + popstate 가로채기가 유일한 방어선.
//
// ⚠️ js_interop 함정 2개 (06-12):
//  ① dart.library.html 조건 import → wasm서 스텁 로드 (dart:js_interop으로 재작성)
//  ② @JS('window.history.pushState') 직접 함수 바인딩 → this 바인딩 깨져
//     "Illegal invocation" TypeError로 조용히 실패. extension type 멤버 호출 필수.
import 'dart:js_interop';

@JS('history')
external JSObject get _historyObj;

@JS('location')
external JSObject get _locationObj;

@JS()
external void addEventListener(String type, JSFunction callback);

extension type _History._(JSObject _) implements JSObject {
  external void pushState(JSAny? data, String unused, String url);
  external JSAny? get state;
}

extension type _Location._(JSObject _) implements JSObject {
  external String get href;
}

void installWebBackHandler(bool Function() onBack) {
  final history = _History._(_historyObj);
  final location = _Location._(_locationObj);
  // ⚠️ Flutter 엔진도 history.state를 쓸 수 있어 현재 state 보존 재푸시
  history.pushState(history.state, '', location.href);
  addEventListener(
    'popstate',
    ((JSAny? event) {
      onBack();
      // 루트여도 잔류 — PWA에서 문서 이탈 = 흰화면/이전 사이트라 '나가기' 무의미
      history.pushState(history.state, '', location.href);
    }).toJS,
  );
}
