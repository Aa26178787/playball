import 'package:flutter/material.dart';
import '../../api/api_service.dart';
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

  final Map<String, List> _hitterCategories = {};
  final Map<String, List> _pitcherCategories = {};

  List _searchResults = [];
  bool _isLoading = true;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  static const List<Map<String, String>> _hitterSorts = [
    {'value': 'avg',       'label': '타율',       'title': '타율왕'},
    {'value': 'home_runs', 'label': '홈런',       'title': '홈런왕'},
    {'value': 'rbis',      'label': '타점',       'title': '타점왕'},
    {'value': 'hits',      'label': '안타',       'title': '안타왕'},
    {'value': 'ops',       'label': '출루장타율', 'title': 'OPS 1위'},
    {'value': 'war',       'label': 'WAR',        'title': 'WAR 1위'},
  ];

  static const List<Map<String, String>> _pitcherSorts = [
    {'value': 'era',        'label': '평균자책점', 'title': 'ERA 1위'},
    {'value': 'wins',       'label': '승',         'title': '승리왕'},
    {'value': 'strikeouts', 'label': '탈삼진',     'title': '삼진왕'},
    {'value': 'whip',       'label': '이닝당출루', 'title': 'WHIP 1위'},
    {'value': 'saves',      'label': '세이브',     'title': '세이브왕'},
    {'value': 'holds',      'label': '홀드',       'title': '홀드왕'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAllCategories();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllCategories() async {
    setState(() => _isLoading = true);
    try {
      final hitterFutures = _hitterSorts.map((s) =>
          ApiService.getHitters(sortBy: s['value']!, limit: 3));
      final pitcherFutures = _pitcherSorts.map((s) =>
          ApiService.getPitchers(sortBy: s['value']!, limit: 3));

      final results = await Future.wait([...hitterFutures, ...pitcherFutures]);

      for (int i = 0; i < _hitterSorts.length; i++) {
        _hitterCategories[_hitterSorts[i]['value']!] =
            results[i]['hitters'] ?? [];
      }
      for (int i = 0; i < _pitcherSorts.length; i++) {
        _pitcherCategories[_pitcherSorts[i]['value']!] =
            results[_hitterSorts.length + i]['pitchers'] ?? [];
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() { _isSearching = false; _searchResults = []; });
      return;
    }
    try {
      final data = await ApiService.searchPlayers(query);
      setState(() {
        _searchResults = data['players'] ?? [];
        _isSearching = true;
      });
    } catch (_) {}
  }

  String _hitterStatValue(Map p, String sortKey) {
    switch (sortKey) {
      case 'avg':       return (p['avg'] as num?)?.toStringAsFixed(3) ?? '-';
      case 'home_runs': return '${p['home_runs'] ?? 0}';
      case 'rbis':      return '${p['rbis'] ?? 0}';
      case 'hits':      return '${p['hits'] ?? 0}';
      case 'ops':       return (p['ops'] as num?)?.toStringAsFixed(3) ?? '-';
      case 'war':       return (p['war'] as num?)?.toStringAsFixed(1) ?? '-';
      default:          return '-';
    }
  }

  String _pitcherStatValue(Map p, String sortKey) {
    switch (sortKey) {
      case 'era':        return (p['era'] as num?)?.toStringAsFixed(2) ?? '-';
      case 'wins':       return '${p['wins'] ?? 0}';
      case 'strikeouts': return '${p['strikeouts'] ?? 0}';
      case 'whip':       return (p['whip'] as num?)?.toStringAsFixed(2) ?? '-';
      case 'saves':      return '${p['saves'] ?? 0}';
      case 'holds':      return '${p['holds'] ?? 0}';
      default:           return '-';
    }
  }

  Widget _buildTitleBadge(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: Colors.amber.withValues(alpha: 0.4), blurRadius: 4, offset: const Offset(0, 1)),
        ],
      ),
      child: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildPodium(List players, String sortKey, String title, bool isHitter) {
    if (players.length < 3) return const SizedBox.shrink();
    final p1 = players[0] as Map;
    final p2 = players[1] as Map;
    final p3 = players[2] as Map;

    Widget slot(Map p, int rank, double height, Color medalColor) {
      final statVal = isHitter
          ? _hitterStatValue(p, sortKey)
          : _pitcherStatValue(p, sortKey);

      return GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: p['id']))),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                CircleAvatar(
                  radius: rank == 1 ? 32 : 24,
                  backgroundImage: p['profile_image'] != null
                      ? NetworkImage(p['profile_image'])
                      : null,
                  backgroundColor: medalColor.withValues(alpha: 0.15),
                  child: p['profile_image'] == null
                      ? Icon(Icons.person, size: rank == 1 ? 28 : 20, color: medalColor)
                      : null,
                ),
                Positioned(
                  bottom: -6,
                  right: -6,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: medalColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [BoxShadow(color: medalColor.withValues(alpha: 0.4), blurRadius: 3)],
                    ),
                    alignment: Alignment.center,
                    child: Text('$rank',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${p['name']}',
                style: TextStyle(fontSize: rank == 1 ? 13 : 11, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis),
            Text('${p['team'] ?? ''}',
                style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(statVal,
                style: TextStyle(
                  fontSize: rank == 1 ? 15 : 13,
                  fontWeight: FontWeight.bold,
                  color: medalColor,
                ),
                textAlign: TextAlign.center),
            if (rank == 1) ...[
              const SizedBox(height: 2),
              _buildTitleBadge(title),
            ],
            const SizedBox(height: 6),
            Container(
              width: rank == 1 ? 90 : 72,
              height: height,
              decoration: BoxDecoration(
                color: medalColor.withValues(alpha: 0.18),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
              alignment: Alignment.center,
              child: Text('$rank위',
                  style: TextStyle(fontSize: 11, color: medalColor, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(child: slot(p2, 2, 52, const Color(0xFFC0C0C0))),
          Expanded(child: slot(p1, 1, 80, const Color(0xFFFFD700))),
          Expanded(child: slot(p3, 3, 38, const Color(0xFFCD7F32))),
        ],
      ),
    );
  }

  Widget _buildCategorySection(Map<String, String> sortInfo, bool isHitter) {
    final key = sortInfo['value']!;
    final label = sortInfo['label']!;
    final title = sortInfo['title']!;
    final players = isHitter ? (_hitterCategories[key] ?? []) : (_pitcherCategories[key] ?? []);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 4, height: 16,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A237E),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A237E),
                    )),
              ],
            ),
          ),
          _buildPodium(players, key, title, isHitter),
        ],
      ),
    );
  }

  Widget _buildCategoryList(bool isHitter) {
    final sorts = isHitter ? _hitterSorts : _pitcherSorts;
    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      children: sorts.map((s) => _buildCategorySection(s, isHitter)).toList(),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return const Center(child: Text('검색 결과가 없습니다'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final p = _searchResults[index] as Map;
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: p['profile_image'] != null ? NetworkImage(p['profile_image']) : null,
            child: p['profile_image'] == null ? const Icon(Icons.person) : null,
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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                isDense: true,
              ),
            ),
          ),
          if (!_isSearching) const Divider(height: 1, thickness: 1),
          Expanded(
            child: _isSearching
                ? _buildSearchResults()
                : _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildCategoryList(true),
                          _buildCategoryList(false),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
