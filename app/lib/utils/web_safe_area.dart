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

/// 탭 헤더의 상태바 아래 추가 여백 — 노치/다이나믹 아일랜드 기기(상태바 영역이
/// 이미 큼, ~59px)는 0, 그 외(갤럭시 ~30px·웹 0px)는 8 (06-13 iOS 헤더 비대 보고)
double headerTopGap(BuildContext context) =>
    MediaQuery.of(context).viewPadding.top > 40 ? 0 : 4;
