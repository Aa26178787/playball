import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import 'player_detail_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PlayerCompareScreen extends StatefulWidget {
  const PlayerCompareScreen({super.key});

  @override
  State<PlayerCompareScreen> createState() => _PlayerCompareScreenState();
}

class _PlayerCompareScreenState extends State<PlayerCompareScreen> {
  final _ctrl1 = TextEditingController();
  final _ctrl2 = TextEditingController();

  List _results1 = [];
  List _results2 = [];

  Map<String, dynamic>? _player1;
  Map<String, dynamic>? _player2;

  bool _loading1 = false;
  bool _loading2 = false;

  Future<void> _search(int slot, String query) async {
    if (query.length < 1) {
      setState(() => slot == 1 ? _results1 = [] : _results2 = []);
      return;
    }
    try {
      final data = await ApiService.searchPlayers(query);
      if (mounted) {
        setState(() {
          if (slot == 1) _results1 = data['players'] ?? [];
          else _results2 = data['players'] ?? [];
        });
      }
    } catch (_) {}
  }

  Future<void> _selectPlayer(int slot, Map p) async {
    final id = p['id'] as int;
    setState(() {
      if (slot == 1) { _results1 = []; _ctrl1.text = p['name'] ?? ''; _loading1 = true; }
      else { _results2 = []; _ctrl2.text = p['name'] ?? ''; _loading2 = true; }
    });
    try {
      final data = await ApiService.getPlayerDetail(id);
      if (mounted) {
        setState(() {
          if (slot == 1) { _player1 = data; _loading1 = false; }
          else { _player2 = data; _loading2 = false; }
        });
      }
    } catch (_) {
      setState(() => slot == 1 ? _loading1 = false : _loading2 = false);
    }
  }

  @override
  void dispose() {
    _ctrl1.dispose();
    _ctrl2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('선수 비교')),
      body: Column(
        children: [
          _buildSearchRow(),
          const Divider(height: 1),
          Expanded(
            child: (_player1 == null && _player2 == null)
                ? const Center(
                    child: Text('두 선수를 검색하여 비교해보세요',
                        style: TextStyle(color: Colors.grey)))
                : _buildComparison(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchRow() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(child: _buildSearchField(1, _ctrl1, _results1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('VS',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[400])),
          ),
          Expanded(child: _buildSearchField(2, _ctrl2, _results2)),
        ],
      ),
    );
  }

