import 'package:flutter_test/flutter_test.dart';
import 'package:playball/widgets/futures_game_card.dart';

void main() {
  test('groups games by yyyy-MM-dd date prefix', () {
    final games = [
      {'game_id': 'a', 'game_date': '2026-06-01'},
      {'game_id': 'b', 'game_date': '2026-06-01'},
      {'game_id': 'c', 'game_date': '2026-06-02'},
    ];
    final m = groupFuturesGamesByDate(games);
    expect(m.keys.toSet(), {'2026-06-01', '2026-06-02'});
    expect(m['2026-06-01']!.length, 2);
    expect(m['2026-06-02']!.length, 1);
  });

  test('skips null game_date', () {
    final m = groupFuturesGamesByDate([
      {'game_id': 'a', 'game_date': null},
      {'game_id': 'b', 'game_date': '2026-06-02T00:00:00'},
    ]);
    expect(m.keys.toSet(), {'2026-06-02'});
  });

  test('empty input returns empty map', () {
    expect(groupFuturesGamesByDate([]), isEmpty);
  });
}
