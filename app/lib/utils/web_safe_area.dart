// iOS 사파리(브라우저 탭) 하단 툴바 보정 — 메가 배포 경로가 웹이라 필수.
// 사파리 탭 모드는 env(safe-area-inset-bottom)이 0으로 와서 viewPadding.bottom=0
// → 하단 고정 UI(플로팅탭/시트)가 사파리 탭바와 겹침/잘림.
// standalone PWA나 안드로이드 크롬은 env가 정상이라 보정 0.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

double webBottomGuard(BuildContext context) {
  if (!kIsWeb) return 0;
  if (defaultTargetPlatform != TargetPlatform.iOS) return 0;
  // env가 이미 잡혔으면(standalone 등) 중복 보정 안 함
  return MediaQuery.of(context).viewPadding.bottom > 0 ? 0 : 20;
}
