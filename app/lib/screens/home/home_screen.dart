import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../models/game.dart';
import '../../utils/local_cache.dart';
import '../../api/api_service.dart';
import '../../utils/team_theme.dart';
import '../../utils/app_theme.dart';
import '../../providers/auth_provider.dart';
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

class _TodayGamesTabState extends State<TodayGamesTab>
    with WidgetsBindingObserver {
  DateTime _selectedDate = DateTime.now();
  List _games = [];
  List _seriesGames = [];
  List _todayRosterChanges = [];
  List _rankings = [];
  bool _isLoading = true;
  bool _loadError = false;
  Set<int> _favoriteTeamIds = {};
  bool _myTeamOnly = false;
  Timer? _autoRefreshTimer;
  int _unreadNotifCount = 0;
  int _loadGen = 0;
  int _seriesGen = 0;
  AuthProvider? _authProvider;
  bool _wasLoggedIn = false;

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
    setState(() { _selectedDate = target; _isLoading = true; _games = []; _loadGen++; });
    _loadGames();
    _loadTomorrowGames();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadGames();        // 최우선
    _loadFavoriteTeams();
    _loadRankings();
    _startAutoRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelected();
      _authProvider = Provider.of<AuthProvider>(context, listen: false);
      _wasLoggedIn = _authProvider!.isLoggedIn;
      _authProvider!.addListener(_onAuthChanged);
      // 핵심 로드 후 비우선 작업 지연
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        _loadTodayRosterChanges();
        _loadUnreadCount();
        _loadTomorrowGames();
        _backgroundPrefetch();
      });
    });
  }

  void _backgroundPrefetch() {
    Future(() async {
      // 최근 14일 경기 목록 병렬 캐시 (날짜 전환 즉시 표시, 미래는 _loadTomorrowGames가 처리)
      final now = DateTime.now();
      await Future.wait(List.generate(14, (i) async {
        final d = now.add(Duration(days: -(i + 1))); // 어제부터 14일 전까지
        final ds = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        if (await LocalCache.getStale('games_$ds') != null) return; // 이미 캐시됨
        try {
          final data = await ApiService.getGamesByDate(ds);
          await LocalCache.set('games_$ds', data['games'] ?? []);
        } catch (_) {}
      }));

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

  void _onAuthChanged() {
    if (!mounted) return;
    final isNow = _authProvider?.isLoggedIn ?? false;
    if (isNow && !_wasLoggedIn) {
      _loadFavoriteTeams();
      _loadUnreadCount();
    }
    _wasLoggedIn = isNow;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authProvider?.removeListener(_onAuthChanged);
    _autoRefreshTimer?.cancel();
    _dateScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadGames();
      _loadUnreadCount();
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final isToday = _isSameDay(_selectedDate, DateTime.now());
      if (isToday || _hasLiveGames) {
        _loadGames();
      } else {
        // 자정 지나면 배너 조건 재평가
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
    final gen = ++_seriesGen;
    try {
      final base = _selectedDate.isAfter(DateTime.now())
          ? _selectedDate
          : DateTime.now();
      String _ds(int offset) {
        final d = base.add(Duration(days: offset));
        return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }

      // 캐시 먼저 확인 — 없는 날짜만 API 호출 + LocalCache에 저장
      final dates = List.generate(7, (i) => _ds(i + 1));
      final results = await Future.wait(dates.map((d) async {
        final c = await LocalCache.getStale('games_$d') as List?;
        if (c != null) return <String, dynamic>{'games': c};
        try {
          final data = await ApiService.getGamesByDate(d);
          final games = data['games'] as List? ?? [];
          await LocalCache.set('games_$d', games);
          return <String, dynamic>{'games': games};
        } catch (_) {
          return <String, dynamic>{};
        }
      }));

      final combined = <dynamic>[];
      for (final r in results) {
        final games = (r as Map<String, dynamic>)['games'] as List? ?? [];
        combined.addAll(games);
      }
      // race condition 방지: 최신 호출만 반영, empty면 기존 데이터 유지
      if (mounted && _seriesGen == gen && combined.isNotEmpty) {
        setState(() => _seriesGames = combined);
      }
    } catch (_) {}
  }

  Future<void> _loadGames() async {
    final gen = ++_loadGen;
    final dateStr = _selectedDateStr;

    final isToday = _isSameDay(_selectedDate, DateTime.now());

    List? cached;
    if (isToday) {
      // 오늘: 300초 TTL 엄격 적용
      cached = await LocalCache.get('games_$dateStr', maxAgeSeconds: 300) as List?;
    } else {
      // 과거/미래: 만료돼도 stale 즉시 표시 → shimmer 없음
      cached = await LocalCache.getStale('games_$dateStr') as List?;
    }
    if (!mounted || _loadGen != gen) return;
    if (cached != null) {
      setState(() { _games = cached!; _isLoading = false; _loadError = false; });
    } else {
      setState(() => _isLoading = true);
    }

    try {
      // 오늘 날짜: /games/today (서버 30초 캐시) 사용 — /games/date/{date}는 5분 캐시라 스코어 갱신 지연
      final data = isToday
          ? await ApiService.getTodayGames()
          : await ApiService.getGamesByDate(dateStr);
      if (!mounted || _loadGen != gen) return;
      final games = data['games'] as List? ?? [];
      await LocalCache.set('games_$dateStr', games);
      if (!mounted || _loadGen != gen) return;
      setState(() { _games = games; _isLoading = false; _loadError = false; });
      _prefetchAdjacentDates(dateStr);
      _prefetchGameDetails(games);
    } catch (e) {
      if (!mounted || _loadGen != gen) return;
      // Dio 인터셉터가 이미 1회 재시도함 — 캐시 데이터 유지, 로딩 해제
      // _games가 비어있으면 에러 상태, 캐시 있으면 에러 숨김
      setState(() { _isLoading = false; if (_games.isEmpty) _loadError = true; });
    }
  }

  // 인접 날짜 게임 목록 선제 캐시 (날짜 전환 즉시 표시)
  void _prefetchAdjacentDates(String dateStr) {
    Future(() async {
      final date = DateTime.parse(dateStr);
      for (final delta in [-1, 1]) {
        final adj = date.add(Duration(days: delta));
        final adjStr = '${adj.year}-${adj.month.toString().padLeft(2, '0')}-${adj.day.toString().padLeft(2, '0')}';
        if (await LocalCache.get('games_$adjStr', maxAgeSeconds: 3600) != null) continue;
        try {
          final data = await ApiService.getGamesByDate(adjStr);
          await LocalCache.set('games_$adjStr', data['games'] ?? []);
        } catch (_) {}
      }
    });
  }

  // 종료/예정 경기 상세 선제 캐시 (게임 상세 첫 진입 즉시 표시)
  void _prefetchGameDetails(List games) {
    Future(() async {
      for (final game in games) {
        final id = game['id'] as int?;
        final status = game['status'] as String? ?? '';
        if (id == null || status == '진행') continue; // 진행중은 실시간 → 캐시 불필요
        if (ApiService.getGameDetailMem(id) != null) continue;
        if (await LocalCache.get('game_${id}_detail', maxAgeSeconds: 86400) != null) continue;
        try {
          final detail = await ApiService.getGameDetail(id);
          ApiService.setGameDetailMem(id, detail);
          await LocalCache.set('game_${id}_detail', detail);
          if (status == '종료' || status == '취소') {
            // 중계 탭도 미리 캐시
            final relay = await ApiService.getGameRelayAll(id);
            await LocalCache.set('game_${id}_relay', relay);
          }
        } catch (_) {}
      }
    });
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
                setState(() { _selectedDate = date; _isLoading = true; _games = []; _loadGen++; });
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
                setState(() { _selectedDate = today; _isLoading = true; _games = []; _loadGen++; });
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
        surfaceTintColor: Colors.transparent,
        title: const Text('PlayBall'),
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
                if (_loadError && !_myTeamOnly) ...[
                  Icon(Icons.wifi_off, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text(
                    '불러오기 실패',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  Text('네트워크를 확인하고 다시 시도해주세요', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() { _isLoading = true; _loadError = false; _loadGen++; });
                      _loadGames();
                    },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('다시 시도'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1A237E),
                      side: const BorderSide(color: Color(0xFF1A237E)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ] else ...[
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
            key: ValueKey(g['id']),
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
      final gameDate = gm['game_date'] as String? ?? '';
      return {'code': oppCode, 'name': oppName, 'date': gameDate};
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

  // 그라디언트 카드에서 공통으로 쓸 white text shadow
  static const _textShadow = [Shadow(color: Colors.black38, blurRadius: 4)];
  // 최근5경기 색상 (어두운 배경 위)
  static const _wColor = Color(0xFF86EFAC);   // 연초록
  static const _lColor = Color(0xFFFCA5A5);   // 연빨강
  static const _cColor = Color(0xFFFDE68A);   // 연노랑 (취소)

  const GameCard({super.key, required this.game, this.isMyTeam = false, this.homeRank, this.awayRank, this.nextHomeSeries, this.nextAwaySeries});

  Widget _starterChip(String name) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.18),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Colors.white.withOpacity(0.35), width: 0.7),
    ),
    child: Text(name,
        style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600, shadows: _textShadow),
        overflow: TextOverflow.ellipsis),
  );

  Widget _buildNextSeriesInline(Map<String, String> series) {
    final dateStr = series['date'] ?? '';
    String dateLabel = '';
    if (dateStr.length >= 10) {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        final m = int.tryParse(parts[1]) ?? 0;
        final d = int.tryParse(parts[2]) ?? 0;
        if (m > 0 && d > 0) dateLabel = ' $m/$d~';
      }
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('다음 ', style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.35))),
        TeamLogo(teamCode: series['code'] ?? '', size: 15),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            '${series['name'] ?? ''}$dateLabel',
            style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis, maxLines: 1,
          ),
        ),
      ],
    );
  }

  Widget? _buildWeatherWidget() {
    final w = game.weather;
    if (w == null) return null;
    if (w['indoor'] == true) {
      return const Text('실내', style: TextStyle(fontSize: 11, color: Colors.white54));
    }
    final emoji = w['emoji'] ?? '';
    final temp = w['temp'];
    final pop = w['pop'];
    final parts = <String>[
      if (emoji.isNotEmpty) emoji,
      if (temp != null) '${temp}°',
      if (pop != null && (pop as int) > 0) '$pop%',
    ];
    if (parts.isEmpty) return null;
    return Text(parts.join(' '), style: const TextStyle(fontSize: 11, color: Colors.white70));
  }

  Widget _buildRecentBar(List<String> recent, bool isHome) {
    if (recent.isEmpty) return const SizedBox.shrink();
    final displayed = isHome ? recent.reversed.toList() : recent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: displayed.asMap().entries.map((e) {
        final idx = e.key;
        final r = e.value;
        final isLatest = isHome ? idx == displayed.length - 1 : idx == 0;
        Color textC;
        Color bgC;
        if (r == 'W')      { textC = _wColor; bgC = _wColor.withOpacity(0.2); }
        else if (r == 'L') { textC = _lColor; bgC = _lColor.withOpacity(0.15); }
        else if (r == 'C') { textC = _cColor; bgC = _cColor.withOpacity(0.15); }
        else               { textC = Colors.white54; bgC = Colors.white12; }

        return Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 18, height: 18,
                decoration: BoxDecoration(
                  color: bgC,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: textC.withOpacity(0.55), width: 0.8),
                ),
                alignment: Alignment.center,
                child: Text(r, style: TextStyle(fontSize: 9, color: textC, fontWeight: FontWeight.w800)),
              ),
              if (isLatest)
                Positioned(
                  top: -3, right: -1,
                  child: Container(
                    width: 5, height: 5,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _winnerGlowLogo(String teamCode, bool isWinner) {
    const size = 52.0;
    final logo = TeamLogo(teamCode: teamCode, size: size);
    if (!isWinner) return Opacity(opacity: 0.85, child: logo);
    final c = teamColor(teamCode);
    return _NeonGlowLogo(teamCode: teamCode, color: c, size: size, logo: logo);
  }

  @override
  Widget build(BuildContext context) {
    final isFinished = game.status == '종료';
    final isDraw = game.isDraw ?? false;
    final homeWon = isFinished && !isDraw && game.homeScore > game.awayScore;
    final awayWon = isFinished && !isDraw && game.awayScore > game.homeScore;
    final isLive = game.status == '진행';
    final showStarters = game.status == '예정' || game.status == '라인업' || isLive;
    final showPrediction = (game.status == '예정' || game.status == '라인업') &&
        game.homeTeamId != null && game.awayTeamId != null;

    final homeColor = teamColor(game.homeTeamCode);
    final awayColor = teamColor(game.awayTeamCode);
    // 취소/종료 시 채도 낮춤
    final overlayOpacity = game.status == '취소' ? 0.58 : (isFinished ? 0.48 : 0.38);

    Widget teamCol(String code, String name, int? rank, bool isHome, bool isWinner) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _winnerGlowLogo(code, isWinner),
          const SizedBox(height: 6),
          Text(name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white, shadows: _textShadow),
              textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(
            rank != null ? '${rank}위 ${isHome ? "홈" : "원정"}' : (isHome ? '홈' : '원정'),
            style: const TextStyle(fontSize: 10, color: Colors.white54),
          ),
        ],
      );
    }

    Widget pitcherChip(String? name, String label, Color labelColor) {
      if (name == null) return const SizedBox.shrink();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white, shadows: _textShadow),
              overflow: TextOverflow.ellipsis, maxLines: 1),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: labelColor.withOpacity(0.25),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: labelColor.withOpacity(0.6), width: 0.7),
            ),
            child: Text(label, style: TextStyle(fontSize: 9, color: labelColor, fontWeight: FontWeight.w800)),
          ),
        ],
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 4,
      shadowColor: homeColor.withOpacity(0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isMyTeam
            ? BorderSide(color: Colors.amber.withOpacity(0.8), width: 2)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // === 그라디언트 배경 ===
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [homeColor, awayColor],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
          // === 어두운 오버레이 (가독성) ===
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(overlayOpacity)),
          ),
          // === 콘텐츠 ===
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GameDetailScreen(gameId: game.id))),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    children: [
                      // 헤더 행
                      Row(
                        children: [
                          if (isMyTeam) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('MY', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900)),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (isLive) ...[
                            Container(
                              width: 7, height: 7,
                              decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 5),
                          ],
                          // 상태 배지
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isLive
                                  ? AppColors.live.withOpacity(0.2)
                                  : Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isLive ? AppColors.live.withOpacity(0.6) : Colors.white.withOpacity(0.35),
                                width: 0.7,
                              ),
                            ),
                            child: Text(
                              isLive ? '${game.currentInning ?? 0}회 ${game.inningHalf ?? ''}' :
                              game.status == '취소' ? '취소' :
                              game.status == '라인업' ? '라인업' : game.status,
                              style: TextStyle(
                                color: isLive ? AppColors.live : Colors.white,
                                fontWeight: FontWeight.w700, fontSize: 11,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (_buildWeatherWidget() != null) ...[_buildWeatherWidget()!, const SizedBox(width: 6)],
                          Text(game.stadium ?? '', style: const TextStyle(fontSize: 11, color: Colors.white54)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // 스코어 행
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: teamCol(
                            game.homeTeamCode, game.homeTeam, homeRank, true, homeWon,
                          )),
                          SizedBox(
                            width: 80,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                game.status == '예정' || game.status == '취소' || game.status == '라인업'
                                    ? Text(
                                        game.status == '취소' ? '취소' : (game.startTime ?? 'VS'),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 22, fontWeight: FontWeight.w900,
                                          letterSpacing: -0.5, color: Colors.white,
                                          shadows: game.status == '취소' ? null : _textShadow,
                                        ),
                                      )
                                    : Text(
                                        '${game.homeScore} : ${game.awayScore}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 30, fontWeight: FontWeight.w900,
                                          letterSpacing: -1, color: Colors.white,
                                          shadows: _textShadow,
                                        ),
                                      ),
                                if (game.status == '라인업')
                                  Container(
                                    margin: const EdgeInsets.only(top: 3),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.25),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.orange.withOpacity(0.5), width: 0.7),
                                    ),
                                    child: const Text('라인업', style: TextStyle(fontSize: 9, color: Colors.orange)),
                                  ),
                                if (isFinished && isDraw) ...[
                                  const SizedBox(height: 4),
                                  const Text('무승부', style: TextStyle(fontSize: 10, color: Colors.white60), textAlign: TextAlign.center),
                                ],
                              ],
                            ),
                          ),
                          Expanded(child: teamCol(
                            game.awayTeamCode, game.awayTeam, awayRank, false, awayWon,
                          )),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // === 정보 스트립 (선발/최근5/승투패투/다음시리즈) ===
              Builder(builder: (_) {
                final hasPitchers = isFinished && !isDraw && (game.winPitcher != null || game.losePitcher != null);
                final hasStarters = showStarters && (game.homeStarter != null || game.awayStarter != null);
                final hasRecent = game.homeRecent5.isNotEmpty || game.awayRecent5.isNotEmpty;
                final hasNext = nextHomeSeries != null || nextAwaySeries != null;
                if (!hasPitchers && !hasStarters && !hasRecent && !hasNext) return const SizedBox.shrink();
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.18),
                    border: Border(top: BorderSide(color: Colors.white.withOpacity(0.12), width: 0.5)),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 승투/패투 칩 (이미지 없음)
                      if (hasPitchers)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Row(
                            children: [
                              pitcherChip(
                                homeWon ? game.winPitcher : game.losePitcher,
                                homeWon ? '승' : '패',
                                homeWon ? _wColor : _lColor,
                              ),
                              const Spacer(),
                              pitcherChip(
                                awayWon ? game.winPitcher : game.losePitcher,
                                awayWon ? '승' : '패',
                                awayWon ? _wColor : _lColor,
                              ),
                            ],
                          ),
                        ),
                      // 선발투수 칩
                      if (hasStarters)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Row(
                            children: [
                              if (game.homeStarter != null) _starterChip(game.homeStarter!),
                              const Spacer(),
                              if (game.awayStarter != null) _starterChip(game.awayStarter!),
                            ],
                          ),
                        ),
                      // 최근 5경기
                      if (hasRecent)
                        Padding(
                          padding: EdgeInsets.only(bottom: hasNext ? 7 : 0),
                          child: Row(
                            children: [
                              _buildRecentBar(game.homeRecent5, true),
                              const Spacer(),
                              _buildRecentBar(game.awayRecent5, false),
                            ],
                          ),
                        ),
                      // 다음 시리즈
                      if (hasNext)
                        Row(
                          children: [
                            if (nextHomeSeries != null)
                              Expanded(child: _buildNextSeriesInline(nextHomeSeries!)),
                            if (nextAwaySeries != null)
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: _buildNextSeriesInline(nextAwaySeries!),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                );
              }),
              if (showPrediction)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    border: Border(top: BorderSide(color: Colors.white.withOpacity(0.15), width: 0.5)),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                  child: _PredictionBar(
                    key: ValueKey(game.id),
                    gameId: game.id,
                    homeTeamId: game.homeTeamId!,
                    awayTeamId: game.awayTeamId!,
                    homeCode: game.homeTeamCode,
                    awayCode: game.awayTeamCode,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}


