import 'dart:async';
import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../utils/team_theme.dart';
import 'player_detail_screen.dart';
import 'player_compare_screen.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List _hitters = [];
  List _pitchers = [];
  bool _hitterLoading = true;
  bool _pitcherLoading = true;

  int _hitterReqId = 0;
  int _pitcherReqId = 0;

  Timer? _hitterDebounce;
  Timer? _pitcherDebounce;

  String _hitterSort = 'avg';
  String _pitcherSort = 'era';

  List _teams = [];
  int? _selectedTeamId;

  List _searchResults = [];
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  static const List<Map<String, String>> _hitterSorts = [
    {'value': 'avg',          'label': '타율'},
    {'value': 'home_runs',    'label': '홈런'},
    {'value': 'rbis',         'label': '타점'},
    {'value': 'hits',         'label': '안타'},
    {'value': 'stolen_bases', 'label': '도루'},
    {'value': 'ops',          'label': 'OPS'},
    {'value': 'war',          'label': 'WAR'},
  ];

  static const List<Map<String, String>> _pitcherSorts = [
    {'value': 'era',        'label': 'ERA'},
    {'value': 'wins',       'label': '승'},
    {'value': 'strikeouts', 'label': '탈삼진'},
    {'value': 'saves',      'label': '세이브'},
    {'value': 'holds',      'label': '홀드'},
    {'value': 'whip',       'label': 'WHIP'},
    {'value': 'war',        'label': 'WAR'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadTeams();
    _loadHitters();
    _loadPitchers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _hitterDebounce?.cancel();
    _pitcherDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadTeams() async {
    try {
      final data = await ApiService.getTeams();
      if (mounted) setState(() => _teams = data['teams'] ?? []);
    } catch (_) {}
  }

  Future<void> _loadHitters() async {
    final reqId = ++_hitterReqId;
    setState(() => _hitterLoading = true);
    try {
      final data = await ApiService.getHitters(sortBy: _hitterSort, limit: 200, teamId: _selectedTeamId);
      if (mounted && reqId == _hitterReqId) {
        setState(() { _hitters = data['hitters'] ?? []; _hitterLoading = false; });
      }
    } catch (_) {
      if (mounted && reqId == _hitterReqId) setState(() => _hitterLoading = false);
    }
  }

  Future<void> _loadPitchers() async {
    final reqId = ++_pitcherReqId;
    setState(() => _pitcherLoading = true);
    try {
      final data = await ApiService.getPitchers(sortBy: _pitcherSort, limit: 200, teamId: _selectedTeamId);
      if (mounted && reqId == _pitcherReqId) {
        setState(() { _pitchers = data['pitchers'] ?? []; _pitcherLoading = false; });
      }
    } catch (_) {
      if (mounted && reqId == _pitcherReqId) setState(() => _pitcherLoading = false);
    }
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() { _isSearching = false; _searchResults = []; });
      return;
    }
    try {
      final data = await ApiService.searchPlayers(query);
      if (mounted) setState(() { _searchResults = data['players'] ?? []; _isSearching = true; });
    } catch (_) {}
  }

  String _hitterStat(Map p) {
    switch (_hitterSort) {
      case 'avg':          return (p['avg'] as num?)?.toStringAsFixed(3) ?? '-';
      case 'home_runs':    return '${p['home_runs'] ?? 0}';
      case 'rbis':         return '${p['rbis'] ?? 0}';
      case 'hits':         return '${p['hits'] ?? 0}';
      case 'stolen_bases': return '${p['stolen_bases'] ?? 0}';
      case 'ops':          return (p['ops'] as num?)?.toStringAsFixed(3) ?? '-';
      case 'war':          return (p['war'] as num?)?.toStringAsFixed(1) ?? '-';
      default:             return '-';
    }
  }

  String _pitcherStat(Map p) {
    switch (_pitcherSort) {
      case 'era':        return (p['era'] as num?)?.toStringAsFixed(2) ?? '-';
      case 'wins':       return '${p['wins'] ?? 0}';
      case 'strikeouts': return '${p['strikeouts'] ?? 0}';
      case 'saves':      return '${p['saves'] ?? 0}';
      case 'holds':      return '${p['holds'] ?? 0}';
      case 'whip':       return (p['whip'] as num?)?.toStringAsFixed(2) ?? '-';
      case 'war':        return (p['war'] as num?)?.toStringAsFixed(1) ?? '-';
      default:           return '-';
    }
  }

  Widget _buildTeamFilterChips(void Function(int?) onSelect) {
    return SizedBox(
      height: 34,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
        itemCount: _teams.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            final sel = _selectedTeamId == null;
            return GestureDetector(
              onTap: () => onSelect(null),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFF1A237E) : Colors.grey.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text('전체',
                    style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.black87,
                        fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
              ),
            );
          }
          final t = _teams[i - 1] as Map;
          final tid = t['id'] as int?;
          final code = t['short_name'] as String? ?? '';
          final sel = _selectedTeamId == tid;
          return GestureDetector(
            onTap: () => onSelect(tid),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: sel ? teamColor(code) : Colors.grey.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: sel ? null : Border.all(color: Colors.grey.withValues(alpha: 0.25)),
              ),
              child: Text(t['name'] ?? '',
                  style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.black87,
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSortChips(
    List<Map<String, String>> sorts,
    String selected,
    void Function(String) onSelect,
  ) {
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        itemCount: sorts.length,
        itemBuilder: (_, i) {
          final s = sorts[i];
          final sel = selected == s['value'];
          return GestureDetector(
            onTap: () => onSelect(s['value']!),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: sel ? const Color(0xFF1A237E) : Colors.grey.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                s['label']!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                  color: sel ? Colors.white : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlayerRow(Map p, String statVal, String statLabel) {
    final code = p['team_code'] as String? ?? p['team'] as String? ?? '';
    final img = p['profile_image'] as String?;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: p['id'])),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: teamColor(code).withValues(alpha: 0.15),
              backgroundImage: (img != null && img.isNotEmpty) ? NetworkImage(img) : null,
              child: (img == null || img.isEmpty)
                  ? Text(
                      teamDisplayName(code).characters.take(2).string,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: teamColor(code),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p['name'] ?? '',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  Text('${p['team'] ?? ''}  ${p['position'] ?? ''}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(statVal,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(statLabel,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHitterList() {
    if (_hitters.isEmpty) {
      if (_hitterLoading) return const Center(child: CircularProgressIndicator());
      return const Center(child: Text('데이터가 없습니다'));
    }
    final label = _hitterSorts.firstWhere((s) => s['value'] == _hitterSort)['label']!;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _hitters.length,
      separatorBuilder: (context2, idx) => Divider(height: 1, indent: 52, endIndent: 16, color: Colors.grey.withValues(alpha: 0.15)),
      itemBuilder: (_, i) => _buildPlayerRow(_hitters[i] as Map, _hitterStat(_hitters[i] as Map), label),
    );
  }

  Widget _buildPitcherList() {
    if (_pitchers.isEmpty) {
      if (_pitcherLoading) return const Center(child: CircularProgressIndicator());
      return const Center(child: Text('데이터가 없습니다'));
    }
    final label = _pitcherSorts.firstWhere((s) => s['value'] == _pitcherSort)['label']!;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _pitchers.length,
      separatorBuilder: (context2, idx) => Divider(height: 1, indent: 52, endIndent: 16, color: Colors.grey.withValues(alpha: 0.15)),
      itemBuilder: (_, i) => _buildPlayerRow(_pitchers[i] as Map, _pitcherStat(_pitchers[i] as Map), label),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) return const Center(child: Text('검색 결과가 없습니다'));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _searchResults.length,
      itemBuilder: (_, i) {
        final p = _searchResults[i] as Map;
        final img = p['profile_image'] as String?;
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: (img != null && img.isNotEmpty) ? NetworkImage(img) : null,
            child: (img == null || img.isEmpty) ? const Icon(Icons.person) : null,
          ),
          title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${p['team'] ?? ''} | ${p['player_type'] ?? ''} | #${p['number'] ?? '-'}'),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: p['id']))),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('선수 기록'),
        actions: [
          IconButton(
            icon: const Icon(Icons.compare_arrows),
            tooltip: '선수 비교',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PlayerCompareScreen())),
          ),
        ],
        bottom: _isSearching
            ? null
            : TabBar(
                controller: _tabController,
                tabs: const [Tab(text: '타자'), Tab(text: '투수')],
              ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _searchController,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: '선수 이름 검색',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() { _isSearching = false; _searchResults = []; });
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                isDense: true,
              ),
            ),
          ),
          if (!_isSearching) ...[
            const Divider(height: 1, thickness: 1),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  Column(
                    children: [
                      const SizedBox(height: 6),
                      _buildSortChips(_hitterSorts, _hitterSort, (val) {
                        setState(() => _hitterSort = val);
                        _hitterDebounce?.cancel();
                        _hitterDebounce = Timer(const Duration(milliseconds: 250), _loadHitters);
                      }),
                      const SizedBox(height: 4),
                      _buildTeamFilterChips((tid) {
                        setState(() => _selectedTeamId = tid);
                        _loadHitters();
                      }),
                      const SizedBox(height: 4),
                      const Divider(height: 1),
                      Expanded(child: _buildHitterList()),
                    ],
                  ),
                  Column(
                    children: [
                      const SizedBox(height: 6),
                      _buildSortChips(_pitcherSorts, _pitcherSort, (val) {
                        setState(() => _pitcherSort = val);
                        _pitcherDebounce?.cancel();
                        _pitcherDebounce = Timer(const Duration(milliseconds: 250), _loadPitchers);
                      }),
                      const SizedBox(height: 4),
                      _buildTeamFilterChips((tid) {
                        setState(() => _selectedTeamId = tid);
                        _loadPitchers();
                      }),
                      const SizedBox(height: 4),
                      const Divider(height: 1),
                      Expanded(child: _buildPitcherList()),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            const Divider(height: 1, thickness: 1),
            Expanded(child: _buildSearchResults()),
          ],
        ],
      ),
    );
  }
}
