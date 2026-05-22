import 'package:flutter/material.dart';
import 'dart:async';

import '../../models/game.dart';
import '../../api/api_service.dart';
import '../../utils/team_theme.dart';
import '../game/game_detail_screen.dart';
import '../team/team_screen.dart';
import '../team/team_detail_screen.dart';
import '../player/player_screen.dart';
import '../community/community_screen.dart';
import '../calendar/calendar_screen.dart';
import '../mypage/my_page_screen.dart';
import '../search/search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const TodayGamesTab(),
    const TeamScreen(),
    const PlayerScreen(),
    const CalendarScreen(),
    const CommunityScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF1A237E),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.sports_baseball),
            label: '경기',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.leaderboard),
            label: '순위',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: '선수',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month),
            label: '캘린더',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.forum),
            label: '커뮤니티',
          ),
        ],
      ),
    );
  }
}

class TodayGamesTab extends StatefulWidget {
  const TodayGamesTab({super.key});

  @override
  State<TodayGamesTab> createState() => _TodayGamesTabState();
}

class _TodayGamesTabState extends State<TodayGamesTab> {
  DateTime _selectedDate = DateTime.now();
  List _games = [];
  List _todayRosterChanges = [];
  List _rankings = [];
  bool _isLoading = true;
  Set<int> _favoriteTeamIds = {};
  bool _myTeamOnly = false;
  Timer? _autoRefreshTimer;

  bool get _hasLiveGames => _games.any((g) => g['status'] == '진행');

