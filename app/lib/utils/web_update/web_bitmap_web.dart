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
external JSPromise<JSAny?> _createImageBitmap(_JSBlob blob);

Future<ui.Image> bytesToUiImage(Uint8List bytes) async {
  final blob = _JSBlob([bytes.toJS as JSAny?].toJS);
  final bitmap = await _createImageBitmap(blob).toDart;
  return ui_web.createImageFromImageBitmap(bitmap!);
}
