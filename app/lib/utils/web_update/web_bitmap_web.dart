// Safari 26 이미지 파이프라인 우회의 마지막 조각:
// 바이트 → Blob → createImageBitmap(실기기 PASS) → 엔진에 비트맵 직접 주입.
// 엔진의 <img>/blob-img 디코드 경로를 단 한 단계도 거치지 않음.
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

@JS('Blob')
extension type _JSBlob._(JSObject _) implements JSObject {
  external factory _JSBlob(JSArray<JSAny?> parts);
}

@JS('createImageBitmap')
external JSPromise<JSAny?> _createImageBitmap(_JSBlob blob, JSAny? options);

Future<ui.Image> bytesToUiImage(Uint8List bytes) async {
  final blob = _JSBlob([bytes.toJS as JSAny?].toJS);
  // ⚠️ premultiplyAlpha = 'none' (straight). skwasm(wasm 렌더러)이 ImageBitmap을
  // straight-alpha로 가정하고 GPU 업로드 시 한 번 premultiply함. bitmap을 'premultiply'로
  // 주면 이중 premultiply → 반투명 픽셀(로고/프로필 안티앨리어싱 엣지)이 다크모드(어두운
  // 배경)서 눈에 띄게 어두워짐 (라이트 배경선 미미) — 06-14 다크모드 이미지 어두움 사고.
  // 'none'이면 엔진이 한 번만 premultiply → 합성 정확. (다운스케일도 엔진이 premultiplied
  // 텍스처에서 수행하므로 검은 프린지 없음.)
  final options = {
    'premultiplyAlpha': 'none',
    'colorSpaceConversion': 'default',
  }.jsify();
  final bitmap = await _createImageBitmap(blob, options).toDart;
  return ui_web.createImageFromImageBitmap(bitmap!);
}
