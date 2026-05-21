import 'package:flutter/material.dart';
import '../../api/api_service.dart';

class PlayerDetailScreen extends StatefulWidget {
  final int playerId;
  const PlayerDetailScreen({super.key, required this.playerId});

  @override
  State<PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends State<PlayerDetailScreen> {
  Map<String, dynamic>? _playerData;
  bool _isLoading = true;
  bool _useEng = false;

  @override
  void initState() {
    super.initState();
    _loadPlayer();
  }

  Future<void> _loadPlayer() async {
    try {
      final data = await ApiService.getPlayerDetail(widget.playerId);
      setState(() { _playerData = data; _isLoading = false; });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_playerData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('선수 상세')),
        body: const Center(child: Text('선수 정보를 불러오지 못했습니다')),
      );
    }

    final player = _playerData!;
    return Scaffold(
      appBar: AppBar(
        title: Text(player['name'] ?? ''),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: () => setState(() => _useEng = !_useEng),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: _useEng ? Colors.white24 : Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _useEng ? 'ENG' : '한글',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(player),
            _buildInfoCard(player),
            if (_playerData!['stats'] != null && (_playerData!['stats'] as List).isNotEmpty)
              ..._buildStatCards()
            else
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('아직 시즌 기록이 없습니다', style: TextStyle(color: Colors.grey)),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> player) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFF1A237E),
      child: Row(
        children: [
          CircleAvatar(
            radius: 38,
            backgroundImage: player['profile_image'] != null ? NetworkImage(player['profile_image']) : null,
            child: player['profile_image'] == null ? const Icon(Icons.person, size: 38, color: Colors.white) : null,
            backgroundColor: const Color(0xFF283593),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(player['name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                Text(
                  '${player['team'] ?? ''} | ${(player['position'] != null && player['position'].toString().isNotEmpty) ? player['position'] : player['player_type'] ?? ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Text('#${player['number'] ?? '-'}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(Map<String, dynamic> player) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('기본 정보'),
              _infoRow('생년월일', player['birth_date'] ?? '-'),
              _infoRow('신장/체중', '${player['height'] ?? '-'}cm / ${player['weight'] ?? '-'}kg'),
              _infoRow('팀', player['team'] ?? '-'),
              _infoRow('투/타', '${player['throws'] ?? '-'} / ${player['bats'] ?? '-'}'),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStatCards() {
    final statsList = _playerData!['stats'] as List;
    final stats = statsList[0] as Map<String, dynamic>;
    final isHitter = _playerData!['player_type'] == '타자';

    // 한글/영어 라벨 선택
    String _l(String kor, String eng) => _useEng ? eng : kor;

    String _s(dynamic v, {int dec = 0, bool rate = false}) {
      if (v == null) return '-';
      if (v is num) {
        if (rate) return v.toStringAsFixed(3);
        if (dec > 0) return v.toStringAsFixed(dec);
        return '${v.toInt()}';
      }
      return '$v';
    }

    if (isHitter) {
      return [
        _statCard(_l('기본 기록', 'Batting'), [
          _statRow([
            (_l('경기', 'G'),   _s(stats['games'])),
            (_l('타석', 'PA'),  _s(stats['pa'])),
            (_l('타수', 'AB'),  _s(stats['at_bats'])),
            (_l('안타', 'H'),   _s(stats['hits'])),
          ]),
          _statRow([
            (_l('2루타', '2B'), _s(stats['doubles'])),
            (_l('3루타', '3B'), _s(stats['triples'])),
            (_l('홈런', 'HR'),  _s(stats['home_runs'])),
            (_l('타점', 'RBI'), _s(stats['rbis'])),
          ]),
          _statRow([
            (_l('득점', 'R'),     _s(stats['runs'])),
            (_l('도루', 'SB'),    _s(stats['stolen_bases'])),
            (_l('도루시도', 'SBA'), _s(stats['sba'])),
            (_l('도루실패', 'CS'), _s(stats['cs'])),
          ]),
          _statRow([
            (_l('볼넷', 'BB'),    _s(stats['walks'])),
            (_l('고의사구', 'IBB'), _s(stats['ibb'])),
            (_l('사구', 'HBP'),   _s(stats['hbp'])),
            (_l('삼진', 'SO'),    _s(stats['strikeouts'])),
          ]),
          _statRow([
            (_l('병살타', 'GDP'), _s(stats['gdp'])),
            (_l('희생번트', 'SAC'), _s(stats['sac'])),
            (_l('희생플라이', 'SF'), _s(stats['sf'])),
            (_l('루타', 'TB'),    _s(stats['tb'])),
          ]),
        ]),
        _statCard(_l('비율 지표', 'Rate Stats'), [
          _statRow([
            (_l('타율', 'AVG'),     _s(stats['avg'], rate: true)),
            (_l('출루율', 'OBP'),   _s(stats['obp'], rate: true)),
            (_l('장타율', 'SLG'),   _s(stats['slg'], rate: true)),
            (_l('출루장타율', 'OPS'), _s(stats['ops'], rate: true)),
          ]),
          _statRow([
            (_l('득점권타율', 'RISP'), _s(stats['risp'], rate: true)),
            (_l('대타타율', 'PH-BA'), _s(stats['ph_ba'], rate: true)),
            (_l('멀티히트', 'MH'),    _s(stats['mh'])),
            (_l('도루율', 'SB%'),
              stats['sb_pct'] != null ? '${(stats['sb_pct'] as num).toStringAsFixed(1)}%' : '-'),
          ]),
          _statRow([
            (_l('투구수/타석', 'P/PA'),
              stats['p_pa'] != null ? (stats['p_pa'] as num).toStringAsFixed(2) : '-'),
            ('', ''), ('', ''), ('', ''),
          ]),
        ]),
        _statCard(_l('고급 지표', 'Advanced'), [
          _statRow([
            (_l('가중출루율', 'wOBA'),    _s(stats['woba'], rate: true)),
            (_l('조정득점창출', 'wRC+'),  _s(stats['wrc_plus'])),
            (_l('인플레이타율', 'BABIP'), _s(stats['babip'], rate: true)),
            (_l('순장타율', 'ISO'),       _s(stats['iso'], rate: true)),
          ]),
          _statRow([
            (_l('대체승리기여', 'WAR'), _s(stats['war'], dec: 2)),
            ('', ''), ('', ''), ('', ''),
          ]),
        ]),
        _statCard(_l('수비', 'Defense'), [
          _statRow([
            (_l('실책', 'E'),    _s(stats['errors'])),
            (_l('수비율', 'FPCT'), _s(stats['fpct'], rate: true)),
            (_l('병살', 'DP'),   _s(stats['dp'])),
            (_l('자살', 'PO'),   _s(stats['po'])),
          ]),
          _statRow([
            (_l('보살', 'A'), _s(stats['assists'])),
            if (_playerData!['position'] == '포수')
              (_l('포일', 'PB'), _s(stats['pb']))
            else
              ('', ''),
            ('', ''), ('', ''),
          ]),
        ]),
      ];
    } else {
      return [
        _statCard(_l('기본 기록', 'Pitching'), [
          _statRow([
            (_l('경기', 'G'),    _s(stats['games'])),
            (_l('승', 'W'),      _s(stats['wins'])),
            (_l('패', 'L'),      _s(stats['losses'])),
            (_l('세이브', 'SV'), _s(stats['saves'])),
          ]),
          _statRow([
            (_l('홀드', 'HLD'),  _s(stats['holds'])),
            (_l('이닝', 'IP'),   _s(stats['innings_pitched'], dec: 1)),
            (_l('피안타', 'HA'), _s(stats['hits_allowed'])),
            (_l('피홈런', 'HRA'), _s(stats['home_runs_allowed'])),
          ]),
          _statRow([
            (_l('볼넷', 'BB'),  _s(stats['walks'])),
            (_l('사구', 'HBP'), _s(stats['hbp'])),
            (_l('삼진', 'SO'),  _s(stats['strikeouts'])),
            (_l('실점', 'R'),   _s(stats['runs_allowed'])),
          ]),
          _statRow([
            (_l('자책점', 'ER'),  _s(stats['earned_runs'])),
            (_l('상대타자', 'TBF'), _s(stats['tbf'])),
            (_l('투구수', 'NP'),  _s(stats['np'])),
            ('', ''),
          ]),
        ]),
        _statCard(_l('성적 지표', 'Rate Stats'), [
          _statRow([
            (_l('평균자책점', 'ERA'),     _s(stats['era'], dec: 2)),
            (_l('이닝당출루', 'WHIP'),    _s(stats['whip'], dec: 2)),
            (_l('승률', 'WPCT'),          _s(stats['wpct'], rate: true)),
            (_l('퀄리티스타트', 'QS'),    _s(stats['qs'])),
          ]),
          _statRow([
            (_l('블론세이브', 'BSV'), _s(stats['blown_saves'])),
            (_l('완투', 'CG'),         _s(stats['cg'])),
            (_l('완봉', 'SHO'),        _s(stats['sho'])),
            (_l('피안타율', 'AVG'),    _s(stats['avg_against'], rate: true)),
          ]),
          _statRow([
            (_l('선발', 'GS'),      _s(stats['gs'])),
            (_l('구원종료', 'GF'),  _s(stats['gf'])),
            (_l('세이브기회', 'SVO'), _s(stats['svo'])),
            ('', ''),
          ]),
        ]),
        _statCard(_l('고급 지표', 'Advanced'), [
          _statRow([
            (_l('수비무관자책', 'FIP'),   _s(stats['fip'], dec: 2)),
            (_l('9이닝삼진', 'K/9'),      _s(stats['k_per_9'], dec: 2)),
            (_l('9이닝볼넷', 'BB/9'),     _s(stats['bb_per_9'], dec: 2)),
            (_l('인플레이타율', 'BABIP'), _s(stats['babip'], rate: true)),
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
                      Text(item.$1, style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(item.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
      child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A237E))),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
