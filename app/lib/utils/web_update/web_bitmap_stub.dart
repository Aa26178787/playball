// 비웹 스텁 — 네이티브는 이 경로 미사용
import 'dart:typed_data';
import 'dart:ui' as ui;

Future<ui.Image> bytesToUiImage(Uint8List bytes) =>
    throw UnsupportedError('web 전용');
