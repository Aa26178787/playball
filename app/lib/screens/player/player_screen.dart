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

  String _hitterSort = 'avg';
  String _pitcherSort = 'era';
  int? _selectedTeamId;
  String? _selectedPosition;
  String? _selectedThrows;

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

  final List<Map<String, String?>> _positions = [
    {'value': null, 'label': '전체'},
    {'value': '포수', 'label': '포수'},
    {'value': '1루수', 'label': '1루수'},
    {'value': '2루수', 'label': '2루수'},
    {'value': '3루수', 'label': '3루수'},
    {'value': '유격수', 'label': '유격수'},
    {'value': '좌익수', 'label': '좌익수'},
    {'value': '중견수', 'label': '중견수'},
    {'value': '우익수', 'label': '우익수'},
    {'value': '지명타자', 'label': 'DH'},
  ];

  final List<Map<String, String?>> _throwsOptions = [
    {'value': null, 'label': '전체'},
    {'value': '우투', 'label': '우투'},
    {'value': '좌투', 'label': '좌투'},
    {'value': '우언', 'label': '우언더'},
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
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
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
          sortBy: _hitterSort,
          teamId: _selectedTeamId,
          position: _selectedPosition,
        );
        setState(() { _hitters = data['hitters'] ?? []; });
      } else {
        final data = await ApiService.getPitchers(
          sortBy: _pitcherSort,
          teamId: _selectedTeamId,
          throws: _selectedThrows,
        );
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

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                dropdownColor: const Color(0xFF283593),
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 18),
                items: items,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final isHitter = _tabController.index == 0;

    final teamItems = _teams.map((t) => DropdownMenuItem<int?>(
      value: t['id'] as int?,
      child: Text(t['name'] as String, style: const TextStyle(color: Colors.white)),
    )).toList();

    final positionItems = _positions.map((p) => DropdownMenuItem<String?>(
      value: p['value'],
      child: Text(p['label']!, style: const TextStyle(color: Colors.white)),
    )).toList();

    final throwsItems = _throwsOptions.map((t) => DropdownMenuItem<String?>(
      value: t['value'],
      child: Text(t['label']!, style: const TextStyle(color: Colors.white)),
    )).toList();

    final hitterSortItems = _hitterSortOptions.map((o) => DropdownMenuItem<String>(
      value: o['value']!,
      child: Text(o['label']!, style: const TextStyle(color: Colors.white)),
    )).toList();

    final pitcherSortItems = _pitcherSortOptions.map((o) => DropdownMenuItem<String>(
      value: o['value']!,
      child: Text(o['label']!, style: const TextStyle(color: Colors.white)),
    )).toList();

    return Container(
      color: const Color(0xFF1A237E),
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Row(
        children: [
          _buildDropdown<int?>(
            label: '팀',
            value: _selectedTeamId,
            items: teamItems,
            onChanged: (v) {
              setState(() => _selectedTeamId = v);
              _loadCurrentTab();
            },
          ),
          Container(width: 1, height: 44, color: Colors.white.withOpacity(0.2)),
          _buildDropdown<String?>(
            label: isHitter ? '포지션' : '투구',
            value: isHitter ? _selectedPosition : _selectedThrows,
            items: isHitter ? positionItems : throwsItems,
            onChanged: (v) {
              setState(() {
                if (isHitter) _selectedPosition = v;
                else _selectedThrows = v;
              });
              _loadCurrentTab();
            },
          ),
          Container(width: 1, height: 44, color: Colors.white.withOpacity(0.2)),
          _buildDropdown<String>(
            label: '기록',
            value: isHitter ? _hitterSort : _pitcherSort,
            items: isHitter ? hitterSortItems : pitcherSortItems,
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                if (isHitter) _hitterSort = v;
                else _pitcherSort = v;
              });
              _loadCurrentTab();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('선수 기록'),
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
          if (!_isSearching) _buildFilters(),
          if (!_isSearching)
            const Divider(height: 1, thickness: 1),
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
        final pos = p['position'] as String?;
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
          title: Row(
            children: [
              Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text('${p['team'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              if (pos != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF303F9F).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(pos, style: const TextStyle(fontSize: 10, color: Color(0xFF00695C))),
                ),
              ],
            ],
          ),
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
        final throws = p['throws'] as String?;
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
          title: Row(
            children: [
              Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text('${p['team'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              if (throws != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF303F9F).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(throws, style: const TextStyle(fontSize: 10, color: Color(0xFF00695C))),
                ),
              ],
            ],
          ),
          subtitle: Text('ERA ${(p['era'] as num?)?.toStringAsFixed(2) ?? '-'}  WHIP ${(p['whip'] as num?)?.toStringAsFixed(2) ?? '-'}  ${p['wins'] ?? 0}승 ${p['strikeouts'] ?? 0}K'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: p['id']))),
        );
      },
    );
  }
}
