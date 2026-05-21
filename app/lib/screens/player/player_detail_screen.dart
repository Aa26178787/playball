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
      appBar: AppBar(title: Text(player['name'] ?? '')),
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
        _statCard('기본 기록', [
          _statRow([('경기', _s(stats['games'])), ('타석', _s(stats['pa'])), ('타수', _s(stats['at_bats'])), ('안타', _s(stats['hits']))]),
          _statRow([('2루타', _s(stats['doubles'])), ('3루타', _s(stats['triples'])), ('홈런', _s(stats['home_runs'])), ('타점', _s(stats['rbis']))]),
          _statRow([('득점', _s(stats['runs'])), ('도루', _s(stats['stolen_bases'])), ('도루시도', _s(stats['sba'])), ('도루실패', _s(stats['cs']))]),
          _statRow([('볼넷', _s(stats['walks'])), ('고의사구', _s(stats['ibb'])), ('사구', _s(stats['hbp'])), ('삼진', _s(stats['strikeouts']))]),
          _statRow([('병살타', _s(stats['gdp'])), ('희생번트', _s(stats['sac'])), ('희생플라이', _s(stats['sf'])), ('루타', _s(stats['tb']))]),
        ]),
        _statCard('비율 지표', [
          _statRow([('타율', _s(stats['avg'], rate: true)), ('출루율', _s(stats['obp'], rate: true)), ('장타율', _s(stats['slg'], rate: true)), ('출루장타율', _s(stats['ops'], rate: true))]),
          _statRow([('득점권타율', _s(stats['risp'], rate: true)), ('대타타율', _s(stats['ph_ba'], rate: true)), ('멀티히트', _s(stats['mh'])), ('도루율', stats['sb_pct'] != null ? '${(stats['sb_pct'] as num).toStringAsFixed(1)}%' : '-')]),
          _statRow([('투구수/타석', stats['p_pa'] != null ? (stats['p_pa'] as num).toStringAsFixed(2) : '-'), ('', ''), ('', ''), ('', '')]),
        ]),
        _statCard('고급 지표', [
          _statRow([('가중출루율', _s(stats['woba'], rate: true)), ('조정득점창출', _s(stats['wrc_plus'])), ('인플레이타율', _s(stats['babip'], rate: true)), ('순장타율', _s(stats['iso'], rate: true))]),
          _statRow([('대체승리기여', _s(stats['war'], dec: 2)), ('', ''), ('', ''), ('', '')]),
        ]),
        _statCard('수비', [
          _statRow([('실책', _s(stats['errors'])), ('수비율', _s(stats['fpct'], rate: true)), ('병살', _s(stats['dp'])), ('자살', _s(stats['po']))]),
          _statRow([('보살', _s(stats['assists'])), if (_playerData!['position'] == '포수') ('포일', _s(stats['pb'])) else ('', ''), ('', ''), ('', '')]),
        ]),
      ];
    } else {
      return [
        _statCard('기본 기록', [
          _statRow([('경기', _s(stats['games'])), ('승', _s(stats['wins'])), ('패', _s(stats['losses'])), ('세이브', _s(stats['saves']))]),
          _statRow([('홀드', _s(stats['holds'])), ('이닝', _s(stats['innings_pitched'], dec: 1)), ('피안타', _s(stats['hits_allowed'])), ('피홈런', _s(stats['home_runs_allowed']))]),
          _statRow([('볼넷', _s(stats['walks'])), ('사구', _s(stats['hbp'])), ('삼진', _s(stats['strikeouts'])), ('실점', _s(stats['runs_allowed']))]),
          _statRow([('자책점', _s(stats['earned_runs'])), ('상대타자', _s(stats['tbf'])), ('투구수', _s(stats['np'])), ('', '')]),
        ]),
        _statCard('성적 지표', [
          _statRow([('평균자책점', _s(stats['era'], dec: 2)), ('이닝당출루', _s(stats['whip'], dec: 2)), ('승률', _s(stats['wpct'], rate: true)), ('퀄리티스타트', _s(stats['qs']))]),
          _statRow([('블론세이브', _s(stats['blown_saves'])), ('완투', _s(stats['cg'])), ('완봉', _s(stats['sho'])), ('피안타율', _s(stats['avg_against'], rate: true))]),
          _statRow([('선발', _s(stats['gs'])), ('구원종료', _s(stats['gf'])), ('세이브기회', _s(stats['svo'])), ('', '')]),
        ]),
        _statCard('고급 지표', [
          _statRow([('수비무관자책', _s(stats['fip'], dec: 2)), ('9이닝삼진', _s(stats['k_per_9'], dec: 2)), ('9이닝볼넷', _s(stats['bb_per_9'], dec: 2)), ('인플레이타율', _s(stats['babip'], rate: true))]),
          _statRow([('대체승리기여', _s(stats['war'], dec: 2)), ('', ''), ('', ''), ('', '')]),
        ]),
        _statCard('투구 상세', [
          _statRow([('2루타허용', _s(stats['doubles_allowed'])), ('3루타허용', _s(stats['triples_allowed'])), ('희생번트', _s(stats['sac'])), ('희생플라이', _s(stats['sf']))]),
          _statRow([('고의사구', _s(stats['ibb'])), ('폭투', _s(stats['wp'])), ('보크', _s(stats['bk'])), ('', '')]),
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
