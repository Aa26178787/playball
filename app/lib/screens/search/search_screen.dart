import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../api/api_service.dart';
import '../../utils/team_theme.dart';
import '../player/player_detail_screen.dart';
import '../team/team_detail_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List _players = [];
  List _teams = [];
  List<String> _history = [];
  bool _loading = false;
  bool _searched = false;

  static const _historyKey = 'search_history';
  static const _maxHistory = 10;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _history = prefs.getStringList(_historyKey) ?? []);
  }

  Future<void> _saveHistory(String q) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [q, ..._history.where((h) => h != q)].take(_maxHistory).toList();
    await prefs.setStringList(_historyKey, list);
    if (mounted) setState(() => _history = list);
  }

  Future<void> _removeHistory(String q) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _history.where((h) => h != q).toList();
    await prefs.setStringList(_historyKey, list);
    if (mounted) setState(() => _history = list);
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    if (mounted) setState(() => _history = []);
  }

  Future<void> _search(String q) async {
    q = q.trim();
    if (q.isEmpty) return;
    setState(() { _loading = true; _searched = true; });
    await _saveHistory(q);
    try {
      final data = await ApiService.search(q);
      if (mounted) setState(() {
        _players = data['players'] ?? [];
        _teams = data['teams'] ?? [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '선수, 팀 검색',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
          ),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
          onSubmitted: _search,
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _ctrl.clear();
                setState(() { _players = []; _teams = []; _searched = false; });
              },
            ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _search(_ctrl.text),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_searched
              ? _buildHistory()
              : _players.isEmpty && _teams.isEmpty
                  ? const Center(child: Text('검색 결과가 없습니다', style: TextStyle(color: Colors.grey)))
                  : _buildResults(),
    );
  }

  Widget _buildHistory() {
    if (_history.isEmpty) {
      return const Center(child: Text('선수 이름 또는 팀명을 검색하세요', style: TextStyle(color: Colors.grey)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('최근 검색', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
              TextButton(onPressed: _clearHistory, child: const Text('전체 삭제', style: TextStyle(fontSize: 12))),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: _history.map((h) => ListTile(
              leading: const Icon(Icons.history, size: 20, color: Colors.grey),
              title: Text(h),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                onPressed: () => _removeHistory(h),
              ),
              onTap: () {
                _ctrl.text = h;
                _search(h);
              },
            )).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildResults() {
    return ListView(
      children: [
        if (_teams.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('팀', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          ..._teams.map((t) => ListTile(
            leading: TeamLogo(teamCode: t['short_name'] ?? '', size: 36),
            title: Text(t['name'] ?? ''),
            subtitle: null,
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => TeamDetailScreen(team: Map<String, dynamic>.from(t)))),
          )),
          const Divider(),
        ],
        if (_players.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text('선수', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          ..._players.map((p) => ListTile(
            leading: CircleAvatar(
              radius: 20,
              backgroundImage: p['profile_image'] != null
                  ? CachedNetworkImageProvider(p['profile_image']) : null,
              backgroundColor: Colors.grey[200],
              child: p['profile_image'] == null
                  ? const Icon(Icons.person, size: 20) : null,
            ),
            title: Text(p['name'] ?? ''),
            subtitle: Text('${p['team'] ?? ''} | ${p['position'] ?? ''} | ${p['player_type'] ?? ''}',
                style: const TextStyle(fontSize: 12)),
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => PlayerDetailScreen(playerId: p['id']))),
          )),
        ],
      ],
    );
  }
}
