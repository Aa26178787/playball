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

// 공통 디자인 토큰 (mockup hi-fi)
class _Tok {
  final Color paper, paper2, line, line2, ink, ink2, ink3, sub, track;
  const _Tok({
    required this.paper, required this.paper2,
    required this.line, required this.line2,
    required this.ink, required this.ink2, required this.ink3, required this.sub,
    required this.track,
  });
  factory _Tok.of(bool isDark) => _Tok(
    paper:  isDark ? const Color(0xFF18181C) : Colors.white,
    paper2: isDark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6),
    line:   isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0),
    line2:  isDark ? const Color(0xFF33333A) : const Color(0xFFE0E0E4),
    ink:    isDark ? const Color(0xFFF4F4F5) : const Color(0xFF111113),
    ink2:   isDark ? const Color(0xFFC9C9D1) : const Color(0xFF3F3F46),
    ink3:   isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73),
    sub:    isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2),
    track:  isDark ? const Color(0xFF2C2C33) : const Color(0xFFE8E8EC),
  );
}

const Color _kLiveRed = Color(0xFFE53935);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  List<Map<String, dynamic>> _myTeamChips = [];

  @override
  void initState() {
    super.initState();
    ApiService.myTeamData.addListener(_onMyTeamDataChanged);
  }

  void _onMyTeamDataChanged() {
    if (mounted) setState(() => _myTeamChips = List.of(ApiService.myTeamData.value));
  }

  @override
  void dispose() {
    ApiService.myTeamData.removeListener(_onMyTeamDataChanged);
    super.dispose();
  }

  final List<Widget> _screens = [
    const TodayGamesTab(),
    const TeamScreen(),
    const PlayerScreen(),
    const CalendarScreen(),
    const CommunityScreen(),
  ];

  static const _navItems = [
    (icon: Icons.sports_baseball_outlined, activeIcon: Icons.sports_baseball, label: '경기'),
    (icon: Icons.leaderboard_outlined,     activeIcon: Icons.leaderboard,     label: '팀'),
    (icon: Icons.person_outline,           activeIcon: Icons.person,          label: '선수'),
    (icon: Icons.calendar_month_outlined,  activeIcon: Icons.calendar_month,  label: '캘린더'),
    (icon: Icons.forum_outlined,           activeIcon: Icons.forum,           label: '커뮤니티'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Scaffold(
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v < -250 && _currentIndex < _screens.length - 1) {
                setState(() => _currentIndex++);
              } else if (v > 250 && _currentIndex > 0) {
                setState(() => _currentIndex--);
              }
            },
            child: IndexedStack(index: _currentIndex, children: _screens),
          ),
          // Floating NavBar — 시스템 내비게이션 바 위로 올림
          Positioned(
            left: 20,
            right: 20,
            bottom: 16 + bottomInset,
            child: _FloatingNavBar(
              currentIndex: _currentIndex,
              isDark: isDark,
              onTap: (i) => setState(() => _currentIndex = i),
              items: _navItems,
              myTeamItems: _myTeamChips,
              onMyTeamTap: (item) => Navigator.push(context,
                MaterialPageRoute(builder: (_) => TeamDetailScreen(team: item['ranking'] as Map<String, dynamic>)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({
    required this.currentIndex,
    required this.isDark,
    required this.onTap,
    required this.items,
    this.myTeamItems = const [],
    this.onMyTeamTap,
  });

  final int currentIndex;
  final bool isDark;
  final ValueChanged<int> onTap;
  final List<({IconData icon, IconData activeIcon, String label})> items;
  final List<Map<String, dynamic>> myTeamItems;
  final void Function(Map<String, dynamic>)? onMyTeamTap;

  BoxDecoration _pillDecoration() {
    final tk = _Tok.of(isDark);
    return BoxDecoration(
      color: tk.paper,
      borderRadius: BorderRadius.circular(30),
      boxShadow: [
        BoxShadow(
          color: isDark ? Colors.black45 : Colors.black.withValues(alpha: 0.08),
          blurRadius: 16, offset: const Offset(0, 4),
        ),
      ],
      border: Border.all(color: tk.line, width: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tk = _Tok.of(isDark);
    final activeColor = tk.ink;
    final inactiveColor = tk.sub;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 마이팀 개별 floating chips (즐겨찾기 있을 때만) ──
        if (myTeamItems.isNotEmpty) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: myTeamItems.map((item) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildFloatingChip(item),
              )).toList(),
            ),
          ),
          const SizedBox(height: 10),
        ],
        // ── 탭 pill ──
        Container(
          height: 58,
          decoration: _pillDecoration(),
          child: Row(
            children: List.generate(items.length, (i) {
              final item = items[i];
              final selected = i == currentIndex;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    decoration: BoxDecoration(
                      color: selected ? activeColor.withOpacity(0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          selected ? item.activeIcon : item.icon,
                          size: 22,
                          color: selected ? activeColor : inactiveColor,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                            color: selected ? activeColor : inactiveColor,
                            fontFamily: 'Pretendard',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingChip(Map<String, dynamic> item) {
    final tk = _Tok.of(isDark);
    final code = item['code'] as String? ?? '';
    final name = item['name'] as String? ?? '';
    final gameStr = item['gameStr'] as String? ?? '';
    final gameStatus = item['gameStatus'] as String? ?? '';
    final won = item['won'] as bool? ?? false;
    final lost = item['lost'] as bool? ?? false;

    Color gameColor;
    if (gameStatus == '진행') {
      gameColor = const Color(0xFF22C55E);
    } else if (gameStatus == '종료') {
      gameColor = won ? const Color(0xFF3B82F6) : (lost ? const Color(0xFFEF4444) : tk.sub);
    } else {
      gameColor = tk.sub;
    }

    return GestureDetector(
      onTap: () => onMyTeamTap?.call(item),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: tk.paper,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tk.line, width: 1),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black54 : Colors.black.withValues(alpha: 0.08),
              blurRadius: 12, offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            TeamLogo(teamCode: code, size: 18),
            const SizedBox(width: 6),
            Text(name,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: tk.ink)),
            if (gameStr.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(gameStr,
                  style: TextStyle(fontSize: 11, color: gameColor, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChip(Map<String, dynamic> item) {
    final code = item['code'] as String? ?? '';
    final name = item['name'] as String? ?? '';
    final gameStr = item['gameStr'] as String? ?? '';
    final gameStatus = item['gameStatus'] as String? ?? '';
    final won = item['won'] as bool? ?? false;
    final lost = item['lost'] as bool? ?? false;

    Color gameColor;
    if (gameStatus == '진행') {
      gameColor = Colors.green;
    } else if (gameStatus == '종료') {
      gameColor = won ? const Color(0xFF3B82F6) : (lost ? const Color(0xFFEF4444) : Colors.grey);
    } else if (gameStatus == '없음') {
      gameColor = isDark ? Colors.white30 : Colors.black26;
    } else {
      gameColor = isDark ? Colors.white54 : Colors.black45;
    }

    final textColor = isDark ? Colors.white.withOpacity(0.88) : Colors.black87;

    return GestureDetector(
      onTap: () => onMyTeamTap?.call(item),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            TeamLogo(teamCode: code, size: 18),
            const SizedBox(width: 5),
            Text(name,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: textColor)),
            if (gameStr.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(gameStr,
                  style: TextStyle(
                      fontSize: 11, color: gameColor, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
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
  final ScrollController _gameScrollController = ScrollController();
  static final _seasonStart = DateTime(2026, 3, 1);
  static final _seasonEnd   = DateTime(2026, 10, 31);
  static const _itemW = 50.0;

  bool get _hasLiveGames => _games.any((g) => g['status'] == '진행');

  String get _selectedDateStr =>
      '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

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

  void _resetGameScroll() {
    if (_gameScrollController.hasClients) {
      _gameScrollController.jumpTo(0);
    }
  }

  void _prevDay() {
    if (_selectedDate.isAfter(_seasonStart)) {
      setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
      _resetGameScroll();
      _loadGames();
      Future.delayed(const Duration(seconds: 3), () { if (mounted) _loadTomorrowGames(); });
    }
  }

  void _nextDay() {
    if (_selectedDate.isBefore(_seasonEnd)) {
      setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
      _resetGameScroll();
      _loadGames();
      Future.delayed(const Duration(seconds: 3), () { if (mounted) _loadTomorrowGames(); });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: _seasonStart,
      lastDate: _seasonEnd,
      locale: const Locale('ko', 'KR'),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
      _loadGames();
      Future.delayed(const Duration(seconds: 3), () { if (mounted) _loadTomorrowGames(); });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ApiService.favoriteTeamsChanged.addListener(_loadFavoriteTeams);
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
    ApiService.favoriteTeamsChanged.removeListener(_loadFavoriteTeams);
    _authProvider?.removeListener(_onAuthChanged);
    _autoRefreshTimer?.cancel();
    _dateScrollController.dispose();
    _gameScrollController.dispose();
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
      _updateMyTeamData();
    }
    try {
      final data = await ApiService.getFavoriteTeams();
      final teams = data['teams'] as List? ?? [];
      await LocalCache.set('favorite_teams', teams);
      if (mounted) {
        setState(() {
          _favoriteTeamIds = Set.from(teams.map((t) => (t as Map)['id'] as int));
        });
        _updateMyTeamData();
      }
    } catch (_) {}
  }

  Future<void> _loadRankings() async {
    final cached = await LocalCache.get('team_rankings') as List?;
    if (cached != null && mounted) {
      setState(() => _rankings = cached);
      _updateMyTeamData();
    }
    try {
      final data = await ApiService.getTeamRankings();
      final rankings = data['rankings'] as List? ?? [];
      await LocalCache.set('team_rankings', rankings);
      if (mounted) {
        setState(() => _rankings = rankings);
        _updateMyTeamData();
      }
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
    // 캐시 날짜 불일치 시 (UTC/KST 불일치 등) 캐시 무효화 → 신선 fetch 강제
    try {
      if (cached != null && cached.isNotEmpty) {
        final cachedDate = (cached.first as Map)['game_date'];
        if (cachedDate != null && cachedDate != dateStr) cached = null;
      }
    } catch (_) {
      cached = null;
    }
    if (cached != null) {
      setState(() { _games = cached!; _isLoading = false; _loadError = false; });
      _updateMyTeamData();
    } else {
      setState(() => _isLoading = true);
    }

    try {
      // 오늘 날짜: /games/today (서버 30초 캐시) 사용 — /games/date/{date}는 5분 캐시라 스코어 갱신 지연
      print('[loadGames] dateStr=$dateStr isToday=$isToday calling API');
      final data = isToday
          ? await ApiService.getTodayGames()
          : await ApiService.getGamesByDate(dateStr);
      print('[loadGames] response keys=${data.keys.toList()} games_count=${(data['games'] as List?)?.length}');
      if (!mounted) { print('[loadGames] unmounted after API'); return; }
      if (_loadGen != gen) {
        print('[loadGames] loadGen mismatch $gen vs $_loadGen — skip');
        if (_isLoading) setState(() => _isLoading = false);
        return;
      }
      final games = data['games'] as List? ?? [];
      await LocalCache.set('games_$dateStr', games);
      if (!mounted || _loadGen != gen) { print('[loadGames] unmounted/gen after cache set'); return; }
      print('[loadGames] setState _games=${games.length} _isLoading=false');
      setState(() { _games = games; _isLoading = false; _loadError = false; });
      _updateMyTeamData();
      _prefetchAdjacentDates(dateStr);
      _prefetchGameDetails(games);
    } catch (e, st) {
      print('[loadGames] ERROR: $e\n$st');
      if (!mounted) return;
      if (_loadGen != gen) {
        if (_isLoading) setState(() => _isLoading = false);
        return;
      }
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

  void _updateMyTeamData() {
    if (!mounted) return;
    if (_favoriteTeamIds.isEmpty || _rankings.isEmpty) {
      ApiService.myTeamData.value = [];
      return;
    }
    final myRankings = _rankings.where((r) => _favoriteTeamIds.contains(r['id'] as int?)).toList();
    if (myRankings.isEmpty) {
      ApiService.myTeamData.value = [];
      return;
    }
    final chips = myRankings.map((r) {
      final Map ranking = r as Map;
      final teamId = ranking['id'] as int? ?? 0;
      final code = ranking['short_name'] as String? ?? '';
      final name = ranking['name'] as String? ?? '';
      final rank = ranking['rank'] as int? ?? 0;

      Map? todayGame;
      for (final g in _games) {
        final gm = g as Map;
        if (gm['home_team_id'] == teamId || gm['away_team_id'] == teamId) {
          todayGame = gm;
          break;
        }
      }

      final bool isHome = todayGame != null && todayGame['home_team_id'] == teamId;
      final oppName = todayGame != null
          ? (isHome ? todayGame['away_team'] as String? ?? '' : todayGame['home_team'] as String? ?? '')
          : '';

      String gameStr;
      String gameStatus;
      bool won = false;
      bool lost = false;

      if (todayGame == null) {
        gameStr = '경기 없음';
        gameStatus = '없음';
      } else {
        final status = todayGame['status'] as String? ?? '';
        gameStatus = status;
        final hs = todayGame['home_score'] as int? ?? 0;
        final as_ = todayGame['away_score'] as int? ?? 0;
        final myScore = isHome ? hs : as_;
        final oppScore = isHome ? as_ : hs;
        if (status == '예정' || status == '라인업') {
          gameStr = 'vs $oppName';
        } else if (status == '진행') {
          gameStr = '$myScore : $oppScore  vs $oppName';
        } else if (status == '종료') {
          gameStr = '$myScore : $oppScore  vs $oppName';
          won = myScore > oppScore;
          lost = myScore < oppScore;
        } else if (status == '취소') {
          gameStr = '취소';
        } else {
          gameStr = 'vs $oppName';
        }
      }

      return <String, dynamic>{
        'id': teamId,
        'code': code,
        'name': name,
        'rank': rank,
        'gameStr': gameStr,
        'gameStatus': gameStatus,
        'won': won,
        'lost': lost,
        'ranking': Map<String, dynamic>.from(ranking),
      };
    }).toList();

    ApiService.myTeamData.value = chips;
  }

  Widget _buildMonthStrip() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tk = _Tok.of(isDark);
    return SizedBox(
      height: 32,
      child: Row(
        children: List.generate(8, (i) {
          final month = i + 3;
          final isActive = _selectedDate.month == month;
          return Expanded(
            child: GestureDetector(
              onTap: () => _scrollToMonthStart(month),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive ? tk.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: isActive ? null : Border.all(color: tk.line2, width: 1),
                ),
                child: Center(
                  child: Text(
                    '$month월',
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: -0.2,
                      color: isActive ? (isDark ? Colors.black : Colors.white) : tk.ink2,
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
      clipBehavior: Clip.none,
      alignment: Alignment.centerRight,
      children: [
        SizedBox(
          height: 76,
          child: ListView.builder(
        controller: _dateScrollController,
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        itemCount: _totalDays,
        itemBuilder: (_, i) {
          final date = _seasonStart.add(Duration(days: i));
          final isSelected = _isSameDay(date, _selectedDate);
          final isToday = _isSameDay(date, today);
          final dayName = dayNames[date.weekday - 1];
          final isSat = date.weekday == DateTime.saturday;
          final isSun = date.weekday == DateTime.sunday;

          final tk = _Tok.of(isDark);
          Color nameColor;
          if (isSelected) {
            nameColor = isDark ? Colors.black54 : Colors.white70;
          } else if (isSun) {
            nameColor = const Color(0xFFE53935);
          } else if (isSat) {
            nameColor = const Color(0xFF1976D2);
          } else {
            nameColor = tk.sub;
          }

          return GestureDetector(
            onTap: () {
              if (!isSelected) {
                setState(() => _selectedDate = date);
                _loadGames();
                Future.delayed(const Duration(seconds: 3), () { if (mounted) _loadTomorrowGames(); });
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: _itemW - 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: isSelected ? tk.ink : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: isSelected ? null : Border.all(color: tk.line2, width: 1),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(dayName,
                      style: TextStyle(fontSize: 11, color: nameColor, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3,
                      color: isSelected ? (isDark ? Colors.black : Colors.white) : tk.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    width: 4, height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isToday && !isSelected ? _kLiveRed : Colors.transparent,
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
              child: Builder(builder: (_) {
                final tk = _Tok.of(isDark);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: tk.ink, borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('오늘',
                      style: TextStyle(
                          color: isDark ? Colors.black : Colors.white,
                          fontSize: 11, fontWeight: FontWeight.w800)),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildFilterChip(String label, bool isActive, VoidCallback onTap, {IconData? icon}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tk = _Tok.of(isDark);
    final activeColor = tk.ink;
    final fg = isActive ? (isDark ? Colors.black : Colors.white) : tk.ink3;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: isActive ? activeColor : tk.line2, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: fg),
              const SizedBox(width: 4),
            ],
            Text(label, style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: fg,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildDateNavHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final today = DateTime.now();
    final isToday = _isSameDay(_selectedDate, today);
    final prev = _selectedDate.subtract(const Duration(days: 1));
    final next = _selectedDate.add(const Duration(days: 1));
    final canPrev = _selectedDate.isAfter(_seasonStart);
    final canNext = _selectedDate.isBefore(_seasonEnd);
    String fmtShort(DateTime d) => '${d.month}/${d.day}';

    final dim = isDark ? Colors.white38 : Colors.black38;
    final arrowC = isDark ? Colors.white60 : Colors.black45;

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -250 && canNext) _nextDay();
        else if (v > 250 && canPrev) _prevDay();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.scaffoldDark : AppColors.surfaceLight,
          border: Border(bottom: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
            width: 0.5,
          )),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // 이전날
                Expanded(
                  child: GestureDetector(
                    onTap: canPrev ? _prevDay : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.chevron_left, size: 20, color: canPrev ? arrowC : Colors.transparent),
                          const SizedBox(width: 2),
                          Text(fmtShort(prev), style: TextStyle(fontSize: 13, color: canPrev ? dim : Colors.transparent)),
                        ],
                      ),
                    ),
                  ),
                ),
                // 오늘 바로가기
                GestureDetector(
                  onTap: isToday ? null : () {
                    setState(() { _selectedDate = today; _isLoading = true; _games = []; _loadGen++; });
                    _loadGames();
                    _loadTomorrowGames();
                  },
                  onLongPress: _pickDate,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: isToday ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isToday ? AppColors.primary.withOpacity(0.3) : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      isToday ? '오늘' : '오늘로',
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: isToday ? AppColors.primary : dim,
                      ),
                    ),
                  ),
                ),
                // 다음날
                Expanded(
                  child: GestureDetector(
                    onTap: canNext ? _nextDay : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(fmtShort(next), style: TextStyle(fontSize: 13, color: canNext ? dim : Colors.transparent)),
                          const SizedBox(width: 2),
                          Icon(Icons.chevron_right, size: 20, color: canNext ? arrowC : Colors.transparent),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_favoriteTeamIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _buildFilterChip('전체', !_myTeamOnly, () => setState(() => _myTeamOnly = false)),
                    const SizedBox(width: 8),
                    _buildFilterChip('마이팀', _myTeamOnly, () => setState(() => _myTeamOnly = true), icon: Icons.star),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const dayNames = ['월', '화', '수', '목', '금', '토', '일'];
    final dayName = dayNames[_selectedDate.weekday - 1];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_baseball,
                size: 18,
                color: isDark ? const Color(0xFFF4F4F5) : AppColors.primary),
            const SizedBox(width: 7),
            Text('PlayBall',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isDark ? const Color(0xFFF5F5F5) : AppColors.primary,
                  letterSpacing: -0.3,
                )),
          ],
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
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
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
            icon: const Icon(Icons.search),
            tooltip: '검색',
            onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: '마이페이지',
            onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const MyPageScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          // 월/날짜 스트립 — AppBar와 동일한 배경색
          Container(
            color: isDark ? AppColors.scaffoldDark : AppColors.scaffoldLight,
            child: Column(
              children: [
                _buildMonthStrip(),
                _buildDateStrip(),
              ],
            ),
          ),
          if (_todayRosterChanges.isNotEmpty && _isSameDay(_selectedDate, DateTime.now()))
            _buildTodayRosterBanner(),
          if (_favoriteTeamIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
              child: Row(
                children: [
                  _buildFilterChip('전체', !_myTeamOnly, () => setState(() => _myTeamOnly = false)),
                  const SizedBox(width: 8),
                  _buildFilterChip('마이팀', _myTeamOnly, () => setState(() => _myTeamOnly = true), icon: Icons.star),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _isLoading ? _buildGameShimmer() : _buildGameList(),
                AnimatedBuilder(
                  animation: _gameScrollController,
                  builder: (ctx, _) {
                    final offset = _gameScrollController.hasClients
                        ? _gameScrollController.offset
                        : 0.0;
                    final opacity = (offset / 48.0).clamp(0.0, 1.0);
                    if (opacity == 0) return const SizedBox.shrink();
                    final scaffoldBg = Theme.of(ctx).brightness == Brightness.dark
                        ? AppColors.scaffoldDark
                        : AppColors.scaffoldLight;
                    return Positioned(
                      top: 0, left: 0, right: 0,
                      height: 52,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: opacity,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [scaffoldBg, scaffoldBg.withOpacity(0)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더 + 필터 칩 통합
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 6),
            child: Row(
              children: [
                const Icon(Icons.star, size: 13, color: AppColors.primary),
                const SizedBox(width: 5),
                const Text('마이팀',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary)),
                const Spacer(),
                _buildFilterChip('전체', !_myTeamOnly,
                    () => setState(() => _myTeamOnly = false)),
                const SizedBox(width: 6),
                _buildFilterChip('마이팀', _myTeamOnly,
                    () => setState(() => _myTeamOnly = true), icon: Icons.star),
              ],
            ),
          ),
          SizedBox(
            height: 66,
            child: Stack(
              children: [
                ListView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                  children: myRankings.map((r) => _buildMyTeamCard(r as Map)).toList(),
                ),
                // 좌측 fade
                Positioned(
                  left: 0, top: 0, bottom: 0, width: 24,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                            (isDark ? AppColors.surfaceDark : AppColors.surfaceLight).withOpacity(0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // 우측 fade
                Positioned(
                  right: 0, top: 0, bottom: 0, width: 24,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                          colors: [
                            isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                            (isDark ? AppColors.surfaceDark : AppColors.surfaceLight).withOpacity(0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
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
        width: 158,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withOpacity(0.2), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 상단: 로고 + 팀명 + 순위
            Row(
              children: [
                TeamLogo(teamCode: code, size: 22),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: rankBg, borderRadius: BorderRadius.circular(8)),
                  child: Text('${rank}위',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            // 하단: 오늘 경기 + 연속
            Row(
              children: [
                if (showWinIcon) const Icon(Icons.arrow_upward, size: 9, color: Colors.blue),
                if (showLossIcon) const Icon(Icons.arrow_downward, size: 9, color: Colors.red),
                Expanded(
                  child: Text(gameStr,
                      style: TextStyle(fontSize: 11, color: gameColor, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
                if (streakText.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(streakText,
                      style: TextStyle(fontSize: 11, color: streakColor, fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _listBottomPad(BuildContext context) {
    // tab pill 58 + optional myTeam pill (44 + 8 gap) + 16 margin + 18 clearance
    final navBarH = ApiService.myTeamData.value.isNotEmpty ? 110.0 : 58.0;
    return navBarH + 34 + MediaQuery.of(context).padding.bottom;
  }

  Widget _buildGameShimmer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(0, 8, 0, _listBottomPad(context)),
      itemCount: 4,
      itemBuilder: (_, i) => Shimmer.fromColors(
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
          padding: EdgeInsets.only(bottom: _listBottomPad(context)),
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
                      foregroundColor: const Color(0xFF111113),
                      side: const BorderSide(color: Color(0xFF111113)),
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
                        foregroundColor: const Color(0xFF111113),
                        side: const BorderSide(color: Color(0xFF111113)),
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
        controller: _gameScrollController,
        padding: EdgeInsets.fromLTRB(16, 8, 16, _listBottomPad(context)),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final g = filtered[index];
          final homeId = g['home_team_id'] as int? ?? 0;
          final awayId = g['away_team_id'] as int? ?? 0;
          final isMyTeam = _favoriteTeamIds.contains(homeId) ||
              _favoriteTeamIds.contains(awayId);
          // 마이팀이 home/away 중 어느 쪽인지 결정 → 올바른 팀색 전달
          final myTeamIsHome = _favoriteTeamIds.contains(homeId);
          final myTeamIsAway = _favoriteTeamIds.contains(awayId);
          return GameCard(
            key: ValueKey(g['id']),
            game: Game.fromJson(g),
            isMyTeam: isMyTeam && !_myTeamOnly,
            myTeamIsHome: myTeamIsHome,
            myTeamIsAway: myTeamIsAway,
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
      final gameDate = gm['game_date'] as String? ?? '';
      // 현재 날짜 이하 게임 무시 (stale 캐시 방어)
      if (gameDate.isEmpty || gameDate.compareTo(_selectedDateStr) <= 0) continue;
      final homeId = gm['home_team_id'] as int? ?? 0;
      final awayId = gm['away_team_id'] as int? ?? 0;
      if (homeId != teamId && awayId != teamId) continue;
      final oppId = homeId == teamId ? awayId : homeId;
      if (oppId == currentOpponentId) continue;
      final oppName = homeId == teamId ? gm['away_team'] as String? ?? '' : gm['home_team'] as String? ?? '';
      final oppCode = homeId == teamId ? gm['away_team_code'] as String? ?? '' : gm['home_team_code'] as String? ?? '';
      return {'code': oppCode, 'name': oppName, 'date': gameDate};
    }
    return null;
  }

  bool _rosterBannerExpanded = false;

  Widget _buildTodayRosterBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = _Tok.of(isDark);
    final changes = _todayRosterChanges;
    final registrations = changes.where((c) => c['change_type'] == '1군등록').toList();
    final removals = changes.where((c) => c['change_type'] == '등록말소').toList();
    final injuries = changes.where((c) => c['change_type'] == '부상자명단').toList();

    return InkWell(
      onTap: () => setState(() => _rosterBannerExpanded = !_rosterBannerExpanded),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        decoration: BoxDecoration(
          color: t.paper,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.line, width: 1),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
              child: Row(children: [
                Icon(Icons.swap_horiz, size: 16, color: t.ink2),
                const SizedBox(width: 6),
                Text('오늘 등록말소',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: t.ink, letterSpacing: -0.15)),
                const SizedBox(width: 8),
                if (registrations.isNotEmpty)
                  _rosterChip('${registrations.length}명 등록', const Color(0xFF1976D2), t),
                if (removals.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _rosterChip('${removals.length}명 말소', const Color(0xFFFFA000), t),
                ],
                if (injuries.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _rosterChip('${injuries.length}명 부상', const Color(0xFFE53935), t),
                ],
                const Spacer(),
                Icon(_rosterBannerExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: t.sub),
              ]),
            ),
            if (_rosterBannerExpanded)
              Container(
                decoration: BoxDecoration(
                  color: t.paper2,
                  border: Border(top: BorderSide(color: t.line, width: 1)),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: Column(
                        children: changes.map((c) {
                          final type = c['change_type'] as String? ?? '';
                          Color col = type == '1군등록' ? const Color(0xFF1976D2)
                              : type == '등록말소' ? const Color(0xFFFFA000)
                              : type == '부상자명단' ? const Color(0xFFE53935) : t.ink3;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: col.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(type, style: TextStyle(fontSize: 11, color: col, fontWeight: FontWeight.w800)),
                              ),
                              const SizedBox(width: 8),
                              Text(c['team_name'] ?? '', style: TextStyle(fontSize: 11, color: t.ink3, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 4),
                              Text(c['player_name'] ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.ink)),
                              if ((c['reason'] as String? ?? '').isNotEmpty) ...[
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text('(${c['reason']})',
                                      style: TextStyle(fontSize: 11, color: t.sub),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ]),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _rosterChip(String label, Color color, _Tok t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w800)),
  );
}

// ===== Winner Glow Logo =====


class GameCard extends StatelessWidget {
  final Game game;
  final bool isMyTeam;
  final bool myTeamIsHome;
  final bool myTeamIsAway;
  final int? homeRank;
  final int? awayRank;
  final Map<String, String>? nextHomeSeries;
  final Map<String, String>? nextAwaySeries;

  const GameCard({super.key, required this.game, this.isMyTeam = false,
      this.myTeamIsHome = false, this.myTeamIsAway = false,
      this.homeRank, this.awayRank, this.nextHomeSeries, this.nextAwaySeries});

  Widget _starterChip(String name, _Tok t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: t.paper2,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: t.line2, width: 1),
    ),
    child: Text(name,
        style: TextStyle(fontSize: 11, color: t.ink2, fontWeight: FontWeight.w700),
        overflow: TextOverflow.ellipsis),
  );

  Widget _buildNextSeriesInline(Map<String, String> series, _Tok t) {
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
        Text('다음 ', style: TextStyle(fontSize: 11, color: t.sub)),
        TeamLogo(teamCode: series['code'] ?? '', size: 15),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            '${series['name'] ?? ''}$dateLabel',
            style: TextStyle(fontSize: 11, color: t.ink3, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis, maxLines: 1,
          ),
        ),
      ],
    );
  }

  Widget? _buildWeatherWidget(_Tok t) {
    final w = game.weather;
    if (w == null) return null;
    if (w['indoor'] == true) {
      return Text('실내', style: TextStyle(fontSize: 11, color: t.sub));
    }
    final emoji = w['emoji'] ?? '';
    final temp = w['temp'];
    final pop = w['pop'];
    final popVal = pop is num ? pop.toInt() : null;
    final parts = <String>[
      if (emoji.isNotEmpty) emoji,
      if (temp != null) '${temp}°',
      if (popVal != null && popVal > 0) '$popVal%',
    ];
    if (parts.isEmpty) return null;
    return Text(parts.join(' '),
        style: TextStyle(fontSize: 11, color: t.ink3, fontWeight: FontWeight.w600));
  }

  // 다크 모드: 어두운 팀색(KT/NC/두산 등) lightness 부스트로 가시성 확보
  // 라이트 모드: 너무 밝은 팀색 약간 어둡게 (대비 확보)
  Color _adjustTeamColor(Color c, bool isDark) {
    final hsl = HSLColor.fromColor(c);
    if (isDark) {
      // lightness < 0.45 인 색만 부스트 (밝은 색은 그대로)
      if (hsl.lightness < 0.45) {
        return hsl.withLightness((hsl.lightness + 0.30).clamp(0.0, 0.75)).toColor();
      }
      return c;
    } else {
      // 라이트: lightness > 0.6인 색만 약간 어둡게
      if (hsl.lightness > 0.6) {
        return hsl.withLightness((hsl.lightness - 0.10).clamp(0.0, 1.0)).toColor();
      }
      return c;
    }
  }

  Widget _buildMini5(List<String> recent, Color accent, _Tok t, bool isDark) {
    if (recent.isEmpty) return const SizedBox(height: 13);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: recent.map((r) {
        final isW = r == 'W';
        final fill = isW ? accent : t.track;
        final fg = isW ? (isDark ? const Color(0xFF0F0F12) : Colors.white) : t.sub;
        return Padding(
          padding: const EdgeInsets.only(right: 2.5),
          child: Container(
            width: 13, height: 13,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(4)),
            child: Text(r,
                style: TextStyle(fontSize: 7, fontWeight: FontWeight.w800, color: fg)),
          ),
        );
      }).toList(),
    );
  }

  Widget _stadiumChip(BuildContext context, _Tok t) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StadiumScreen(
          initialIndex: game.stadiumId != null ? game.stadiumId! - 1 : null,
        )),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: t.paper2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: t.line2, width: 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.map_outlined, size: 11, color: t.ink3),
          const SizedBox(width: 4),
          Text('지도 · ${game.stadium!}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.ink2)),
          const SizedBox(width: 2),
          Icon(Icons.chevron_right, size: 12, color: t.ink3),
        ]),
      ),
    );
  }

  Widget _weatherChip(_Tok t) {
    final w = game.weather;
    if (w == null) return const SizedBox.shrink();
    String label;
    if (w['indoor'] == true) {
      label = '실내';
    } else {
      final emoji = w['emoji'] ?? '';
      final temp = w['temp'];
      final pop = w['pop'];
      final popVal = pop is num ? pop.toInt() : null;
      final parts = <String>[
        if (emoji.isNotEmpty) emoji,
        if (temp != null) '${temp}°',
        if (popVal != null && popVal > 0) '$popVal%',
      ];
      if (parts.isEmpty) return const SizedBox.shrink();
      label = parts.join(' ');
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: t.paper2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 5, height: 5,
            decoration: BoxDecoration(color: t.line2, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.ink3)),
      ]),
    );
  }

  Widget _teamSide({
    required String code, required String name, required int? rank,
    required bool isHome, required bool isWinner,
    required List<String> recent,
    required Color accent,
    required _Tok t, required bool isDark,
    int? teamId,
    BuildContext? buildContext,
  }) {
    // logo + winner overlay (logo center에 정확 일치)
    // SizedBox(46)로 Stack 영역 고정 → overlay overflow는 clipBehavior.none + Card boundary로 clip
    Widget logo = SizedBox(
      width: 46, height: 46,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (isWinner)
            IgnorePointer(
              child: Opacity(
                opacity: isDark ? 0.13 : 0.11,
                child: TeamLogo(teamCode: code, size: 290),
              ),
            ),
          TeamLogo(teamCode: code, size: 46),
        ],
      ),
    );
    if (teamId != null && buildContext != null) {
      logo = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.push(buildContext,
            MaterialPageRoute(builder: (_) => TeamDetailScreen(
                team: {'id': teamId, 'short_name': code, 'name': name}))),
        child: logo,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        const SizedBox(height: 7),
        Text(name,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: t.ink, letterSpacing: -0.15),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 5),
        Text(rank != null ? '${rank}위' : (isHome ? '홈' : '원정'),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.sub)),
        const SizedBox(height: 7),
        // 각 팀 mini5 W 박스 = 자기 팀 컬러 (라이트/다크 모드 보정)
        _buildMini5(isHome ? recent.reversed.toList() : recent, _adjustTeamColor(teamColor(code), isDark), t, isDark),
      ],
    );
  }

  // 선발/승투/패투 — 가운데 정렬 단일 텍스트
  Widget _centerPitcherCell({
    required String? starter,
    required String? pitcher, required String? pitcherLabel, required Color? pitcherLabelColor,
    required _Tok t,
  }) {
    if (pitcher != null && pitcher.isNotEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: (pitcherLabelColor ?? t.ink3).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(pitcherLabel ?? '',
                style: TextStyle(fontSize: 11, color: pitcherLabelColor ?? t.ink3, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(pitcher,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.ink2),
                overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
        ],
      );
    }
    if (starter != null && starter.isNotEmpty) {
      return Text(starter,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.ink2),
          overflow: TextOverflow.ellipsis, maxLines: 1);
    }
    return Text('-', style: TextStyle(fontSize: 11, color: t.line2));
  }

  Widget _centerNextSeriesCell(Map<String, String>? ns, _Tok t) {
    if (ns == null) return Text('-', style: TextStyle(fontSize: 11, color: t.line2));
    // date "YYYY-MM-DD" → "M/D"
    String dateLabel = '';
    final ds = ns['date'] ?? '';
    if (ds.length >= 10) {
      final parts = ds.split('-');
      if (parts.length == 3) {
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (m != null && d != null) dateLabel = '$m/$d';
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            TeamLogo(teamCode: ns['code'] ?? '', size: 15),
            const SizedBox(width: 4),
            Flexible(
              child: Text(ns['name'] ?? '',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.ink3),
                  overflow: TextOverflow.ellipsis, maxLines: 1),
            ),
          ],
        ),
        if (dateLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(dateLabel,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.sub,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = _Tok.of(isDark);
    final isFinished = game.status == '종료';
    final isDraw = game.isDraw ?? false;
    final homeWon = isFinished && !isDraw && game.homeScore > game.awayScore;
    final awayWon = isFinished && !isDraw && game.awayScore > game.homeScore;
    final isLive = game.status == '진행';
    final showStarters = game.status == '예정' || game.status == '라인업' || isLive;
    final showPrediction = (game.status == '예정' || game.status == '라인업') &&
        game.homeTeamId != null && game.awayTeamId != null;
    final isCancelled = game.status == '취소';
    final isUpcoming = !isFinished && !isLive && !isCancelled;

    final homeColor = teamColor(game.homeTeamCode);
    final awayColor = teamColor(game.awayTeamCode);
    // 마이팀 색: 한화가 home이면 homeColor, away면 awayColor (둘 다 마이팀인 경우 홈 우선)
    final myColor = myTeamIsHome ? homeColor : (myTeamIsAway ? awayColor : homeColor);
    // accent: 마이팀이면 팀색, 아니면 ink (승팀 강조용)
    final accent = isMyTeam ? myColor : t.ink;

    // ── 상태 pill ──
    Widget statusPill() {
      if (isLive) {
        // 라이브: LIVE dot + 'N회 초/말'
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _kLiveRed.withValues(alpha: isDark ? 0.20 : 0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 5, height: 5,
                decoration: const BoxDecoration(color: _kLiveRed, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text('${game.currentInning ?? 0}회 ${game.inningHalf ?? ''}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _kLiveRed)),
          ]),
        );
      }
      if (isCancelled) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: t.paper2, borderRadius: BorderRadius.circular(999)),
          child: Text('취소',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.ink3)),
        );
      }
      if (isFinished) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: t.paper2, borderRadius: BorderRadius.circular(999)),
          child: Text('경기 종료',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.ink3)),
        );
      }
      if (game.status == '라인업') {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFFFA000).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text('라인업',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFFFA000))),
        );
      }
      // 예정 + 그 외 상태: 상태 텍스트만 (시작시간 X — 시간은 score 자리에 표시)
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: t.paper2, borderRadius: BorderRadius.circular(999)),
        child: Text(game.status.isEmpty ? '예정' : game.status,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.ink2)),
      );
    }

    // ── 정보 (TeamSide에 inline 통합) ──
    final hasPitchers = isFinished && !isDraw && (game.winPitcher != null || game.losePitcher != null);
    final hasStarters = showStarters && (game.homeStarter != null || game.awayStarter != null);

    // 카드 배경: 항상 paper (마이팀 배경색 적용 X)
    final winnerColor = homeWon ? homeColor : (awayWon ? awayColor : null);
    final cardBg = t.paper;
    final cardBd = t.line;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBd, width: 1),
        boxShadow: (!isMyTeam && !isDark) ? [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 2, offset: const Offset(0, 1)),
        ] : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GameDetailScreen(gameId: game.id))),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── 헤더: 날씨 + 구장 | 마이팀 + status ──
                Row(
                  children: [
                    _weatherChip(t),
                    if (game.stadium != null) ...[
                      const SizedBox(width: 6),
                      _stadiumChip(context, t),
                    ],
                    const Spacer(),
                    if (isMyTeam) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(color: myColor, borderRadius: BorderRadius.circular(5)),
                        child: const Text('마이팀',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                      const SizedBox(width: 7),
                    ],
                    statusPill(),
                  ],
                ),
                const SizedBox(height: 13),
                // ── 메인 grid: TeamSide | score | TeamSide ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: _teamSide(
                      code: game.homeTeamCode, name: game.homeTeam, rank: homeRank,
                      isHome: true, isWinner: homeWon,
                      recent: game.homeRecent5, accent: accent, t: t, isDark: isDark,
                      teamId: game.homeTeamId, buildContext: context,
                    )),
                    SizedBox(
                      width: 86,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isUpcoming)
                            Text(
                              isCancelled ? '취소' : (game.startTime ?? 'VS'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800,
                                color: t.ink3, letterSpacing: -0.3,
                              ),
                            )
                          else
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text('${game.homeScore}',
                                    style: TextStyle(
                                      fontSize: homeWon ? 34 : 26,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.6,
                                      color: homeWon ? t.ink : (isDraw ? t.ink : t.ink2.withValues(alpha: 0.55)),
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    )),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 9),
                                  child: Text(':',
                                      style: TextStyle(
                                        fontSize: 22, fontWeight: FontWeight.w400, color: t.line2,
                                      )),
                                ),
                                Text('${game.awayScore}',
                                    style: TextStyle(
                                      fontSize: awayWon ? 34 : 26,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.6,
                                      color: awayWon ? t.ink : (isDraw ? t.ink : t.ink2.withValues(alpha: 0.55)),
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    )),
                              ],
                            ),
                          if (isLive) ...[
                            const SizedBox(height: 6),
                            Text('${game.currentInning ?? 0}회 ${game.inningHalf ?? ''}',
                                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: _kLiveRed),
                                textAlign: TextAlign.center),
                          ],
                          if (isFinished && isDraw) ...[
                            const SizedBox(height: 6),
                            Text('무승부',
                                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: t.ink3),
                                textAlign: TextAlign.center),
                          ],
                        ],
                      ),
                    ),
                    Expanded(child: _teamSide(
                      code: game.awayTeamCode, name: game.awayTeam, rank: awayRank,
                      isHome: false, isWinner: awayWon,
                      recent: game.awayRecent5, accent: accent, t: t, isDark: isDark,
                      teamId: game.awayTeamId, buildContext: context,
                    )),
                  ],
                ),
                // ── divider + 선발 + 다음 시리즈 (footer 영역, overlay 안 침범) ──
                if (hasPitchers || hasStarters || nextHomeSeries != null || nextAwaySeries != null)
                  Container(
                    margin: const EdgeInsets.only(top: 13),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(height: 1, color: t.line, margin: const EdgeInsets.only(bottom: 11)),
                  // 선발/승투/패투 row
                  if (hasPitchers || hasStarters)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(child: _centerPitcherCell(
                            starter: hasStarters ? game.homeStarter : null,
                            pitcher: hasPitchers ? (homeWon ? game.winPitcher : game.losePitcher) : null,
                            pitcherLabel: hasPitchers ? (homeWon ? '승' : '패') : null,
                            pitcherLabelColor: hasPitchers
                                ? (homeWon ? const Color(0xFF1976D2) : const Color(0xFFC62828))
                                : null,
                            t: t,
                          )),
                          SizedBox(
                            width: 78,
                            child: Text(hasPitchers ? '결과' : '선발',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.sub)),
                          ),
                          Expanded(child: _centerPitcherCell(
                            starter: hasStarters ? game.awayStarter : null,
                            pitcher: hasPitchers ? (awayWon ? game.winPitcher : game.losePitcher) : null,
                            pitcherLabel: hasPitchers ? (awayWon ? '승' : '패') : null,
                            pitcherLabelColor: hasPitchers
                                ? (awayWon ? const Color(0xFF1976D2) : const Color(0xFFC62828))
                                : null,
                            t: t,
                          )),
                        ],
                      ),
                    ),
                  // 다음 시리즈 row
                  if (nextHomeSeries != null || nextAwaySeries != null)
                    Row(
                      children: [
                        Expanded(child: _centerNextSeriesCell(nextHomeSeries, t)),
                        SizedBox(
                          width: 78,
                          child: Text('다음 시리즈',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.sub)),
                        ),
                        Expanded(child: _centerNextSeriesCell(nextAwaySeries, t)),
                      ],
                    ),
                      ],
                    ),
                  ),
                if (showPrediction)
                  Container(
                    margin: const EdgeInsets.only(top: 13),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(height: 1, color: t.line, margin: const EdgeInsets.only(bottom: 11)),
                        _PredictionBar(
                          key: ValueKey(game.id),
                          gameId: game.id,
                          homeTeamId: game.homeTeamId!,
                          awayTeamId: game.awayTeamId!,
                          homeCode: game.homeTeamCode,
                          awayCode: game.awayTeamCode,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _symmetricPitcher(_Tok t, bool homeWon, bool isLeftSide) {
    // 좌측 = 홈, 우측 = 원정
    final isHomeSide = isLeftSide;
    final isWinSide = isHomeSide == homeWon;
    final name = isWinSide ? game.winPitcher : game.losePitcher;
    if (name == null) return const SizedBox.shrink();
    final label = isWinSide ? '승' : '패';
    final col = isWinSide ? const Color(0xFF1976D2) : const Color(0xFFC62828);
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: col, fontWeight: FontWeight.w800)),
    );
    final nameText = Text(name,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.ink2),
        overflow: TextOverflow.ellipsis, maxLines: 1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: isLeftSide
          ? [badge, const SizedBox(width: 4), nameText]
          : [nameText, const SizedBox(width: 4), badge],
    );
  }

  Widget _nextSeriesInline(Map<String, String> series, _Tok t) {
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
        Text('다음 ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: t.sub)),
        TeamLogo(teamCode: series['code'] ?? '', size: 15),
        const SizedBox(width: 3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 90),
          child: Text('${series['name'] ?? ''}$dateLabel',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.ink3),
              overflow: TextOverflow.ellipsis, maxLines: 1),
        ),
      ],
    );
  }

  Widget _strippedLabel({required String label, required Widget value, required _Tok t}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.sub)),
        const SizedBox(height: 4),
        value,
      ],
    );
  }

  Widget _buildStarterValue(_Tok t, String? h, String? a) {
    final parts = <String>[];
    if (h != null && h.isNotEmpty) parts.add(h);
    if (a != null && a.isNotEmpty) parts.add(a);
    return Text(parts.join(' · '),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.ink2),
        maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  Widget _buildPitcherValue(_Tok t, bool homeWon, bool awayWon) {
    final winName = game.winPitcher;
    final loseName = game.losePitcher;
    final parts = <String>[];
    if (winName != null) parts.add('승 $winName');
    if (loseName != null) parts.add('패 $loseName');
    return Text(parts.join(' · '),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.ink2),
        maxLines: 1, overflow: TextOverflow.ellipsis);
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
  // ML 모델 예측 결과 cache
  static final Map<int, Map<String, dynamic>> _cache = {};

  double? _homeProb;
  double? _awayProb;
  String _homeStarter = '';
  String _awayStarter = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _applyCache();
    if (_loading) _load();
  }

  @override
  void didUpdateWidget(_PredictionBar old) {
    super.didUpdateWidget(old);
    if (old.gameId != widget.gameId) {
      _applyCache();
      if (_loading) _load();
    }
  }

  void _applyCache() {
    final cached = _cache[widget.gameId];
    if (cached != null) {
      _homeProb = (cached['home_prob'] as num?)?.toDouble();
      _awayProb = (cached['away_prob'] as num?)?.toDouble();
      _homeStarter = cached['home_starter'] as String? ?? '';
      _awayStarter = cached['away_starter'] as String? ?? '';
      _loading = false;
    }
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.getWinPrediction(widget.gameId);
      debugPrint('[PredBar ${widget.gameId}] data=$data');
      _cache[widget.gameId] = data;
      if (mounted) setState(() {
        _homeProb = (data['home_prob'] as num?)?.toDouble();
        _awayProb = (data['away_prob'] as num?)?.toDouble();
        _homeStarter = data['home_starter'] as String? ?? '';
        _awayStarter = data['away_starter'] as String? ?? '';
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('[PredBar ${widget.gameId}] ERROR: $e\n$st');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = _Tok.of(isDark);
    final homeP = _homeProb ?? 0.5;
    final awayP = _awayProb ?? 0.5;
    final homePctStr = _loading ? '-' : '${(homeP * 100).round()}%';
    final awayPctStr = _loading ? '-' : '${(awayP * 100).round()}%';

    final homeColor = teamColor(widget.homeCode);
    final awayColor = teamColor(widget.awayCode);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Text('AI 승리 예측',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: t.ink3, letterSpacing: 0.2)),
              const Spacer(),
              Text('ML 모델',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.sub)),
            ],
          ),
        ),
        // 좌(홈) - 우(원정) 분할 바
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 24,
            child: Row(
              children: [
                Flexible(
                  flex: (homeP * 1000).round().clamp(50, 950),
                  child: Container(
                    color: homeColor.withValues(alpha: isDark ? 0.55 : 0.78),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('${teamDisplayName(widget.homeCode)} $homePctStr',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()]),
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
                Container(width: 1, color: t.paper),
                Flexible(
                  flex: (awayP * 1000).round().clamp(50, 950),
                  child: Container(
                    color: awayColor.withValues(alpha: isDark ? 0.55 : 0.78),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('${teamDisplayName(widget.awayCode)} $awayPctStr',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()]),
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_homeStarter.isNotEmpty || _awayStarter.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text('$_homeStarter vs $_awayStarter',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.sub)),
        ],
      ],
    );
  }
}