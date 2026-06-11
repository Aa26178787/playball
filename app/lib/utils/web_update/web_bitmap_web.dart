// Safari 26 이미지 파이프라인 우회의 마지막 조각:
// 바이트 → Blob → createImageBitmap(실기기 PASS) → 엔진에 비트맵 직접 주입.
// 엔진의 <img>/blob-img 디코드 경로를 단 한 단계도 거치지 않음.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

Future<ui.Image> bytesToUiImage(Uint8List bytes) async {
  final blob = html.Blob([bytes]);
  final bitmap = await js_util.promiseToFuture<Object>(
      js_util.callMethod(html.window, 'createImageBitmap', [blob]));
  return ui_web.createImageFromImageBitmap(bitmap);
}