  Widget _buildSearchField(int slot, TextEditingController ctrl, List results) {
    return Column(
      children: [
        TextField(
          controller: ctrl,
          onChanged: (v) => _search(slot, v),
          decoration: InputDecoration(
            hintText: '선수 검색',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: ctrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      ctrl.clear();
                      setState(() {
                        if (slot == 1) { _results1 = []; _player1 = null; }
                        else { _results2 = []; _player2 = null; }
                      });
                    },
                  )
                : null,
          ),
        ),
        if (results.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: results.length,
              itemBuilder: (_, i) {
                final p = results[i];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundImage: p['profile_image'] != null
                        ? CachedNetworkImageProvider(p['profile_image'])
                        : null,
                    child: p['profile_image'] == null
                        ? const Icon(Icons.person, size: 14)
                        : null,
                  ),
                  title: Text('${p['name']}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text('${p['team']} | ${p['player_type']}',
                      style: const TextStyle(fontSize: 11)),
                  onTap: () => _selectPlayer(slot, p),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildComparison() {
    final p1 = _player1;
    final p2 = _player2;

    final isBothHitter = p1 != null && p2 != null &&
        p1['player_type'] == '타자' && p2['player_type'] == '타자';
    final isBothPitcher = p1 != null && p2 != null &&
        p1['player_type'] == '투수' && p2['player_type'] == '투수';

    final stats1 = (p1?['stats'] as List?)?.isNotEmpty == true
        ? (p1!['stats'] as List)[0] as Map<String, dynamic>
        : null;
    final stats2 = (p2?['stats'] as List?)?.isNotEmpty == true
        ? (p2!['stats'] as List)[0] as Map<String, dynamic>
        : null;

    final rows = isBothHitter
        ? _hitterRows(stats1, stats2)
        : isBothPitcher
            ? _pitcherRows(stats1, stats2)
            : _basicRows(stats1, stats2);

    return SingleChildScrollView(
      child: Column(
        children: [
          // 헤더: 양 선수 프로필
          Container(
            color: const Color(0xFF1A237E),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Row(
              children: [
                Expanded(child: _buildPlayerHeader(p1, _loading1, 1)),
                const Text('VS',
                    style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
                Expanded(child: _buildPlayerHeader(p2, _loading2, 2)),
              ],
            ),
          ),

          // 스탯 비교 테이블
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('기록이 없거나 포지션이 달라 비교할 수 없습니다',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey)),
            )
          else
            ...rows.asMap().entries.map((e) => _buildStatRow(
                e.value['label'] as String,
                e.value['v1'] as String,
                e.value['v2'] as String,
                e.value['higher_is_better'] as bool,
                e.key % 2 == 0,
            )),
        ],
      ),
    );
  }

  Widget _buildPlayerHeader(Map<String, dynamic>? p, bool loading, int slot) {
    if (loading) return const Center(child: CircularProgressIndicator(color: Colors.white));
    if (p == null) {
      return Center(
        child: Text(
          slot == 1 ? '선수 1' : '선수 2',
          style: const TextStyle(color: Colors.white38, fontSize: 14),
        ),
      );
    }
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: p['id']))),
      child: Column(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundImage: p['profile_image'] != null
                ? CachedNetworkImageProvider(p['profile_image'])
                : null,
            backgroundColor: Colors.white24,
            child: p['profile_image'] == null
                ? const Icon(Icons.person, color: Colors.white, size: 28)
                : null,
          ),
          const SizedBox(height: 6),
          Text('${p['name']}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          Text('${p['team']} | ${p['player_type']}',
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String v1, String v2,
      bool higherIsBetter, bool shaded) {
    double? n1 = double.tryParse(v1);
    double? n2 = double.tryParse(v2);
    bool p1Better = false, p2Better = false;
    if (n1 != null && n2 != null && n1 != n2) {
      p1Better = higherIsBetter ? n1 > n2 : n1 < n2;
      p2Better = !p1Better;
    }

    TextStyle boldStyle(bool highlight) => TextStyle(
          fontSize: 14,
          fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
          color: highlight ? const Color(0xFF1A237E) : Colors.black87,
        );

    return Container(
      color: shaded ? const Color(0xFFF5F5F5) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(v1, style: boldStyle(p1Better), textAlign: TextAlign.center)),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.center),
          ),
          Expanded(child: Text(v2, style: boldStyle(p2Better), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  String _s(dynamic v, {int dec = 0, bool rate = false}) {
    if (v == null) return '-';
    if (v is num) {
      if (rate) return v.toStringAsFixed(3);
      if (dec > 0) return v.toStringAsFixed(dec);
      return '${v.toInt()}';
    }
    return '$v';
  }

  List<Map<String, dynamic>> _hitterRows(Map? s1, Map? s2) => [
    {'label': '타율', 'v1': _s(s1?['avg'], rate: true), 'v2': _s(s2?['avg'], rate: true), 'higher_is_better': true},
    {'label': '경기', 'v1': _s(s1?['games']), 'v2': _s(s2?['games']), 'higher_is_better': true},
    {'label': '타석', 'v1': _s(s1?['pa']), 'v2': _s(s2?['pa']), 'higher_is_better': true},
    {'label': '안타', 'v1': _s(s1?['hits']), 'v2': _s(s2?['hits']), 'higher_is_better': true},
    {'label': '홈런', 'v1': _s(s1?['home_runs']), 'v2': _s(s2?['home_runs']), 'higher_is_better': true},
    {'label': '타점', 'v1': _s(s1?['rbis']), 'v2': _s(s2?['rbis']), 'higher_is_better': true},
    {'label': '출루율', 'v1': _s(s1?['obp'], rate: true), 'v2': _s(s2?['obp'], rate: true), 'higher_is_better': true},
    {'label': '장타율', 'v1': _s(s1?['slg'], rate: true), 'v2': _s(s2?['slg'], rate: true), 'higher_is_better': true},
    {'label': 'OPS', 'v1': _s(s1?['ops'], rate: true), 'v2': _s(s2?['ops'], rate: true), 'higher_is_better': true},
    {'label': '득점', 'v1': _s(s1?['runs']), 'v2': _s(s2?['runs']), 'higher_is_better': true},
    {'label': '도루', 'v1': _s(s1?['stolen_bases']), 'v2': _s(s2?['stolen_bases']), 'higher_is_better': true},
    {'label': '삼진', 'v1': _s(s1?['strikeouts']), 'v2': _s(s2?['strikeouts']), 'higher_is_better': false},
    {'label': '볼넷', 'v1': _s(s1?['walks']), 'v2': _s(s2?['walks']), 'higher_is_better': true},
    {'label': 'WAR', 'v1': _s(s1?['war'], dec: 1), 'v2': _s(s2?['war'], dec: 1), 'higher_is_better': true},
  ];

  List<Map<String, dynamic>> _pitcherRows(Map? s1, Map? s2) => [
    {'label': '평균자책점', 'v1': _s(s1?['era'], dec: 2), 'v2': _s(s2?['era'], dec: 2), 'higher_is_better': false},
    {'label': '경기', 'v1': _s(s1?['games']), 'v2': _s(s2?['games']), 'higher_is_better': true},
    {'label': '승', 'v1': _s(s1?['wins']), 'v2': _s(s2?['wins']), 'higher_is_better': true},
    {'label': '패', 'v1': _s(s1?['losses']), 'v2': _s(s2?['losses']), 'higher_is_better': false},
    {'label': '세이브', 'v1': _s(s1?['saves']), 'v2': _s(s2?['saves']), 'higher_is_better': true},
    {'label': '홀드', 'v1': _s(s1?['holds']), 'v2': _s(s2?['holds']), 'higher_is_better': true},
    {'label': '이닝', 'v1': _s(s1?['innings_pitched'], dec: 1), 'v2': _s(s2?['innings_pitched'], dec: 1), 'higher_is_better': true},
    {'label': '탈삼진', 'v1': _s(s1?['strikeouts']), 'v2': _s(s2?['strikeouts']), 'higher_is_better': true},
    {'label': 'WHIP', 'v1': _s(s1?['whip'], dec: 2), 'v2': _s(s2?['whip'], dec: 2), 'higher_is_better': false},
    {'label': 'FIP', 'v1': _s(s1?['fip'], dec: 2), 'v2': _s(s2?['fip'], dec: 2), 'higher_is_better': false},
    {'label': 'K/9', 'v1': _s(s1?['k_per_9'], dec: 1), 'v2': _s(s2?['k_per_9'], dec: 1), 'higher_is_better': true},
    {'label': 'BB/9', 'v1': _s(s1?['bb_per_9'], dec: 1), 'v2': _s(s2?['bb_per_9'], dec: 1), 'higher_is_better': false},
    {'label': 'WAR', 'v1': _s(s1?['war'], dec: 1), 'v2': _s(s2?['war'], dec: 1), 'higher_is_better': true},
  ];

  List<Map<String, dynamic>> _basicRows(Map? s1, Map? s2) {
    if (s1 == null && s2 == null) return [];
    return [
      {'label': '경기', 'v1': _s(s1?['games']), 'v2': _s(s2?['games']), 'higher_is_better': true},
    ];
  }
}
