import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../utils/team_theme.dart';
import '../player/player_detail_screen.dart';
import 'team_detail_screen.dart';

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
  Set<int> _favoriteTeamIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadTeams();
    _loadFavoriteTeams();
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

  Future<void> _loadFavoriteTeams() async {
    try {
      final data = await ApiService.getFavoriteTeams();
      final teams = (data['teams'] as List? ?? []);
      if (mounted) {
        setState(() {
          _favoriteTeamIds = teams.map((t) => t['id'] as int).toSet();
        });
      }
    } catch (_) {}
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
    final rankCounts = <int, int>{};
    for (final t in _teams) {
      final r = t['rank'] as int? ?? 0;
      rankCounts[r] = (rankCounts[r] ?? 0) + 1;
    }
    return RefreshIndicator(
      onRefresh: _loadTeams,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: _teams.map((team) {
          final r = team['rank'] as int? ?? 0;
          return _buildTeamRow(team, isTied: (rankCounts[r] ?? 1) > 1);
        }).toList(),
      ),
    );
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

  Color _seriesLabelColor(String label) {
    if (label.contains('스윕 승')) return const Color(0xFF1565C0);
    if (label.contains('위닝')) return const Color(0xFF1976D2);
    if (label.contains('스플릿')) return Colors.grey;
    if (label.contains('루징')) return const Color(0xFFE53935);
    if (label.contains('스윕 패')) return const Color(0xFFC62828);
    return Colors.grey;
  }

  Widget _buildTeamRow(Map<String, dynamic> team, {bool isTied = false}) {
    final code = team['short_name'] as String? ?? '';
    final gb = team['games_behind'];
    final gbNum = gb as num?;
    final gbText = gbNum == null || gbNum == 0 ? '-' : gbNum.toStringAsFixed(1);
    final recent5 = (team['recent_5'] as List?)?.cast<String>() ?? [];
    final wins = team['wins'] as int? ?? 0;
    final losses = team['losses'] as int? ?? 0;
    final draws = team['draws'] as int? ?? 0;
    final totalGames = team['total_games'] as int? ?? 0;
    final streak = team['streak'] as int? ?? 0;
    final rank = team['rank'] as int? ?? 0;
    final winRate = (team['win_rate'] as num?)?.toStringAsFixed(3) ?? '-';

    final Color rankBg;
    if (isTied) {
      rankBg = const Color(0xFFF57F17); // 주황 (공동순위)
    } else if (rank <= 5) {
      rankBg = const Color(0xFF1565C0); // 파랑 (상위 5)
    } else {
      rankBg = const Color(0xFF78909C); // 회색 (하위 5)
    }

    final isFav = _favoriteTeamIds.contains(team['id'] as int? ?? -1);
    final lastSeries = team['last_series'] as Map<String, dynamic>?;
    final seriesLabel = lastSeries?['label'] as String?;
    final pythag = (team['pythag_winpct'] as num?)?.toStringAsFixed(3) ?? '-';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isFav ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isFav
            ? const BorderSide(color: Color(0xFF1A237E), width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TeamDetailScreen(team: team)),
        ),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── 헤더: 순위 + 로고 + 팀명 ───
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: rankBg, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(
                      '$rank',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TeamLogo(teamCode: code, size: 36, logoUrl: team['logo_url']),
                  const SizedBox(width: 10),
                  Text(
                    team['name'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if (isFav) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.star, size: 16, color: Color(0xFF1A237E)),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, thickness: 0.5),
              const SizedBox(height: 10),
              // ─── 스탯 행: G / 승-패-무 / 승률 / GB ───
              Row(
                children: [
                  _statCell('경기', '$totalGames'),
                  _statDivider(),
                  _statCell('승', '$wins', valueColor: const Color(0xFF1565C0)),
                  _statDivider(),
                  _statCell('패', '$losses', valueColor: const Color(0xFFC62828)),
                  _statDivider(),
                  _statCell('무', '$draws'),
                  _statDivider(),
                  _statCell('승률', winRate),
                  _statDivider(),
                  _statCell('게임차', gbText),
                  _statDivider(),
                  _statCell('피타', pythag),
                ],
              ),
              const SizedBox(height: 8),
              // ─── 최근 5경기 + 연승 ───
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Text('최근 5경기',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                    const SizedBox(width: 10),
                    ...recent5.map((r) => _recentDot(r)),
                    const Spacer(),
                    if (seriesLabel != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: _seriesLabelColor(seriesLabel).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _seriesLabelColor(seriesLabel), width: 0.8),
                        ),
                        child: Text(
                          seriesLabel,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _seriesLabelColor(seriesLabel)),
                        ),
                      ),
                    ],
                    Text(
                      _streakText(streak),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _streakColor(streak),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCell(String label, String value, {Color? valueColor}) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: valueColor)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(width: 0.5, height: 28, color: Colors.grey[300]);
  }

  Widget _recentDot(String result) {
    Color color;
    String label;
    switch (result) {
      case 'W': color = const Color(0xFF1565C0); label = '승'; break;
      case 'L': color = const Color(0xFFC62828); label = '패'; break;
      default:  color = Colors.grey; label = '무';
    }
    return Container(
      width: 22,
      height: 22,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      alignment: Alignment.center,
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
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
    {'value': 'avg',          'label': '타율'},
    {'value': 'home_runs',    'label': '홈런'},
    {'value': 'rbis',         'label': '타점'},
    {'value': 'hits',         'label': '안타'},
    {'value': 'stolen_bases', 'label': '도루'},
    {'value': 'ops',          'label': '출루장타율'},
    {'value': 'war',          'label': '대체승리기여'},
  ];

  final List<Map<String, String>> _pitcherCategories = [
    {'value': 'era',        'label': '평균자책점'},
    {'value': 'wins',       'label': '승리'},
    {'value': 'strikeouts', 'label': '탈삼진'},
    {'value': 'saves',      'label': '세이브'},
    {'value': 'holds',      'label': '홀드'},
    {'value': 'whip',       'label': '이닝당출루'},
    {'value': 'war',        'label': '대체승리기여'},
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
      case 'avg':          return (p['avg'] as num?)?.toStringAsFixed(3) ?? '-';
      case 'home_runs':    return '${p['home_runs'] ?? '-'}';
      case 'rbis':         return '${p['rbis'] ?? '-'}';
      case 'hits':         return '${p['hits'] ?? '-'}';
      case 'stolen_bases': return '${p['stolen_bases'] ?? '-'}';
      case 'ops':          return (p['ops'] as num?)?.toStringAsFixed(3) ?? '-';
      case 'war':          return (p['war'] as num?)?.toStringAsFixed(1) ?? '-';
      default:             return '-';
    }
  }

  String _pitcherStatValue(Map p) {
    switch (_pitcherSort) {
      case 'era':        return (p['era'] as num?)?.toStringAsFixed(2) ?? '-';
      case 'wins':       return '${p['wins'] ?? '-'}';
      case 'strikeouts': return '${p['strikeouts'] ?? '-'}';
      case 'saves':      return '${p['saves'] ?? '-'}';
      case 'holds':      return '${p['holds'] ?? '-'}';
      case 'whip':       return (p['whip'] as num?)?.toStringAsFixed(2) ?? '-';
      case 'war':        return (p['war'] as num?)?.toStringAsFixed(1) ?? '-';
      default:           return '-';
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
              child: Text(
                cat['label']!,
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected ? Colors.white : null,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPodium(List players, String Function(Map) statValue) {
    if (players.length < 3) return const SizedBox.shrink();
    final p1 = players[0] as Map;
    final p2 = players[1] as Map;
    final p3 = players[2] as Map;

    Widget slot(Map p, int rank, double height, Color medalColor) {
      final img = p['profile_image'] as String?;
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
                  backgroundImage: (img != null && img.isNotEmpty) ? NetworkImage(img) : null,
                  backgroundColor: medalColor.withValues(alpha: 0.15),
                  child: (img == null || img.isEmpty)
                      ? Icon(Icons.person, size: rank == 1 ? 28 : 20, color: medalColor)
                      : null,
                ),
                Positioned(
                  bottom: -6, right: -6,
                  child: Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      color: medalColor, shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [BoxShadow(color: medalColor.withValues(alpha: 0.4), blurRadius: 3)],
                    ),
                    alignment: Alignment.center,
                    child: Text('$rank', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(p['name'] ?? '',
                style: TextStyle(fontSize: rank == 1 ? 13 : 11, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
            Text(p['team'] ?? '',
                style: TextStyle(fontSize: 9, color: Colors.grey[600]), textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(statValue(p),
                style: TextStyle(fontSize: rank == 1 ? 16 : 14, fontWeight: FontWeight.bold, color: medalColor),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Container(
              width: rank == 1 ? 90 : 72,
              height: height,
              decoration: BoxDecoration(
                color: medalColor.withValues(alpha: 0.18),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
              alignment: Alignment.center,
              child: Text('$rank위', style: TextStyle(fontSize: 11, color: medalColor, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
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

  Widget _buildRankingsContent(List players, String Function(Map) statValue, String label) {
    final top3 = players.take(3).toList();
    final rest = players.skip(3).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (top3.length >= 3) ...[
          _buildPodium(top3, statValue),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const SizedBox(width: 32, child: Text('순위', style: TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center)),
              const SizedBox(width: 56),
              const Expanded(child: Text('선수', style: TextStyle(fontSize: 11, color: Colors.grey))),
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(width: 8),
            ]),
          ),
          const Divider(height: 8),
        ],
        ...rest.asMap().entries.map((e) {
          final p = e.value as Map;
          return _buildRankRow(
            rank: e.key + 4,
            playerId: p['id'],
            name: p['name'] ?? '',
            team: p['team'] ?? '',
            teamCode: p['team_code'] ?? '',
            profileImage: p['profile_image'] as String?,
            label: label,
            value: statValue(p),
          );
        }),
      ],
    );
  }

  Widget _buildHitterRankings() {
    final label = _hitterCategories.firstWhere((c) => c['value'] == _hitterSort)['label']!;
    return Column(
      children: [
        _buildCategoryChips(_hitterCategories, _hitterSort, (val) {
          setState(() { _hitterSort = val; _hitterRankings = []; });
          _loadHitters();
        }),
        const SizedBox(height: 4),
        Expanded(
          child: _hitterLoading
              ? const Center(child: CircularProgressIndicator())
              : _hitterRankings.isEmpty
                  ? const Center(child: Text('데이터가 없습니다'))
                  : _buildRankingsContent(_hitterRankings, _hitterStatValue, label),
        ),
      ],
    );
  }

  Widget _buildPitcherRankings() {
    final label = _pitcherCategories.firstWhere((c) => c['value'] == _pitcherSort)['label']!;
    return Column(
      children: [
        _buildCategoryChips(_pitcherCategories, _pitcherSort, (val) {
          setState(() { _pitcherSort = val; _pitcherRankings = []; });
          _loadPitchers();
        }),
        const SizedBox(height: 4),
        Expanded(
          child: _pitcherLoading
              ? const Center(child: CircularProgressIndicator())
              : _pitcherRankings.isEmpty
                  ? const Center(child: Text('데이터가 없습니다'))
                  : _buildRankingsContent(_pitcherRankings, _pitcherStatValue, label),
        ),
      ],
    );
  }

  Widget _buildRankRow({
    required int rank,
    required int playerId,
    required String name,
    required String team,
    required String teamCode,
    required String label,
    required String value,
    String? profileImage,
  }) {
    final isTop3 = rank <= 3;
    final rankColors = [Colors.amber, Colors.grey[600]!, Colors.brown];
    final color = teamColor(teamCode);

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: playerId)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
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
            // 선수 사진 (없으면 팀 컬러 이니셜)
            CircleAvatar(
              radius: 18,
              backgroundColor: color,
              backgroundImage: (profileImage != null && profileImage.isNotEmpty)
                  ? NetworkImage(profileImage)
                  : null,
              child: (profileImage == null || profileImage.isEmpty)
                  ? Text(
                      teamDisplayName(teamCode).substring(0, teamDisplayName(teamCode).length.clamp(0, 2)),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
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
