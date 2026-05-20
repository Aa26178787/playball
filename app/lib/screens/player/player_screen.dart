import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import 'player_detail_screen.dart';

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
  List _searchResults = [];
  bool _isLoading = true;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  // 필터
  String _hitterSort = 'avg';
  String _pitcherSort = 'era';
  int? _selectedTeamId;

  final List<Map<String, dynamic>> _teams = [
    {'id': null, 'name': '전체'},
    {'id': 1, 'name': 'KT'},
    {'id': 9, 'name': 'LG'},
    {'id': 11, 'name': '삼성'},
    {'id': 10, 'name': 'SSG'},
    {'id': 2, 'name': 'KIA'},
    {'id': 5, 'name': '한화'},
    {'id': 7, 'name': '두산'},
    {'id': 6, 'name': 'NC'},
    {'id': 4, 'name': '롯데'},
    {'id': 8, 'name': '키움'},
  ];

  final List<Map<String, String>> _hitterSortOptions = [
    {'value': 'avg', 'label': '타율'},
    {'value': 'home_runs', 'label': '홈런'},
    {'value': 'rbis', 'label': '타점'},
    {'value': 'hits', 'label': '안타'},
    {'value': 'ops', 'label': 'OPS'},
    {'value': 'war', 'label': 'WAR'},
  ];

  final List<Map<String, String>> _pitcherSortOptions = [
    {'value': 'era', 'label': 'ERA'},
    {'value': 'wins', 'label': '승'},
    {'value': 'strikeouts', 'label': '탈삼진'},
    {'value': 'whip', 'label': 'WHIP'},
    {'value': 'saves', 'label': '세이브'},
    {'value': 'holds', 'label': '홀드'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPlayers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentTab() async {
    setState(() => _isLoading = true);
    try {
      if (_tabController.index == 0) {
        final data = await ApiService.getHitters(
            sortBy: _hitterSort, teamId: _selectedTeamId);
        setState(() { _hitters = data['hitters'] ?? []; });
      } else {
        final data = await ApiService.getPitchers(
            sortBy: _pitcherSort, teamId: _selectedTeamId);
        setState(() { _pitchers = data['pitchers'] ?? []; });
      }
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPlayers() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiService.getHitters(sortBy: _hitterSort, teamId: _selectedTeamId),
        ApiService.getPitchers(sortBy: _pitcherSort, teamId: _selectedTeamId),
      ]);
      setState(() {
        _hitters = results[0]['hitters'] ?? [];
        _pitchers = results[1]['pitchers'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() { _isSearching = false; _searchResults = []; });
      return;
    }
    try {
      final data = await ApiService.searchPlayers(query);
      setState(() { _searchResults = data['players'] ?? []; _isSearching = true; });
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('선수 기록'),
        bottom: _isSearching ? null : TabBar(
          controller: _tabController,
          tabs: const [Tab(text: '타자'), Tab(text: '투수')],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
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
              ),
            ),
          ),
          if (!_isSearching) ...[
            // 팀 필터
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                itemCount: _teams.length,
                itemBuilder: (context, index) {
                  final team = _teams[index];
                  final selected = _selectedTeamId == team['id'];
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedTeamId = team['id']);
                      _loadCurrentTab();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFF1A237E) : Colors.grey.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(team['name']!,
                          style: TextStyle(
                              fontSize: 12,
                              color: selected ? Colors.white : null,
                              fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                    ),
                  );
                },
              ),
            ),
            // 정렬 필터
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                itemCount: _tabController.index == 0
                    ? _hitterSortOptions.length
                    : _pitcherSortOptions.length,
                itemBuilder: (context, index) {
                  final options = _tabController.index == 0
                      ? _hitterSortOptions
                      : _pitcherSortOptions;
                  final opt = options[index];
                  final currentSort = _tabController.index == 0 ? _hitterSort : _pitcherSort;
                  final selected = currentSort == opt['value'];
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_tabController.index == 0) _hitterSort = opt['value']!;
                        else _pitcherSort = opt['value']!;
                      });
                      _loadCurrentTab();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: selected ? Colors.orange : Colors.grey.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(opt['label']!,
                          style: TextStyle(
                              fontSize: 12,
                              color: selected ? Colors.white : null,
                              fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                    ),
                  );
                },
              ),
            ),
          ],
          Expanded(
            child: _isSearching
                ? _buildSearchResults()
                : _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        controller: _tabController,
                        children: [_buildHitterList(), _buildPitcherList()],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) return const Center(child: Text('검색 결과가 없습니다'));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final p = _searchResults[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: p['profile_image'] != null ? NetworkImage(p['profile_image']) : null,
            child: p['profile_image'] == null ? const Icon(Icons.person) : null,
          ),
          title: Text('${p['name']}'),
          subtitle: Text('${p['team']} | ${p['player_type']} | #${p['number'] ?? '-'}'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: p['id']))),
        );
      },
    );
  }

  Widget _buildHitterList() {
    if (_hitters.isEmpty) return const Center(child: Text('데이터가 없습니다'));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _hitters.length,
      itemBuilder: (context, index) {
        final p = _hitters[index];
        return ListTile(
          leading: Stack(
            children: [
              CircleAvatar(
                backgroundImage: p['profile_image'] != null ? NetworkImage(p['profile_image']) : null,
                child: p['profile_image'] == null ? Text('${index + 1}', style: const TextStyle(fontSize: 12)) : null,
              ),
              Positioned(
                bottom: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(color: Color(0xFF1A237E), shape: BoxShape.circle),
                  child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontSize: 9)),
                ),
              ),
            ],
          ),
          title: Text('${p['name']} (${p['team'] ?? ''})'),
          subtitle: Text('타율 ${(p['avg'] as num?)?.toStringAsFixed(3) ?? '-'}  OPS ${(p['ops'] as num?)?.toStringAsFixed(3) ?? '-'}  ${p['home_runs'] ?? 0}홈런 ${p['rbis'] ?? 0}타점'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: p['id']))),
        );
      },
    );
  }

  Widget _buildPitcherList() {
    if (_pitchers.isEmpty) return const Center(child: Text('데이터가 없습니다'));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _pitchers.length,
      itemBuilder: (context, index) {
        final p = _pitchers[index];
        return ListTile(
          leading: Stack(
            children: [
              CircleAvatar(
                backgroundImage: p['profile_image'] != null ? NetworkImage(p['profile_image']) : null,
                child: p['profile_image'] == null ? Text('${index + 1}', style: const TextStyle(fontSize: 12)) : null,
              ),
              Positioned(
                bottom: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(color: Color(0xFF1A237E), shape: BoxShape.circle),
                  child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontSize: 9)),
                ),
              ),
            ],
          ),
          title: Text('${p['name']} (${p['team'] ?? ''})'),
          subtitle: Text('ERA ${(p['era'] as num?)?.toStringAsFixed(2) ?? '-'}  WHIP ${(p['whip'] as num?)?.toStringAsFixed(2) ?? '-'}  ${p['wins'] ?? 0}승 ${p['strikeouts'] ?? 0}K'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: p['id']))),
        );
      },
    );
  }
}