class _PredictionBar extends StatefulWidget {
  final int gameId;
  final int homeTeamId;
  final int awayTeamId;
  final String homeCode;
  final String awayCode;

  const _PredictionBar({
    super.key,
    required this.gameId,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.homeCode,
    required this.awayCode,
  });

  @override
  State<_PredictionBar> createState() => _PredictionBarState();
}

class _PredictionBarState extends State<_PredictionBar> {
  // 세션 내 재생성 시 (스크롤 아웃→인) 즉시 표시용 static cache
  static final Map<int, Map<String, dynamic>> _cache = {};

  int _homeVotes = 0;
  int _awayVotes = 0;
  int? _userVote;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _applyCache();
    if (_loading) _load(); // 캐시 hit 시 재호출 금지 — setState 플리커 방지
  }

  @override
  void didUpdateWidget(_PredictionBar old) {
    super.didUpdateWidget(old);
    if (old.gameId != widget.gameId) {
      // 게임 교체 (list 재정렬) — cache로 즉시 전환
      _applyCache();
      if (_loading) _load();
    }
  }

  void _applyCache() {
    final cached = _cache[widget.gameId];
    if (cached != null) {
      _homeVotes = cached['home_votes'] as int? ?? 0;
      _awayVotes = cached['away_votes'] as int? ?? 0;
      _userVote = cached['user_vote'] as int?;
      _loading = false;
    }
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.getGamePredictions(widget.gameId);
      _cache[widget.gameId] = {
        'home_votes': data['home_votes'],
        'away_votes': data['away_votes'],
        'user_vote': data['user_vote'],
      };
      if (mounted) setState(() {
        _homeVotes = data['home_votes'] as int? ?? 0;
        _awayVotes = data['away_votes'] as int? ?? 0;
        _userVote = data['user_vote'] as int?;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _vote(int teamId) async {
    try {
      final data = await ApiService.predictGame(widget.gameId, teamId);
      _cache[widget.gameId] = {
        'home_votes': data['home_votes'],
        'away_votes': data['away_votes'],
        'user_vote': data['user_vote'],
      };
      if (mounted) setState(() {
        _homeVotes = data['home_votes'] as int? ?? 0;
        _awayVotes = data['away_votes'] as int? ?? 0;
        _userVote = data['user_vote'] as int?;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인 후 예측 가능합니다'), duration: Duration(seconds: 2)),
        );
      }
    }
  }

  Widget _voteButton({
    required bool isSelected,
    required String name,
    required String pct,
    required VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white.withOpacity(0.28)
                : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? Colors.white.withOpacity(0.8)
                  : Colors.white.withOpacity(0.25),
              width: isSelected ? 1.5 : 0.8,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold,
                  color: Colors.white.withOpacity(isSelected ? 1.0 : 0.7),
                  shadows: GameCard._textShadow,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                pct,
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800,
                  color: Colors.white.withOpacity(isSelected ? 1.0 : 0.55),
                  shadows: GameCard._textShadow,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _homeVotes + _awayVotes;
    final homePct = total > 0 ? _homeVotes / total : 0.5;
    final awayPct = 1.0 - homePct;
    final homeSelected = _userVote == widget.homeTeamId;
    final awaySelected = _userVote == widget.awayTeamId;
    final homePctStr = _loading ? '-' : '${(homePct * 100).round()}%';
    final awayPctStr = _loading ? '-' : '${(awayPct * 100).round()}%';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(
            children: [
              Text('승리 예측',
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.bold,
                    color: Colors.white.withOpacity(0.6),
                  )),
              const Spacer(),
              if (total > 0)
                Text('$total명 참여',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withOpacity(0.45),
                    )),
            ],
          ),
        ),
        Row(
          children: [
            _voteButton(
              isSelected: homeSelected,
              name: teamDisplayName(widget.homeCode),
              pct: homePctStr,
              onTap: () => _vote(widget.homeTeamId),
            ),
            const SizedBox(width: 8),
            _voteButton(
              isSelected: awaySelected,
              name: teamDisplayName(widget.awayCode),
              pct: awayPctStr,
              onTap: () => _vote(widget.awayTeamId),
            ),
          ],
        ),
      ],
    );
  }
}