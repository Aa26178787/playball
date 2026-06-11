// wasm-safe 스텁 — 등록만 받고 아무것도 안 함 (웹 토큰 저장 = _SafeStore/SharedPreferences)
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

class FlutterSecureStorageWeb {
  static void registerWith(Registrar registrar) {}
}
