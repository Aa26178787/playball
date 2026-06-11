@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playball/widgets/share_cards.dart';
import 'package:playball/utils/app_theme.dart';

// 공유 카드 골든 (메가C 위젯 회귀 방어).
// 카드 = 테마 무관 고정 디자인이라 라이트 1장씩.
// 네트워크 로고는 테스트 HttpClient 400 → fallback(팀 이니셜) 렌더로 결정적.
// cached_network_image의 cache_manager가 path_provider 호출 → mock 채널 필수.
// 갱신: flutter test --update-goldens test/golden
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => '.dart_tool/test_tmp',
  );

  Widget harness(Widget card) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Scaffold(
          backgroundColor: const Color(0xFF222226),
          body: Center(child: card),
        ),
      );

  testWidgets('VisitShareCard', (tester) async {
    await tester.pumpWidget(harness(const VisitShareCard(
      homeCode: 'HH', awayCode: 'LG',
      homeName: '한화', awayName: 'LG',
      result: 'win',
      dateStr: '2026년 6월 12일',
      stadium: '대전',
      memo: '끝내기 직관! 최고의 하루',
    )));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(VisitShareCard),
      matchesGoldenFile('goldens/visit_share_card.png'),
    );
  });

  testWidgets('PlayerShareCard', (tester) async {
    await tester.pumpWidget(harness(const PlayerShareCard(
      name: '김도영',
      teamCode: 'HT',
      teamName: 'KIA',
      position: '내야수',
      number: '5',
      stats: [('타율', '.347'), ('홈런', '38'), ('타점', '109'), ('OPS', '1.067')],
    )));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(PlayerShareCard),
      matchesGoldenFile('goldens/player_share_card.png'),
    );
  });
}
