import 'package:flutter/material.dart';
import '../../widgets/common_widgets.dart';
import '../../utils/design_tokens.dart';

class PlayerStatsSection extends StatelessWidget {
  final List<dynamic> statsList;
  final String playerType;
  final bool useEng;
  final VoidCallback onToggleEng;
  final String? position;

  const PlayerStatsSection({
    super.key,
    required this.statsList,
    required this.playerType,
    required this.useEng,
    required this.onToggleEng,
    this.position,
  });

  @override
  Widget build(BuildContext context) {
    try {
      if (statsList.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Text('아직 시즌 기록이 없습니다', style: TextStyle(color: Colors.grey)),
        );
      }
      return _buildContent(context);
    } catch (e, st) {
      debugPrint('PlayerStatsSection error: $e\n$st');
      return const AppErrorView(message: '통계를 불러올 수 없습니다');
    }
  }

  String _l(String kor, String eng) => useEng ? eng : kor;

  String _s(dynamic v, {int dec = 0, bool rate = false}) {
    if (v == null) return '-';
    if (v is num) {
      if (rate) return v.toStringAsFixed(3);
      if (dec > 0) return v.toStringAsFixed(dec);
      return '${v.toInt()}';
    }
    return '$v';
  }

  Widget _buildContent(BuildContext context) {
    final stats = statsList[0] as Map<String, dynamic>;
    final isHitter = playerType == '타자';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final toggleWidget = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${stats['season'] ?? ''}시즌 기록',
            style: const TextStyle(
              fontSize: Typo.subtitle, fontWeight: Typo.bold,
            ),
          ),
          GestureDetector(
            onTap: onToggleEng,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: useEng ? SemColor.brand(context) : (isDark ? Colors.grey[800] : Colors.grey[200]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                useEng ? 'ENG' : '한글',
                style: TextStyle(
                  fontSize: Typo.small,
                  fontWeight: Typo.bold,
                  color: useEng ? (isDark ? SemColor.panelDark : Colors.white) : (isDark ? Colors.grey[300] : Colors.black87),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final cards = isHitter ? _hitterCards(stats) : _pitcherCards(stats);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [toggleWidget, ...cards],
    );
  }

  List<Widget> _hitterCards(Map<String, dynamic> stats) {
    return [
      _statCard(_l('기본 기록', 'Batting'), [
        _statRow([
          (_l('경기', 'G'),    _s(stats['games'])),
          (_l('타석', 'PA'),   _s(stats['pa'])),
          (_l('타수', 'AB'),   _s(stats['at_bats'])),
          (_l('안타', 'H'),    _s(stats['hits'])),
        ]),
        _statRow([
          (_l('2루타', '2B'),  _s(stats['doubles'])),
          (_l('3루타', '3B'),  _s(stats['triples'])),
          (_l('홈런', 'HR'),   _s(stats['home_runs'])),
          (_l('타점', 'RBI'),  _s(stats['rbis'])),
        ]),
        _statRow([
          (_l('득점', 'R'),       _s(stats['runs'])),
          (_l('도루', 'SB'),      _s(stats['stolen_bases'])),
          (_l('도루시도', 'SBA'), _s(stats['sba'])),
          (_l('도루실패', 'CS'),  _s(stats['cs'])),
        ]),
        _statRow([
          (_l('볼넷', 'BB'),      _s(stats['walks'])),
          (_l('고의사구', 'IBB'), _s(stats['ibb'])),
          (_l('사구', 'HBP'),     _s(stats['hbp'])),
          (_l('삼진', 'SO'),      _s(stats['strikeouts'])),
        ]),
        _statRow([
          (_l('병살타', 'GDP'),    _s(stats['gdp'])),
          (_l('희생번트', 'SAC'),  _s(stats['sac'])),
          (_l('희생플라이', 'SF'), _s(stats['sf'])),
          (_l('루타', 'TB'),       _s(stats['tb'])),
        ]),
      ]),
      _statCard(_l('비율 지표', 'Rate Stats'), [
        _statRow([
          (_l('타율', 'AVG'),       _s(stats['avg'], rate: true)),
          (_l('출루율', 'OBP'),     _s(stats['obp'], rate: true)),
          (_l('장타율', 'SLG'),     _s(stats['slg'], rate: true)),
          (_l('출루장타율', 'OPS'), _s(stats['ops'], rate: true)),
        ]),
        _statRow([
          (_l('득점권타율', 'RISP'), _s(stats['risp'], rate: true)),
          (_l('대타타율', 'PH-BA'), _s(stats['ph_ba'], rate: true)),
          (_l('멀티히트', 'MH'),    _s(stats['mh'])),
          (_l('도루율', 'SB%'),
            stats['sb_pct'] != null
              ? '${(stats['sb_pct'] as num).toStringAsFixed(1)}%'
              : '-'),
        ]),
        _statRow([
          (_l('투구수/타석', 'P/PA'),
            stats['p_pa'] != null
              ? (stats['p_pa'] as num).toStringAsFixed(2)
              : '-'),
          ('', ''), ('', ''), ('', ''),
        ]),
      ]),
      _statCard(_l('고급 지표', 'Advanced'), [
        _statRow([
          (_l('가중출루율', 'wOBA'),     _s(stats['woba'], rate: true)),
          (_l('조정득점창출', 'wRC+'),   _s(stats['wrc_plus'])),
          (_l('인플레이타율', 'BABIP'),  _s(stats['babip'], rate: true)),
          (_l('순장타율', 'ISO'),        _s(stats['iso'], rate: true)),
        ]),
        _statRow([
          (_l('대체승리기여', 'WAR'), _s(stats['war'], dec: 2)),
          ('', ''), ('', ''), ('', ''),
        ]),
      ]),
      _statCard(_l('수비', 'Defense'), [
        _statRow([
          (_l('실책', 'E'),      _s(stats['errors'])),
          (_l('수비율', 'FPCT'), _s(stats['fpct'], rate: true)),
          (_l('병살', 'DP'),     _s(stats['dp'])),
          (_l('자살', 'PO'),     _s(stats['po'])),
        ]),
        _statRow([
          (_l('보살', 'A'), _s(stats['assists'])),
          if (position == '포수')
            (_l('포일', 'PB'), _s(stats['pb']))
          else
            ('', ''),
          ('', ''), ('', ''),
        ]),
      ]),
    ];
  }

  List<Widget> _pitcherCards(Map<String, dynamic> stats) {
    return [
      _statCard(_l('기본 기록', 'Pitching'), [
        _statRow([
          (_l('경기', 'G'),     _s(stats['games'])),
          (_l('승', 'W'),       _s(stats['wins'])),
          (_l('패', 'L'),       _s(stats['losses'])),
          (_l('세이브', 'SV'),  _s(stats['saves'])),
        ]),
        _statRow([
          (_l('홀드', 'HLD'),    _s(stats['holds'])),
          (_l('이닝', 'IP'),     _s(stats['innings_pitched'], dec: 1)),
          (_l('피안타', 'HA'),   _s(stats['hits_allowed'])),
          (_l('피홈런', 'HRA'),  _s(stats['home_runs_allowed'])),
        ]),
        _statRow([
          (_l('볼넷', 'BB'),   _s(stats['walks'])),
          (_l('사구', 'HBP'),  _s(stats['hbp'])),
          (_l('삼진', 'SO'),   _s(stats['strikeouts'])),
          (_l('실점', 'R'),    _s(stats['runs_allowed'])),
        ]),
        _statRow([
          (_l('자책점', 'ER'),    _s(stats['earned_runs'])),
          (_l('상대타자', 'TBF'), _s(stats['tbf'])),
          (_l('투구수', 'NP'),    _s(stats['np'])),
          ('', ''),
        ]),
      ]),
      _statCard(_l('성적 지표', 'Rate Stats'), [
        _statRow([
          (_l('평균자책점', 'ERA'),   _s(stats['era'], dec: 2)),
          (_l('이닝당출루', 'WHIP'),  _s(stats['whip'], dec: 2)),
          (_l('승률', 'WPCT'),        _s(stats['wpct'], rate: true)),
          (_l('퀄리티스타트', 'QS'),  _s(stats['qs'])),
        ]),
        _statRow([
          (_l('블론세이브', 'BSV'), _s(stats['blown_saves'])),
          (_l('완투', 'CG'),         _s(stats['cg'])),
          (_l('완봉', 'SHO'),        _s(stats['sho'])),
          (_l('피안타율', 'AVG'),    _s(stats['avg_against'], rate: true)),
        ]),
        _statRow([
          (_l('선발', 'GS'),        _s(stats['gs'])),
          (_l('구원종료', 'GF'),    _s(stats['gf'])),
          (_l('세이브기회', 'SVO'), _s(stats['svo'])),
          ('', ''),
        ]),
      ]),
      _statCard(_l('고급 지표', 'Advanced'), [
        _statRow([
          (_l('수비무관자책', 'FIP'),    _s(stats['fip'], dec: 2)),
          (_l('9이닝삼진', 'K/9'),       _s(stats['k_per_9'], dec: 2)),
          (_l('9이닝볼넷', 'BB/9'),      _s(stats['bb_per_9'], dec: 2)),
          (_l('인플레이타율', 'BABIP'),  _s(stats['babip'], rate: true)),
        ]),
        _statRow([
          (_l('대체승리기여', 'WAR'), _s(stats['war'], dec: 2)),
          ('', ''), ('', ''), ('', ''),
        ]),
      ]),
      _statCard(_l('투구 상세', 'Detail'), [
        _statRow([
          (_l('2루타허용', '2BA'), _s(stats['doubles_allowed'])),
          (_l('3루타허용', '3BA'), _s(stats['triples_allowed'])),
          (_l('희생번트', 'SAC'),  _s(stats['sac'])),
          (_l('희생플라이', 'SF'), _s(stats['sf'])),
        ]),
        _statRow([
          (_l('고의사구', 'IBB'), _s(stats['ibb'])),
          (_l('폭투', 'WP'),      _s(stats['wp'])),
          (_l('보크', 'BK'),      _s(stats['bk'])),
          ('', ''),
        ]),
      ]),
    ];
  }

  Widget _statCard(String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel(title),
              const SizedBox(height: 8),
              ...rows,
            ],
          ),
        ),
      ),
    );
  }

  Widget _statRow(List<(String, String)> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: items.map((item) {
          return Expanded(
            child: item.$1.isEmpty
                ? const SizedBox()
                : Column(
                    children: [
                      Text(
                        item.$1,
                        style: TextStyle(
                          fontSize: Typo.caption, color: Colors.grey[500], fontWeight: Typo.semibold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(item.$2, style: const TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.bold)),
                    ],
                  ),
          );
        }).toList(),
      ),
    );
  }

  Widget _sectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: const TextStyle(fontSize: Typo.body, fontWeight: Typo.bold),
      ),
    );
  }
}
