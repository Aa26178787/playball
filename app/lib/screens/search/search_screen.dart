import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../utils/team_theme.dart';
import '../player/player_detail_screen.dart';
import '../team/team_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List _players = [];
  List _teams = [];
  bool _loading = false;
  bool _searched = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    setState(() { _loading = true; _searched = true; });
    try {
      final data = await ApiService.search(q.trim());
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
          decoration: const InputDecoration(
            hintText: '선수, 팀 검색',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.white70),
          ),
          style: const TextStyle(color: Colors.white, fontSize: 16),
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
              ? const Center(child: Text('선수 이름 또는 팀명을 검색하세요', style: TextStyle(color: Colors.grey)))
              : _players.isEmpty && _teams.isEmpty
                  ? const Center(child: Text('검색 결과가 없습니다', style: TextStyle(color: Colors.grey)))
                  : ListView(
                      children: [
                        if (_teams.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text('팀', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
                          ),
                          ..._teams.map((t) => ListTile(
                            leading: TeamLogo(teamCode: t['short_name'] ?? '', size: 36),
                            title: Text(t['name'] ?? ''),
                            subtitle: Text(t['short_name'] ?? ''),
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
                                  ? NetworkImage(p['profile_image']) : null,
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
                    ),
    );
  }
}
