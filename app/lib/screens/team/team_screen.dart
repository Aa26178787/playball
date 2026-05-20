import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../player/player_detail_screen.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List _teams = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadTeams();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTeams() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getTeamRankings();
      setState(() {
        _teams = data['rankings'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String _streakText(int streak) {
    if (streak > 0) return '$streak연승';
    if (streak < 0) return '${-streak}연패';
    return '-';
  }

  Color _streakColor(int streak) {
    if (streak > 0) return Colors.blue;
    if (streak < 0) return Colors.red;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('순위'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '팀 순위'),
            Tab(text: '부문별 순위'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTeamRankings(),
          const PlayerRankingsTab(),
        ],
      ),
    );
  }

  Widget _buildTeamRankings() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadTeams,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                SizedBox(width: 30, child: Text('순위', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(child: Text('팀', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 30, child: Text('G', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 30, child: Text('승', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 30, child: Text('패', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 30, child: Text('무', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 45, child: Text('승률', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 30, child: Text('게차', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 45, child: Text('연속', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ..._teams.map((team) => _buildTeamRow(team)),
        ],
      ),
    );
  }

  Widget _buildTeamRow(Map<String, dynamic> team) {
    final streak = team['streak'] as int? ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text('${team['rank'] ?? '-'}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Expanded(
            child: Text(team['name'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          SizedBox(width: 30, child: Text('${team['total_games'] ?? 0}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          SizedBox(width: 30, child: Text('${team['wins'] ?? 0}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          SizedBox(width: 30, child: Text('${team['losses'] ?? 0}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          SizedBox(width: 30, child: Text('${team['draws'] ?? 0}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          SizedBox(width: 45, child: Text((team['win_rate'] as num?)?.toStringAsFixed(3) ?? '-', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          SizedBox(width: 30, child: Text('${team['games_behind'] ?? '-'}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          SizedBox(
            width: 45,
            child: Text(
              _streakText(streak),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _streakColor(streak)),
            ),
          ),
        ],
      ),
    );
  }
}


class PlayerRankingsTab extends StatefulWidget {
  const PlayerRankingsTab({super.key});

  @override
  State<PlayerRankingsTab> createState() => _PlayerRankingsTabState();
}

class _PlayerRankingsTabState extends State<PlayerRankingsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<Map<String, String>> _hitterCategories = [
    {'value': 'avg',       'label': '타율'},
    {'value': 'home_runs', 'label': '홈런'},
    {'value': 'rbis',      'label': '타점'},
    {'value': 'hits',      'label': '안타'},
    {'value': 'stolen_bases', 'label': '도루'},
    {'value': 'ops',       'label': 'OPS'},
    {'value': 'war',       'label': 'WAR'},
  ];

  final List<Map<String, String>> _pitcherCategories = [
    {'value': 'era',        'label': 'ERA'},
    {'value': 'wins',       'label': '승리'},
    {'value': 'strikeouts', 'label': '탈삼진'},
    {'value': 'saves',      'label': '세이브'},
    {'value': 'holds',      'label': '홀드'},
    {'value': 'whip',       'label': 'WHIP'},
    {'value': 'war',        'label': 'WAR'},
  ];

  String _hitterSort = 'avg';
  String _pitcherSort = 'era';
  List _hitterRankings = [];
  List _pitcherRankings = [];
  bool _hitterLoading = false;
  bool _pitcherLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _pitcherRankings.isEmpty) {
        _loadPitchers();
      }
    });
    _loadHitters();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHitters() async {
    setState(() => _hitterLoading = true);
    try {
      final data = await ApiService.getHitters(sortBy: _hitterSort, limit: 10);
      if (mounted) setState(() { _hitterRankings = data['hitters'] ?? []; _hitterLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _hitterLoading = false);
    }
  }

  Future<void> _loadPitchers() async {
    setState(() => _pitcherLoading = true);
    try {
      final data = await ApiService.getPitchers(sortBy: _pitcherSort, limit: 10);
      if (mounted) setState(() { _pitcherRankings = data['pitchers'] ?? []; _pitcherLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _pitcherLoading = false);
    }
  }

  String _hitterStatValue(Map p) {
    switch (_hitterSort) {
      case 'avg': return (p['avg'] as num?)?.toStringAsFixed(3) ?? '-';
      case 'home_runs': return '${p['home_runs'] ?? '-'}';
      case 'rbis': return '${p['rbis'] ?? '-'}';
      case 'hits': return '${p['hits'] ?? '-'}';
      case 'stolen_bases': return '${p['stolen_bases'] ?? '-'}';
      case 'ops': return (p['ops'] as num?)?.toStringAsFixed(3) ?? '-';
      case 'war': return (p['war'] as num?)?.toStringAsFixed(1) ?? '-';
      default: return '-';
    }
  }

  String _pitcherStatValue(Map p) {
    switch (_pitcherSort) {
      case 'era': return (p['era'] as num?)?.toStringAsFixed(2) ?? '-';
      case 'wins': return '${p['wins'] ?? '-'}';
      case 'strikeouts': return '${p['strikeouts'] ?? '-'}';
      case 'saves': return '${p['saves'] ?? '-'}';
      case 'holds': return '${p['holds'] ?? '-'}';
      case 'whip': return (p['whip'] as num?)?.toStringAsFixed(2) ?? '-';
      case 'war': return (p['war'] as num?)?.toStringAsFixed(1) ?? '-';
      default: return '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF1A237E),
          indicatorColor: const Color(0xFF1A237E),
          tabs: const [Tab(text: '타자'), Tab(text: '투수')],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildHitterRankings(),
              _buildPitcherRankings(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryChips(List<Map<String, String>> categories, String selected, Function(String) onSelect) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = selected == cat['value'];
          return GestureDetector(
            onTap: () => onSelect(cat['value']!),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1A237E) : Colors.grey.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(cat['label']!,
                  style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? Colors.white : null,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHitterRankings() {
    return Column(
      children: [
        _buildCategoryChips(_hitterCategories, _hitterSort, (val) {
          setState(() { _hitterSort = val; _hitterRankings = []; });
          _loadHitters();
        }),
        const SizedBox(height: 8),
        Expanded(
          child: _hitterLoading
              ? const Center(child: CircularProgressIndicator())
              : _hitterRankings.isEmpty
                  ? const Center(child: Text('데이터가 없습니다'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _hitterRankings.length,
                      itemBuilder: (context, index) {
                        final p = _hitterRankings[index];
                        final label = _hitterCategories.firstWhere((c) => c['value'] == _hitterSort)['label']!;
                        return _buildRankRow(
                          rank: index + 1,
                          playerId: p['id'],
                          name: p['name'] ?? '',
                          team: p['team'] ?? '',
                          label: label,
                          value: _hitterStatValue(p),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildPitcherRankings() {
    return Column(
      children: [
        _buildCategoryChips(_pitcherCategories, _pitcherSort, (val) {
          setState(() { _pitcherSort = val; _pitcherRankings = []; });
          _loadPitchers();
        }),
        const SizedBox(height: 8),
        Expanded(
          child: _pitcherLoading
              ? const Center(child: CircularProgressIndicator())
              : _pitcherRankings.isEmpty
                  ? const Center(child: Text('데이터가 없습니다'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _pitcherRankings.length,
                      itemBuilder: (context, index) {
                        final p = _pitcherRankings[index];
                        final label = _pitcherCategories.firstWhere((c) => c['value'] == _pitcherSort)['label']!;
                        return _buildRankRow(
                          rank: index + 1,
                          playerId: p['id'],
                          name: p['name'] ?? '',
                          team: p['team'] ?? '',
                          label: label,
                          value: _pitcherStatValue(p),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildRankRow({
    required int rank,
    required int playerId,
    required String name,
    required String team,
    required String label,
    required String value,
  }) {
    final isTop3 = rank <= 3;
    final rankColors = [Colors.amber, Colors.grey, Colors.brown];

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: playerId)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isTop3
              ? rankColors[rank - 1].withOpacity(0.08)
              : Colors.grey.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isTop3 ? rankColors[rank - 1] : Colors.grey[600],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(team, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
