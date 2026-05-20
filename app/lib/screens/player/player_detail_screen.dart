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
      setState(() {
        _playerData = data;
        _isLoading = false;
      });
    } catch (e) {
      print('선수 상세 오류: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

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
            // 프로필 헤더
            Container(
              padding: const EdgeInsets.all(24),
              color: const Color(0xFF1A237E),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundImage: player['profile_image'] != null
                        ? NetworkImage(player['profile_image'])
                        : null,
                    child: player['profile_image'] == null
                        ? const Icon(Icons.person, size: 40)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          player['name'] ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${player['team'] ?? ''} | ${(player['position'] != null && player['position'].toString().isNotEmpty) ? player['position'] : player['player_type'] ?? ''}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                        ),
                        Text(
                          '#${player['number'] ?? ''}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 기본 정보
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('기본 정보',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const Divider(),
                      _infoRow('생년월일', player['birth_date'] ?? '-'),
                      _infoRow('신장/체중',
                          '${player['height'] ?? '-'}cm / ${player['weight'] ?? '-'}kg'),
                      _infoRow('팀', player['team'] ?? '-'),
                      _infoRow('투타', '${player['throws'] ?? '-'} / ${player['bats'] ?? '-'}'),
                    ],
                  ),
                ),
              ),
            ),

            // 시즌 통계
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('2026 시즌 통계',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const Divider(),
                      if (_playerData!['stats'] != null &&
                          (_playerData!['stats'] as List).isNotEmpty)
                        ..._buildStats()
                      else
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              '아직 시즌 기록이 없습니다',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStats() {
    final statsList = _playerData!['stats'] as List?;
    if (statsList == null || statsList.isEmpty) return [];

    final stats = statsList[0];

    if (_playerData!['player_type'] == '타자') {
      return [
        _infoRow('경기', '${stats['games'] ?? '-'}'),
        _infoRow('타율', (stats['avg'] as num?)?.toStringAsFixed(3) ?? '-'),
        _infoRow('출루율', (stats['obp'] as num?)?.toStringAsFixed(3) ?? '-'),
        _infoRow('장타율', (stats['slg'] as num?)?.toStringAsFixed(3) ?? '-'),
        _infoRow('OPS', (stats['ops'] as num?)?.toStringAsFixed(3) ?? '-'),
        _infoRow('안타', '${stats['hits'] ?? '-'}'),
        _infoRow('2루타', '${stats['doubles'] ?? '-'}'),
        _infoRow('3루타', '${stats['triples'] ?? '-'}'),
        _infoRow('홈런', '${stats['home_runs'] ?? '-'}'),
        _infoRow('타점', '${stats['rbis'] ?? '-'}'),
        _infoRow('득점', '${stats['runs'] ?? '-'}'),
        _infoRow('볼넷', '${stats['walks'] ?? '-'}'),
        _infoRow('삼진', '${stats['strikeouts'] ?? '-'}'),
        _infoRow('도루', '${stats['stolen_bases'] ?? '-'}'),
        _infoRow('BABIP', (stats['babip'] as num?)?.toStringAsFixed(3) ?? '-'),
        _infoRow('ISO', (stats['iso'] as num?)?.toStringAsFixed(3) ?? '-'),
        _infoRow('wOBA', (stats['woba'] as num?)?.toStringAsFixed(3) ?? '-'),
        _infoRow('wRC+', '${stats['wrc_plus'] ?? '-'}'),
        _infoRow('WAR', (stats['war'] as num?)?.toStringAsFixed(2) ?? '-'),
        // 기존 스탯 아래에 추가
        _infoRow('타석', '${stats['pa'] ?? '-'}'),
        _infoRow('루타', '${stats['tb'] ?? '-'}'),
        _infoRow('병살타', '${stats['gdp'] ?? '-'}'),
        _infoRow('희생번트', '${stats['sac'] ?? '-'}'),
        _infoRow('희생플라이', '${stats['sf'] ?? '-'}'),
        _infoRow('고의사구', '${stats['ibb'] ?? '-'}'),
        _infoRow('몸에 맞는 볼', '${stats['hbp'] ?? '-'}'),
        _infoRow('도루실패', '${stats['cs'] ?? '-'}'),
        _infoRow('실책', '${stats['errors'] ?? '-'}'),
        _infoRow('득점권타율', (stats['risp'] as num?)?.toStringAsFixed(3) ?? '-'),
        _infoRow('대타타율', (stats['ph_ba'] as num?)?.toStringAsFixed(3) ?? '-'),
      ];
    } else {
      return [
        _infoRow('경기', '${stats['games'] ?? '-'}'),
        _infoRow('ERA', (stats['era'] as num?)?.toStringAsFixed(2) ?? '-'),
        _infoRow('WHIP', (stats['whip'] as num?)?.toStringAsFixed(2) ?? '-'),
        _infoRow('승', '${stats['wins'] ?? '-'}'),
        _infoRow('패', '${stats['losses'] ?? '-'}'),
        _infoRow('세이브', '${stats['saves'] ?? '-'}'),
        _infoRow('홀드', '${stats['holds'] ?? '-'}'),
        _infoRow('이닝', '${stats['innings_pitched'] ?? '-'}'),
        _infoRow('삼진', '${stats['strikeouts'] ?? '-'}'),
        _infoRow('볼넷', '${stats['walks'] ?? '-'}'),
        _infoRow('피안타', '${stats['hits_allowed'] ?? '-'}'),
        _infoRow('피홈런', '${stats['home_runs_allowed'] ?? '-'}'),
        _infoRow('WAR', (stats['war'] as num?)?.toStringAsFixed(2) ?? '-'),
        _infoRow('블론세이브', '${stats['blown_saves'] ?? '-'}'),
        _infoRow('퀄리티스타트', '${stats['qs'] ?? '-'}'),
        _infoRow('완투', '${stats['cg'] ?? '-'}'),
        _infoRow('완봉', '${stats['sho'] ?? '-'}'),
        _infoRow('피안타', '${stats['hits_allowed'] ?? '-'}'),
        _infoRow('실점', '${stats['runs_allowed'] ?? '-'}'),
        _infoRow('자책점', '${stats['earned_runs'] ?? '-'}'),
        _infoRow('피홈런', '${stats['home_runs_allowed'] ?? '-'}'),
        _infoRow('고의사구', '${stats['ibb'] ?? '-'}'),
        _infoRow('몸에 맞는 볼', '${stats['hbp'] ?? '-'}'),
        _infoRow('보크', '${stats['bk'] ?? '-'}'),
        _infoRow('폭투', '${stats['wp'] ?? '-'}'),
        _infoRow('FIP', (stats['fip'] as num?)?.toStringAsFixed(2) ?? '-'),
        _infoRow('K/9', (stats['k_per_9'] as num?)?.toStringAsFixed(2) ?? '-'),
        _infoRow('BB/9', (stats['bb_per_9'] as num?)?.toStringAsFixed(2) ?? '-'),
        _infoRow('피안타율', (stats['avg_against'] as num?)?.toStringAsFixed(3) ?? '-'),
      ];
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[400])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}