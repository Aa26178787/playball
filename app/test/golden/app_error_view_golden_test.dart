import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playball/widgets/common_widgets.dart';
import 'package:playball/utils/app_theme.dart';

// 골든 테스트 — 테마 인식 위젯의 라이트/다크 렌더를 PNG로 고정.
// 다크모드 회귀(panelDark·surface·ink 색 깨짐) 자동 검출.
// 갱신: flutter test --update-goldens test/golden
// 첫 타겟 = AppErrorView (네트워크 의존 0, 테마 민감). 확장 시 동일 패턴 추가.
void main() {
  Widget harness(ThemeData theme) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: const Scaffold(
          body: AppErrorView(
            message: '네트워크 연결을 확인해주세요',
            onRetry: _noop,
          ),
        ),
      );

  testWidgets('AppErrorView light', (tester) async {
    await tester.pumpWidget(harness(AppTheme.light()));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(AppErrorView),
      matchesGoldenFile('goldens/app_error_view_light.png'),
    );
  });

  testWidgets('AppErrorView dark', (tester) async {
    await tester.pumpWidget(harness(AppTheme.dark()));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(AppErrorView),
      matchesGoldenFile('goldens/app_error_view_dark.png'),
    );
  });
}

void _noop() {}
