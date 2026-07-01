import 'package:flutter_test/flutter_test.dart';
import 'package:playball/screens/futures/futures_game_detail_screen.dart';

void main() {
  test('futuresSummaryEntries drops empty and 없음 values', () {
    final e = futuresSummaryEntries({
      '결승타': '유로결(1회)', '홈런': '', '2루타': '없음', '심판': '정은재',
    });
    expect(e.map((x) => x.key).toList(), ['결승타', '심판']);
  });

  test('futuresSummaryEntries handles null', () {
    expect(futuresSummaryEntries(null), isEmpty);
  });

  test('futuresAvgLabel formats number as .XXX', () {
    expect(futuresAvgLabel(0.5), '.500');
    expect(futuresAvgLabel(0.333), '.333');
    expect(futuresAvgLabel(1.0), '1.000');
    expect(futuresAvgLabel(null), '-');
    expect(futuresAvgLabel('x'), '-');
  });
}
