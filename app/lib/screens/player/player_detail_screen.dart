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
          _statRow([('G', _s(stats['games'])), ('PA', _s(stats['pa'])), ('AB', _s(stats['at_bats'])), ('H', _s(stats['hits']))]),
          _statRow([('2B', _s(stats['doubles'])), ('3B', _s(stats['triples'])), ('HR', _s(stats['home_runs'])), ('RBI', _s(stats['rbis']))]),
          _statRow([('R', _s(stats['runs'])), ('SB', _s(stats['stolen_bases'])), ('SBA', _s(stats['sba'])), ('CS', _s(stats['cs']))]),
          _statRow([('BB', _s(stats['walks'])), ('IBB', _s(stats['ibb'])), ('HBP', _s(stats['hbp'])), ('SO', _s(stats['strikeouts']))]),
          _statRow([('GDP', _s(stats['gdp'])), ('SAC', _s(stats['sac'])), ('SF', _s(stats['sf'])), ('TB', _s(stats['tb']))]),
        ]),
        _statCard('비율 지표', [
          _statRow([('AVG', _s(stats['avg'], rate: true)), ('OBP', _s(stats['obp'], rate: true)), ('SLG', _s(stats['slg'], rate: true)), ('OPS', _s(stats['ops'], rate: true))]),
          _statRow([('RISP', _s(stats['risp'], rate: true)), ('PH-BA', _s(stats['ph_ba'], rate: true)), ('MH', _s(stats['mh'])), ('도루율', stats['sb_pct'] != null ? '${(stats['sb_pct'] as num).toStringAsFixed(1)}%' : '-')]),
        ]),
        _statCard('고급 지표', [
          _statRow([('wOBA', _s(stats['woba'], rate: true)), ('wRC+', _s(stats['wrc_plus'])), ('BABIP', _s(stats['babip'], rate: true)), ('ISO', _s(stats['iso'], rate: true))]),
          _statRow([('WAR', _s(stats['war'], dec: 2)), ('', ''), ('', ''), ('', '')]),
        ]),
        _statCard('수비', [
          _statRow([('E', _s(stats['errors'])), ('FPCT', _s(stats['fpct'], rate: true)), ('DP', _s(stats['dp'])), ('PO', _s(stats['po']))]),
          _statRow([('보살', _s(stats['assists'])), if (_playerData!['position'] == '포수') ('PB', _s(stats['pb'])) else ('', ''), ('', ''), ('', '')]),
        ]),
      ];
    } else {
      return [
        _statCard('기본 기록', [
          _statRow([('G', _s(stats['games'])), ('W', _s(stats['wins'])), ('L', _s(stats['losses'])), ('SV', _s(stats['saves']))]),
          _statRow([('HLD', _s(stats['holds'])), ('IP', _s(stats['innings_pitched'], dec: 1)), ('H', _s(stats['hits_allowed'])), ('HR', _s(stats['home_runs_allowed']))]),
          _statRow([('BB', _s(stats['walks'])), ('HBP', _s(stats['hbp'])), ('SO', _s(stats['strikeouts'])), ('R', _s(stats['runs_allowed']))]),
          _statRow([('ER', _s(stats['earned_runs'])), ('TBF', _s(stats['tbf'])), ('NP', _s(stats['np'])), ('', '')]),
        ]),
        _statCard('성적 지표', [
          _statRow([('ERA', _s(stats['era'], dec: 2)), ('WHIP', _s(stats['whip'], dec: 2)), ('WPCT', _s(stats['wpct'], rate: true)), ('QS', _s(stats['qs']))]),
          _statRow([('BS', _s(stats['blown_saves'])), ('CG', _s(stats['cg'])), ('SHO', _s(stats['sho'])), ('피안타율', _s(stats['avg_against'], rate: true))]),
        ]),
        _statCard('고급 지표', [
          _statRow([('FIP', _s(stats['fip'], dec: 2)), ('K/9', _s(stats['k_per_9'], dec: 2)), ('BB/9', _s(stats['bb_per_9'], dec: 2)), ('BABIP', _s(stats['babip'], rate: true))]),
          _statRow([('WAR', _s(stats['war'], dec: 2)), ('', ''), ('', ''), ('', '')]),
        ]),
        _statCard('투구 상세', [
          _statRow([('2B허용', _s(stats['doubles_allowed'])), ('3B허용', _s(stats['triples_allowed'])), ('SAC', _s(stats['sac'])), ('SF', _s(stats['sf']))]),
          _statRow([('IBB', _s(stats['ibb'])), ('WP', _s(stats['wp'])), ('BK', _s(stats['bk'])), ('', '')]),
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