  @override
  void initState() {
    super.initState();
    _loadGames();
    _loadTodayRosterChanges();
    _loadFavoriteTeams();
    _loadRankings();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && _hasLiveGames) _loadGames();
    });
  }

  Future<void> _loadFavoriteTeams() async {
    try {
      final data = await ApiService.getFavoriteTeams();
      if (mounted) {
        setState(() {
          _favoriteTeamIds = Set.from(
            (data['teams'] as List? ?? []).map((t) => t['id'] as int),
          );
        });
      }
    } catch (_) {}
  }

  Future<void> _loadRankings() async {
    try {
      final data = await ApiService.getTeamRankings();
      if (mounted) setState(() => _rankings = data['rankings'] ?? []);
    } catch (_) {}
  }

  Future<void> _loadTodayRosterChanges() async {
    try {
      final data = await ApiService.getTodayRosterChanges();
      if (mounted) setState(() => _todayRosterChanges = data['changes'] ?? []);
    } catch (_) {}
  }

  Future<void> _loadGames() async {
    setState(() => _isLoading = true);
    try {
      final dateStr =
          "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
      final data = await ApiService.getGamesByDate(dateStr);
      setState(() {
        _games = data['games'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2026, 3, 1),
      lastDate: DateTime(2026, 10, 31),
      locale: const Locale('ko', 'KR'),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadGames();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PlayBall',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A237E),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '검색',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: '마이페이지',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyPageScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 날짜 선택 바
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() {
                      _selectedDate =
                          _selectedDate.subtract(const Duration(days: 1));
                    });
                    _loadGames();
                  },
                ),
                GestureDetector(
                  onTap: _selectDate,
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '${_selectedDate.year}.${_selectedDate.month.toString().padLeft(2, '0')}.${_selectedDate.day.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    setState(() {
                      _selectedDate =
                          _selectedDate.add(const Duration(days: 1));
                    });
                    _loadGames();
                  },
                ),
              ],
            ),
          ),

          // 당일 등록말소 배너
          if (_todayRosterChanges.isNotEmpty)
            _buildTodayRosterBanner(),

          // 마이팀 대시보드
          _buildMyTeamDashboard(),

          // 마이팀 필터
          if (_favoriteTeamIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _myTeamOnly = !_myTeamOnly),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _myTeamOnly ? const Color(0xFF1A237E) : Colors.grey[200],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star,
                              size: 14,
                              color: _myTeamOnly ? Colors.amber : Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            '마이팀',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _myTeamOnly ? Colors.white : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 경기 목록
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildGameList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMyTeamDashboard() {
    if (_favoriteTeamIds.isEmpty || _rankings.isEmpty) return const SizedBox.shrink();
    final myRankings = _rankings
        .where((r) => _favoriteTeamIds.contains(r['id'] as int?))
        .toList();
    if (myRankings.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: const [
              Icon(Icons.star, size: 14, color: Color(0xFF1A237E)),
              SizedBox(width: 5),
              Text('마이팀',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
            ],
          ),
        ),
        SizedBox(
          height: 112,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            children: myRankings.map((r) => _buildMyTeamCard(r as Map)).toList(),
          ),
        ),
        const Divider(height: 1, thickness: 1),
      ],
    );
  }

  Widget _buildMyTeamCard(Map ranking) {
    final teamId = ranking['id'] as int? ?? 0;
    final code = ranking['short_name'] as String? ?? '';
    final name = ranking['name'] as String? ?? '';
    final rank = ranking['rank'] as int? ?? 0;
    final wins = ranking['wins'] as int? ?? 0;
    final losses = ranking['losses'] as int? ?? 0;
    final draws = ranking['draws'] as int? ?? 0;
    final streak = ranking['streak'] as int? ?? 0;
    final recent5 = (ranking['recent_5'] as List?)?.cast<String>() ?? [];

    Map? todayGame;
    for (final g in _games) {
      final gm = g as Map;
      if (gm['home_team_id'] == teamId || gm['away_team_id'] == teamId) {
        todayGame = gm;
        break;
      }
    }

    final bool isHome = todayGame != null && todayGame['home_team_id'] == teamId;
    final String oppName = todayGame != null
        ? (isHome
            ? todayGame['away_team'] as String? ?? ''
            : todayGame['home_team'] as String? ?? '')
        : '';

    String gameStr;
    Color gameColor = Colors.grey;
    bool showWinIcon = false;
    bool showLossIcon = false;

    if (todayGame == null) {
      gameStr = '오늘 경기 없음';
    } else {
      final status = todayGame['status'] as String? ?? '';
      final hs = todayGame['home_score'] as int? ?? 0;
      final as_ = todayGame['away_score'] as int? ?? 0;
      final myScore = isHome ? hs : as_;
      final oppScore = isHome ? as_ : hs;
      if (status == '예정' || status == '라인업') {
        gameStr = 'vs $oppName  ${todayGame['start_time'] ?? ''}';
        gameColor = Colors.indigo;
      } else if (status == '진행') {
        gameStr = '$myScore : $oppScore  vs $oppName';
        gameColor = Colors.green;
      } else if (status == '종료') {
        gameStr = '$myScore : $oppScore  vs $oppName';
        if (myScore > oppScore) { gameColor = Colors.blue; showWinIcon = true; }
        else if (myScore < oppScore) { gameColor = Colors.red; showLossIcon = true; }
      } else if (status == '취소') {
        gameStr = '취소  vs $oppName';
      } else {
        gameStr = 'vs $oppName';
      }
    }

    String streakText = '';
    Color streakColor = Colors.grey;
    if (streak > 0) { streakText = '$streak연승'; streakColor = Colors.blue; }
    else if (streak < 0) { streakText = '${-streak}연패'; streakColor = Colors.red; }

    final Color rankBg = rank <= 5 ? const Color(0xFF1565C0) : const Color(0xFF78909C);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TeamDetailScreen(team: Map<String, dynamic>.from(ranking))),
      ),
      child: Container(
        width: 215,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1A237E).withOpacity(0.25), width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TeamLogo(teamCode: code, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      Text('$wins승 $losses패${draws > 0 ? ' $draws무' : ''}',
                          style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                    ],
                  ),
                ),
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(color: rankBg, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text('$rank', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                if (showWinIcon) const Icon(Icons.arrow_upward, size: 11, color: Colors.blue),
                if (showLossIcon) const Icon(Icons.arrow_downward, size: 11, color: Colors.red),
                Expanded(
                  child: Text(gameStr,
                      style: TextStyle(fontSize: 11, color: gameColor, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
                if (streakText.isNotEmpty)
                  Text(streakText, style: TextStyle(fontSize: 10, color: streakColor, fontWeight: FontWeight.bold)),
              ],
            ),
            if (recent5.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: recent5.reversed.map((r) {
                  final c = r == 'W' ? Colors.blue : r == 'L' ? Colors.red : Colors.grey;
                  return Container(
                    width: 16, height: 16,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: c.withOpacity(0.5), width: 0.8),
                    ),
                    alignment: Alignment.center,
                    child: Text(r, style: TextStyle(fontSize: 8, color: c, fontWeight: FontWeight.bold)),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGameList() {
    List filtered;
    if (_myTeamOnly && _favoriteTeamIds.isNotEmpty) {
      filtered = _games.where((g) =>
          _favoriteTeamIds.contains(g['home_team_id']) ||
          _favoriteTeamIds.contains(g['away_team_id'])).toList();
    } else if (_favoriteTeamIds.isNotEmpty) {
      // 마이팀 경기 상단 고정
      final my = _games.where((g) =>
          _favoriteTeamIds.contains(g['home_team_id']) ||
          _favoriteTeamIds.contains(g['away_team_id'])).toList();
      final others = _games.where((g) =>
          !_favoriteTeamIds.contains(g['home_team_id']) &&
          !_favoriteTeamIds.contains(g['away_team_id'])).toList();
      filtered = [...my, ...others];
    } else {
      filtered = _games;
    }

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          _myTeamOnly ? '마이팀 경기가 없습니다' : '경기가 없습니다',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadGames,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final g = filtered[index];
          final isMyTeam = _favoriteTeamIds.contains(g['home_team_id']) ||
              _favoriteTeamIds.contains(g['away_team_id']);
          return GameCard(game: Game.fromJson(g), isMyTeam: isMyTeam && !_myTeamOnly);
        },
      ),
    );
  }

  bool _rosterBannerExpanded = false;

  Widget _buildTodayRosterBanner() {
    final changes = _todayRosterChanges;
    final registrations = changes.where((c) => c['change_type'] == '1군등록').toList();
    final removals = changes.where((c) => c['change_type'] == '등록말소').toList();
    final injuries = changes.where((c) => c['change_type'] == '부상자명단').toList();

    return InkWell(
      onTap: () => setState(() => _rosterBannerExpanded = !_rosterBannerExpanded),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFFE082)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                const Icon(Icons.swap_horiz, size: 16, color: Color(0xFFF57F17)),
                const SizedBox(width: 6),
                const Text('오늘 등록말소',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFF57F17))),
                const SizedBox(width: 8),
                if (registrations.isNotEmpty)
                  _rosterChip('${registrations.length}명 등록', Colors.blue),
                if (removals.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _rosterChip('${removals.length}명 말소', Colors.orange),
                ],
                if (injuries.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _rosterChip('${injuries.length}명 부상', Colors.red),
                ],
                const Spacer(),
                Icon(_rosterBannerExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: Colors.grey),
              ]),
            ),
            if (_rosterBannerExpanded)
              ...changes.map((c) {
                final type = c['change_type'] as String? ?? '';
                Color col = type == '1군등록' ? Colors.blue
                    : type == '등록말소' ? Colors.orange
                    : type == '부상자명단' ? Colors.red : Colors.grey;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: col.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(type, style: TextStyle(fontSize: 10, color: col, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Text(c['team_name'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(width: 4),
                    Text(c['player_name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    if ((c['reason'] as String? ?? '').isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text('(${c['reason']})',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ]),
                );
              }),
            if (_rosterBannerExpanded) const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _rosterChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
  );
}

class GameCard extends StatelessWidget {
  final Game game;
  final bool isMyTeam;

  const GameCard({super.key, required this.game, this.isMyTeam = false});

  Widget _starterChip(String name, bool isHome) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.indigo.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${isHome ? '홈' : '원정'} $name',
        style: const TextStyle(fontSize: 10, color: Colors.indigo),
      ),
    );
  }

  Widget? _buildWeatherChip() {
    final w = game.weather;
    if (w == null) return null;
    if (w['indoor'] == true) {
      return const Text('실내', style: TextStyle(fontSize: 11, color: Colors.grey));
    }
    final emoji = w['emoji'] ?? '';
    final temp = w['temp'];
    final pop = w['pop'];
    final parts = <String>[
      if (emoji.isNotEmpty) emoji,
      if (temp != null) '${temp}°',
      if (pop != null && (pop as int) > 0) '강수 $pop%',
    ];
    if (parts.isEmpty) return null;
    return Text(parts.join(' '), style: const TextStyle(fontSize: 12, color: Colors.blueGrey));
  }

  Widget _buildRecentBar(List<String> recent, String teamName, bool isHome) {
    if (recent.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(isHome ? '홈 ' : '원정 ',
            style: TextStyle(fontSize: 9, color: Colors.grey[400])),
        ...recent.map((r) {
          Color c;
          if (r == 'W') c = Colors.blue;
          else if (r == 'L') c = Colors.red;
          else c = Colors.grey;
          return Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: c.withOpacity(0.15),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: c.withOpacity(0.5), width: 0.8),
            ),
            alignment: Alignment.center,
            child: Text(r, style: TextStyle(fontSize: 8, color: c, fontWeight: FontWeight.bold)),
          );
        }),
      ],
    );
  }

  Color _statusColor() {
    switch (game.status) {
      case '진행':
        return Colors.green;
      case '종료':
        return Colors.grey;
      case '취소':
        return Colors.red;
      case '라인업':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isMyTeam
            ? const BorderSide(color: Color(0xFF1A237E), width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GameDetailScreen(gameId: game.id),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 상태 + 경기장
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isMyTeam)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A237E),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('MY',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor().withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      game.status == '진행'
                          ? '${game.currentInning ?? 0}회 ${game.inningHalf ?? ''}'
                          : game.status == '취소'
                              ? '취소'
                              : game.status == '라인업'
                                  ? '라인업'
                                  : game.status,
                      style: TextStyle(
                        color: _statusColor(),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_buildWeatherChip() != null) ...[
                        _buildWeatherChip()!,
                        const SizedBox(width: 6),
                      ],
                      Text(
                        game.stadium ?? '',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 팀 vs 스코어
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        TeamLogo(teamCode: game.homeTeamCode, size: 44),
                        const SizedBox(height: 4),
                        Text(
                          game.homeTeam,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        Text('홈', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: game.status == '예정' || game.status == '취소' || game.status == '라인업'
                        ? Text(
                            game.status == '취소' ? '취소' : (game.startTime ?? ''),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: game.status == '취소' ? Colors.red : null,
                            ),
                          )
                        : Text(
                            '${game.homeScore} : ${game.awayScore}',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        TeamLogo(teamCode: game.awayTeamCode, size: 44),
                        const SizedBox(height: 4),
                        Text(
                          game.awayTeam,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        Text('원정', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                      ],
                    ),
                  ),
                ],
              ),

              // 승/패 투수 또는 무승부 (종료 경기만)
              if (game.status == '종료' && (game.winPitcher != null || game.losePitcher != null || (game.isDraw ?? false)))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: (game.isDraw ?? false)
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('무승부',
                              style: TextStyle(fontSize: 11, color: Colors.grey)),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (game.winPitcher != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('승 ${game.winPitcher}',
                                    style: const TextStyle(fontSize: 11, color: Colors.blue)),
                              ),
                            if (game.losePitcher != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('패 ${game.losePitcher}',
                                    style: const TextStyle(fontSize: 11, color: Colors.red)),
                              ),
                          ],
                        ),
                ),

              // 선발투수 표시 (예정/라인업/진행)
              if ((game.status == '예정' || game.status == '라인업' || game.status == '진행') &&
                  (game.homeStarter != null || game.awayStarter != null))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (game.homeStarter != null)
                        _starterChip(game.homeStarter!, true),
                      if (game.homeStarter != null && game.awayStarter != null)
                        const Text('vs', style: TextStyle(fontSize: 10, color: Colors.grey)),
                      if (game.awayStarter != null)
                        _starterChip(game.awayStarter!, false),
                    ],
                  ),
                ),

              // 라인업 확정 표시
              if (game.status == '라인업')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('라인업 확정',
                        style: TextStyle(fontSize: 11, color: Colors.green)),
                  ),
                ),

              // 최근 5경기 W/L/D
              if (game.homeRecent5.isNotEmpty || game.awayRecent5.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildRecentBar(game.homeRecent5.reversed.toList(), game.homeTeam, true),
                      _buildRecentBar(game.awayRecent5.reversed.toList(), game.awayTeam, false),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}