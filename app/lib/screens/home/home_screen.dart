import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/game.dart';
import '../../utils/local_cache.dart';
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
import '../stadium/stadium_screen.dart';
import '../notifications/notifications_screen.dart';

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
      body: IndexedStack(index: _currentIndex, children: _screens),
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
  List _seriesGames = [];
  List _todayRosterChanges = [];
  List _rankings = [];
  bool _isLoading = true;
  Set<int> _favoriteTeamIds = {};
  bool _myTeamOnly = false;
  Timer? _autoRefreshTimer;
  int _unreadNotifCount = 0;
  int _loadGen = 0;

  final ScrollController _dateScrollController = ScrollController();
  static final _seasonStart = DateTime(2026, 3, 1);
  static final _seasonEnd   = DateTime(2026, 10, 31);
  static const _itemW = 50.0;

  bool get _hasLiveGames => _games.any((g) => g['status'] == '진행');

  String get _selectedDateStr =>
      '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

  bool get _gamesDateMismatch =>
      _games.isNotEmpty &&
      (_games.first as Map)['game_date'] != _selectedDateStr;

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  int get _totalDays => _seasonEnd.difference(_seasonStart).inDays + 1;

  int _dateIndex(DateTime d) => d.difference(_seasonStart).inDays.clamp(0, _totalDays - 1);

  void _scrollToSelected() {
    if (!_dateScrollController.hasClients) return;
    final idx = _dateIndex(_selectedDate);
    final screenW = MediaQuery.of(context).size.width;
    final offset = (idx * _itemW) - (screenW / 2) + (_itemW / 2);
    _dateScrollController.animateTo(
      offset.clamp(0.0, _dateScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _scrollToMonthStart(int month) {
    final target = DateTime(2026, month, 1);
    setState(() { _selectedDate = target; _isLoading = true; _loadGen++; });
    _loadGames();
    _loadTomorrowGames();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void initState() {
    super.initState();
    _loadGames();
    _loadTodayRosterChanges();
    _loadFavoriteTeams();
    _loadRankings();
    _loadUnreadCount();
    _loadTomorrowGames();
    _startAutoRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelected();
      _backgroundPrefetch();
    });
  }

  void _backgroundPrefetch() {
    Future(() async {
      // 선수 탭 데이터 미리 로드 (캐시 없을 때만)
      if (await LocalCache.get('hitters_list', maxAgeSeconds: 300) == null) {
        try {
          final d = await ApiService.getHitters(sortBy: 'avg', limit: 500, teamId: null);
          await LocalCache.set('hitters_list', d['hitters'] ?? []);
        } catch (_) {}
      }
      if (await LocalCache.get('pitchers_list', maxAgeSeconds: 300) == null) {
        try {
          final d = await ApiService.getPitchers(sortBy: 'era', limit: 500, teamId: null);
          await LocalCache.set('pitchers_list', d['pitchers'] ?? []);
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _dateScrollController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      if (_hasLiveGames) {
        _loadGames();
      } else {
        // 라이브 경기 없어도 빌드 트리거: 자정 지나면 배너 조건 재평가
        setState(() {});
      }
    });
  }

  Future<void> _loadFavoriteTeams() async {
    final cached = await LocalCache.get('favorite_teams') as List?;
    if (cached != null && mounted) {
      setState(() {
        _favoriteTeamIds = Set.from(cached.map((t) => (t as Map)['id'] as int));
      });
    }
    try {
      final data = await ApiService.getFavoriteTeams();
      final teams = data['teams'] as List? ?? [];
      await LocalCache.set('favorite_teams', teams);
      if (mounted) {
        setState(() {
          _favoriteTeamIds = Set.from(teams.map((t) => (t as Map)['id'] as int));
        });
      }
    } catch (_) {}
  }

  Future<void> _loadRankings() async {
    final cached = await LocalCache.get('team_rankings') as List?;
    if (cached != null && mounted) setState(() => _rankings = cached);
    try {
      final data = await ApiService.getTeamRankings();
      final rankings = data['rankings'] as List? ?? [];
      await LocalCache.set('team_rankings', rankings);
      if (mounted) setState(() => _rankings = rankings);
    } catch (_) {}
  }

  Future<void> _loadUnreadCount() async {
    try {
      final data = await ApiService.getNotifications(limit: 1);
      if (mounted) setState(() => _unreadNotifCount = data['unread_count'] as int? ?? 0);
    } catch (_) {}
  }

  Future<void> _loadTodayRosterChanges() async {
    try {
      final data = await ApiService.getTodayRosterChanges();
      if (mounted) setState(() => _todayRosterChanges = data['changes'] ?? []);
    } catch (_) {}
  }

  Future<void> _loadTomorrowGames() async {
    try {
      final base = _selectedDate.isAfter(DateTime.now())
          ? _selectedDate
          : DateTime.now();
      String _ds(int offset) {
        final d = base.add(Duration(days: offset));
        return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }

      final results = await Future.wait([
        ApiService.getGamesByDate(_ds(1)).catchError((_) => <String, dynamic>{}),
        ApiService.getGamesByDate(_ds(2)).catchError((_) => <String, dynamic>{}),
        ApiService.getGamesByDate(_ds(3)).catchError((_) => <String, dynamic>{}),
        ApiService.getGamesByDate(_ds(4)).catchError((_) => <String, dynamic>{}),
        ApiService.getGamesByDate(_ds(5)).catchError((_) => <String, dynamic>{}),
        ApiService.getGamesByDate(_ds(6)).catchError((_) => <String, dynamic>{}),
        ApiService.getGamesByDate(_ds(7)).catchError((_) => <String, dynamic>{}),
      ]);

      final combined = <dynamic>[];
      for (final r in results) {
        final games = (r as Map<String, dynamic>)['games'] as List? ?? [];
        combined.addAll(games);
      }
      if (mounted) setState(() => _seriesGames = combined);
    } catch (_) {}
  }

  Future<void> _loadGames({bool isRetry = false}) async {
    final gen = ++_loadGen;
    final dateStr = _selectedDateStr;

    final cached = await LocalCache.get('games_$dateStr', maxAgeSeconds: 300) as List?;
    if (!mounted || _loadGen != gen) return;
    if (cached != null) {
      setState(() { _games = cached; _isLoading = false; });
    } else {
      setState(() => _isLoading = true);
    }

    try {
      final data = await ApiService.getGamesByDate(dateStr);
      if (!mounted || _loadGen != gen) return;
      final games = data['games'] as List? ?? [];
      await LocalCache.set('games_$dateStr', games);
      if (!mounted || _loadGen != gen) return;
      setState(() { _games = games; _isLoading = false; });
    } catch (e) {
      if (!mounted || _loadGen != gen) return;
      if (!isRetry) {
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted || _loadGen != gen) return;
        await _loadGames(isRetry: true);
        return;
      }
      setState(() { _isLoading = false; _games = []; });
    }
  }

  Widget _buildMonthStrip() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 28,
      child: Row(
        children: List.generate(8, (i) {
          final month = i + 3;
          final isActive = _selectedDate.month == month;
          return Expanded(
            child: GestureDetector(
              onTap: () => _scrollToMonthStart(month),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF1A237E) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '$month월',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isActive
                          ? Colors.white
                          : (isDark ? Colors.grey[400]! : Colors.grey[500]!),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDateStrip() {
    final today = DateTime.now();
    final isOnToday = _isSameDay(_selectedDate, today);
    const dayNames = ['월', '화', '수', '목', '금', '토', '일'];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      alignment: Alignment.centerRight,
      children: [
        SizedBox(
          height: 68,
          child: ListView.builder(
        controller: _dateScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        itemCount: _totalDays,
        itemBuilder: (_, i) {
          final date = _seasonStart.add(Duration(days: i));
          final isSelected = _isSameDay(date, _selectedDate);
          final isToday = _isSameDay(date, today);
          final dayName = dayNames[date.weekday - 1];
          final isSat = date.weekday == DateTime.saturday;
          final isSun = date.weekday == DateTime.sunday;

          Color nameColor;
          if (isSelected) {
            nameColor = Colors.white70;
          } else if (isSun) {
            nameColor = Colors.red[400]!;
          } else if (isSat) {
            nameColor = Colors.blue[400]!;
          } else {
            nameColor = isDark ? Colors.grey[400]! : Colors.grey[500]!;
          }

          return GestureDetector(
            onTap: () {
              if (!isSelected) {
                setState(() { _selectedDate = date; _isLoading = true; _loadGen++; });
                _loadGames();
                _loadTomorrowGames();
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: _itemW - 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1A237E) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(dayName,
                      style: TextStyle(fontSize: 11, color: nameColor, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? Colors.white
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    width: 4, height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isToday && !isSelected ? Colors.red : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        ),
        ),
        if (!isOnToday)
          Positioned(
            right: 6,
            child: GestureDetector(
              onTap: () {
                setState(() { _selectedDate = today; _isLoading = true; _loadGen++; });
                _loadGames();
                _loadTomorrowGames();
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A237E),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: const Text('오늘', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        title: const Text(
          'PlayBall',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A237E),
          ),
        ),
        actions: [
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_none),
                if (_unreadNotifCount > 0)
                  Positioned(
                    top: -4, right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                      child: Text(
                        _unreadNotifCount > 9 ? '9+' : '$_unreadNotifCount',
                        style: const TextStyle(color: Colors.white, fontSize: 9,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: '알림',
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()));
              _loadUnreadCount();
            },
          ),
          IconButton(
            icon: const Icon(Icons.stadium_outlined),
            tooltip: '구장',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StadiumScreen()),
            ),
          ),
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
          // 월 선택 스트립
          _buildMonthStrip(),
          // 날짜 스크롤 스트립
          _buildDateStrip(),

          // 당일 등록말소 배너 (오늘 날짜일 때만)
          if (_todayRosterChanges.isNotEmpty && _isSameDay(_selectedDate, DateTime.now()))
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
            child: _isLoading || _gamesDateMismatch
                ? _buildGameShimmer()
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
                  width: 32, height: 26,
                  decoration: BoxDecoration(color: rankBg, borderRadius: BorderRadius.circular(13)),
                  alignment: Alignment.center,
                  child: Text('${rank}위', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
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
                  final c = r == 'W' ? Colors.blue : r == 'L' ? Colors.red : r == 'C' ? Colors.orange : Colors.grey;
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

  Widget _buildGameShimmer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 4,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: base,
        highlightColor: highlight,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Container(width: 36, height: 36, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Container(width: 60, height: 14, color: Colors.white),
                  ]),
                  Container(width: 40, height: 20, color: Colors.white),
                  Row(children: [
                    Container(width: 60, height: 14, color: Colors.white),
                    const SizedBox(width: 8),
                    Container(width: 36, height: 36, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                  ]),
                ],
              ),
              const SizedBox(height: 10),
              Container(width: double.infinity, height: 10, color: Colors.white),
            ],
          ),
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
      final isToday = _selectedDate.year == DateTime.now().year &&
          _selectedDate.month == DateTime.now().month &&
          _selectedDate.day == DateTime.now().day;
      final isPast = _selectedDate.isBefore(DateTime.now().subtract(const Duration(days: 1)));
      return RefreshIndicator(
        onRefresh: _loadGames,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.15),
            Column(
              children: [
                Icon(
                  _myTeamOnly ? Icons.star_border : Icons.sports_baseball,
                  size: 64, color: Colors.grey[300],
                ),
                const SizedBox(height: 16),
                Text(
                  _myTeamOnly ? '마이팀 경기가 없습니다' : '경기가 없는 날입니다',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Text(
                  _myTeamOnly
                      ? '마이팀 필터를 해제하면 전체 경기를 볼 수 있습니다'
                      : isToday
                          ? 'KBO 휴식일입니다'
                          : isPast
                              ? '이 날은 경기가 없었습니다'
                              : '이 날은 경기가 예정되어 있지 않습니다',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
                if (_myTeamOnly) ...[
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _myTeamOnly = false),
                    icon: const Icon(Icons.sports_baseball, size: 16),
                    label: const Text('전체 경기 보기'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1A237E),
                      side: const BorderSide(color: Color(0xFF1A237E)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }
    final rankMap = {for (final r in _rankings) (r['id'] as int): r['rank'] as int?};

    return RefreshIndicator(
      onRefresh: _loadGames,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final g = filtered[index];
          final homeId = g['home_team_id'] as int? ?? 0;
          final awayId = g['away_team_id'] as int? ?? 0;
          final isMyTeam = _favoriteTeamIds.contains(homeId) ||
              _favoriteTeamIds.contains(awayId);
          return GameCard(
            game: Game.fromJson(g),
            isMyTeam: isMyTeam && !_myTeamOnly,
            homeRank: rankMap[homeId],
            awayRank: rankMap[awayId],
            nextHomeSeries: _nextSeries(homeId, awayId),
            nextAwaySeries: _nextSeries(awayId, homeId),
          );
        },
      ),
    );
  }

  Map<String, String>? _nextSeries(int teamId, int currentOpponentId) {
    for (final sg in _seriesGames) {
      final gm = sg as Map;
      final homeId = gm['home_team_id'] as int? ?? 0;
      final awayId = gm['away_team_id'] as int? ?? 0;
      if (homeId != teamId && awayId != teamId) continue;
      final oppId = homeId == teamId ? awayId : homeId;
      if (oppId == currentOpponentId) continue;
      final oppName = homeId == teamId ? gm['away_team'] as String? ?? '' : gm['home_team'] as String? ?? '';
      final oppCode = homeId == teamId ? gm['away_team_code'] as String? ?? '' : gm['home_team_code'] as String? ?? '';
      return {'code': oppCode, 'name': oppName};
    }
    return null;
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
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
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
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
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

// ===== Winner Glow Logo =====

class _NeonGlowLogo extends StatefulWidget {
  final String teamCode;
  final Color color;
  final double size;
  final Widget logo;
  const _NeonGlowLogo({required this.teamCode, required this.color, required this.size, required this.logo});

  @override
  State<_NeonGlowLogo> createState() => _NeonGlowLogoState();
}

class _NeonGlowLogoState extends State<_NeonGlowLogo> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) {
        final v = _anim.value;
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: c.withValues(alpha: 0.9 * v), blurRadius: 6, spreadRadius: 1),
              BoxShadow(color: c.withValues(alpha: 0.55 * v), blurRadius: 14, spreadRadius: 4),
              BoxShadow(color: c.withValues(alpha: 0.25 * v), blurRadius: 28, spreadRadius: 8),
              BoxShadow(color: Colors.white.withValues(alpha: 0.35 * v), blurRadius: 4, spreadRadius: 0),
            ],
          ),
          child: child,
        );
      },
      child: widget.logo,
    );
  }
}

class GameCard extends StatelessWidget {
  final Game game;
  final bool isMyTeam;
  final int? homeRank;
  final int? awayRank;
  final Map<String, String>? nextHomeSeries;
  final Map<String, String>? nextAwaySeries;

  const GameCard({super.key, required this.game, this.isMyTeam = false, this.homeRank, this.awayRank, this.nextHomeSeries, this.nextAwaySeries});

  Widget _starterChip(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.indigo.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(name, style: const TextStyle(fontSize: 10, color: Colors.indigo), overflow: TextOverflow.ellipsis),
    );
  }

  Widget _buildNextSeriesWidget(Map<String, String> series) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TeamLogo(teamCode: series['code'] ?? '', size: 20),
            const SizedBox(width: 3),
            Flexible(child: Text(series['name'] ?? '', style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis, maxLines: 1)),
          ],
        ),
        const SizedBox(height: 1),
        Text('다음 시리즈', style: TextStyle(fontSize: 9, color: Colors.grey[500]), overflow: TextOverflow.ellipsis, maxLines: 1),
      ],
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

  Widget _buildRecentBar(List<String> recent, bool isHome) {
    if (recent.isEmpty) return const SizedBox.shrink();
    // home: 좌→우 오래된순, 최신이 우 (rightmost)
    // away: 좌→우 최신순, 최신이 좌 (leftmost)
    final displayed = isHome ? recent.reversed.toList() : recent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...displayed.asMap().entries.map((e) {
          final idx = e.key;
          final r = e.value;
          final isLatest = isHome ? idx == displayed.length - 1 : idx == 0;
          final c = r == 'W' ? Colors.blue : r == 'L' ? Colors.red : r == 'C' ? Colors.orange : Colors.grey;
          return Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: c.withOpacity(0.5), width: 0.8),
                  ),
                  alignment: Alignment.center,
                  child: Text(r, style: TextStyle(fontSize: 8, color: c, fontWeight: FontWeight.bold)),
                ),
                if (isLatest)
                  const Positioned(
                    top: -3,
                    right: -1,
                    child: CircleAvatar(radius: 2.5, backgroundColor: Colors.red),
                  ),
              ],
            ),
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

  Widget _winnerGlowLogo(String teamCode, bool isWinner) {
    final logo = TeamLogo(teamCode: teamCode, size: 44);
    if (!isWinner) return logo;
    final c = teamColor(teamCode);
    return _NeonGlowLogo(teamCode: teamCode, color: c, size: 44, logo: logo);
  }

  @override
  Widget build(BuildContext context) {
    final isFinished = game.status == '종료';
    final isDraw = game.isDraw ?? false;
    final homeWon = isFinished && !isDraw && game.homeScore > game.awayScore;
    final awayWon = isFinished && !isDraw && game.awayScore > game.homeScore;
    final showStarters = game.status == '예정' || game.status == '라인업' || game.status == '진행';

    Widget teamCol(String code, String name, int? rank, bool isHome, bool isWinner,
        String? starter, List<String> recent, Map<String, String>? nextSeries) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _winnerGlowLogo(code, isWinner),
          const SizedBox(height: 4),
          Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            rank != null ? (isHome ? '${rank}위 · 홈' : '원정 · ${rank}위') : (isHome ? '홈' : '원정'),
            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
          ),
          if (showStarters && starter != null) ...[
            const SizedBox(height: 5),
            _starterChip(starter),
          ],
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 5),
            _buildRecentBar(recent, isHome),
          ],
          if (nextSeries != null) ...[
            const SizedBox(height: 5),
            _buildNextSeriesWidget(nextSeries),
          ],
        ],
      );
    }

    Widget _pitcherWidget(String? name, String? imageUrl, String label, Color color) {
      if (name == null) return const SizedBox.shrink();
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: 0.12),
            backgroundImage: imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
            child: imageUrl == null ? Icon(Icons.person, size: 16, color: color) : null,
          ),
          const SizedBox(height: 3),
          Text(name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis, maxLines: 1),
          Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
        ],
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isMyTeam ? const BorderSide(color: Color(0xFF1A237E), width: 1.5) : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GameDetailScreen(gameId: game.id))),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            children: [
              // 상태 + 날씨/구장
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (isMyTeam) ...[
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFF1A237E), borderRadius: BorderRadius.circular(4)),
                        child: const Text('MY', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: _statusColor().withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        game.status == '진행' ? '${game.currentInning ?? 0}회 ${game.inningHalf ?? ''}' :
                        game.status == '취소' ? '취소' :
                        game.status == '라인업' ? '라인업' : game.status,
                        style: TextStyle(color: _statusColor(), fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_buildWeatherChip() != null) ...[_buildWeatherChip()!, const SizedBox(width: 6)],
                    Text(game.stadium ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ]),
                ],
              ),
              const SizedBox(height: 10),

              // 두 팀 정보 + 가운데 스코어/시간
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: teamCol(
                    game.homeTeamCode, game.homeTeam, homeRank, true, homeWon,
                    game.homeStarter, game.homeRecent5, nextHomeSeries,
                  )),
                  SizedBox(
                      width: 76,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          game.status == '예정' || game.status == '취소' || game.status == '라인업'
                              ? Text(
                                  game.status == '취소' ? '취소' : (game.startTime ?? ''),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: game.status == '취소' ? Colors.red : null),
                                )
                              : Text('${game.homeScore} : ${game.awayScore}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          if (game.status == '라인업')
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                              child: const Text('라인업', style: TextStyle(fontSize: 9, color: Colors.green)),
                            ),
                          if (isFinished && isDraw) ...[
                            const SizedBox(height: 3),
                            Text('무승부', style: TextStyle(fontSize: 10, color: Colors.grey[600]), textAlign: TextAlign.center),
                          ],
                          // 승투/패투 — 스코어 아래 수평 배열
                          // 홈승: 승투(홈팀)=왼쪽, 패투=오른쪽
                          // 원정승: 패투(홈팀)=왼쪽, 승투=오른쪽
                          if (isFinished && !isDraw && (game.winPitcher != null || game.losePitcher != null)) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _pitcherWidget(
                                  homeWon ? game.winPitcher : game.losePitcher,
                                  homeWon ? game.winPitcherImage : game.losePitcherImage,
                                  homeWon ? '승투' : '패투',
                                  homeWon ? Colors.blue : Colors.red,
                                ),
                                if (game.winPitcher != null && game.losePitcher != null)
                                  const SizedBox(width: 10),
                                _pitcherWidget(
                                  awayWon ? game.winPitcher : game.losePitcher,
                                  awayWon ? game.winPitcherImage : game.losePitcherImage,
                                  awayWon ? '승투' : '패투',
                                  awayWon ? Colors.blue : Colors.red,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                  ),
                  Expanded(child: teamCol(
                    game.awayTeamCode, game.awayTeam, awayRank, false, awayWon,
                    game.awayStarter, game.awayRecent5, nextAwaySeries,
                  )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}