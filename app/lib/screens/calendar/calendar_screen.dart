// calendar_screen.dart — Option A 디자인 시스템 반영 (2026-06)
import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../api/api_service.dart';
import '../../utils/local_cache.dart';
import '../../utils/team_theme.dart';
import '../game/game_detail_screen.dart';
import '../mypage/my_page_screen.dart';
import '../../widgets/stadium_ranking_sheet.dart';
import 'cal_event_add_screen.dart';
import 'visit_record_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedMonth = DateTime.now();
  Map<String, List> _gamesByDate = {};
  List<Map> _personalEvents = [];
  Map<int, Map> _visitedGames = {}; // gameId → visit {id, result, memo}
  bool _isLoading = false;
  DateTime? _selectedDate;
  Set<int> _favoriteTeamIds = {};
  String? _myTeamCode;
  bool _myTeamOnly = false;

  @override
  void initState() {
    super.initState();
    _loadCalendar();
    _loadPersonalEvents();
    _loadFavoriteTeams();
  }

  void _applyFavorites(List teams) {
    _favoriteTeamIds = Set.from(teams.map((t) => (t as Map)['id'] as int));
    _myTeamCode = teams.isNotEmpty ? (teams.first as Map)['short_name'] as String? : null;
  }

  Future<void> _loadFavoriteTeams() async {
    final cached = await LocalCache.get('favorite_teams') as List?;
    if (cached != null && mounted) {
      setState(() => _applyFavorites(cached));
    }
    try {
      final data = await ApiService.getFavoriteTeams();
      final teams = data['teams'] as List? ?? [];
      await LocalCache.set('favorite_teams', teams);
      if (mounted) setState(() => _applyFavorites(teams));
    } catch (_) {}
  }

  String get _calendarCacheKey =>
      'calendar_${_focusedMonth.year}_${_focusedMonth.month}';

  Future<void> _loadCalendar() async {
    // 캐시 즉시 표시
    final cached = await LocalCache.get(_calendarCacheKey, maxAgeSeconds: 300) as Map?;
    if (cached != null && mounted) {
      final raw = Map<String, dynamic>.from(cached);
      setState(() {
        _gamesByDate = raw.map((k, v) => MapEntry(k, v as List));
        _isLoading = false;
        _autoSelectToday();
      });
    } else {
      setState(() => _isLoading = true);
    }

    // 백그라운드 갱신
    try {
      final data = await ApiService.getCalendar(_focusedMonth.year, _focusedMonth.month);
      final raw = data['games'] as Map<String, dynamic>? ?? {};
      await LocalCache.set(_calendarCacheKey, raw);
      if (mounted) {
        setState(() {
        _gamesByDate = raw.map((k, v) => MapEntry(k, v as List));
        _isLoading = false;
        _autoSelectToday();
      });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _autoSelectToday() {
    final today = DateTime.now();
    if (today.year == _focusedMonth.year && today.month == _focusedMonth.month) {
      _selectedDate = DateTime(today.year, today.month, today.day);
    } else {
      _selectedDate ??= null;
    }
  }

  Future<void> _loadPersonalEvents() async {
    try {
      final results = await Future.wait([
        ApiService.getCalendarEvents(_focusedMonth.year, _focusedMonth.month),
        ApiService.getStadiumVisits(limit: 200),
      ]);
      final events = ((results[0] as Map)['events'] as List? ?? []).cast<Map>();
      final visits = ((results[1] as Map)['visits'] as List? ?? []).cast<Map>();
      final visitMap = <int, Map>{};
      for (final v in visits) {
        final gid = v['game_id'] as int?;
        if (gid != null) visitMap[gid] = v;
      }
      if (mounted) setState(() { _personalEvents = events; _visitedGames = visitMap; });
    } catch (_) {
      try {
        final data = await ApiService.getCalendarEvents(_focusedMonth.year, _focusedMonth.month);
        final events = (data['events'] as List? ?? []).cast<Map>();
        if (mounted) setState(() => _personalEvents = events);
      } catch (_) {}
    }
  }

  void _prevMonth() {
    setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1));
    _loadCalendar();
    _loadPersonalEvents();
  }

  void _nextMonth() {
    setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1));
    _loadCalendar();
    _loadPersonalEvents();
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List _gamesOn(DateTime d) {
    final all = _gamesByDate[_dateKey(d)] ?? [];
    if (!_myTeamOnly || _favoriteTeamIds.isEmpty) return all;
    return all.where((g) {
      final homeId = (g as Map)['home_team_id'] as int?;
      final awayId = g['away_team_id'] as int?;
      return _favoriteTeamIds.contains(homeId) || _favoriteTeamIds.contains(awayId);
    }).toList();
  }

  // dateKey → visit result for days with a visited game (current month data)
  Map<String, String> get _dayVisitResult {
    final map = <String, String>{};
    for (final entry in _gamesByDate.entries) {
      for (final game in entry.value) {
        final id = game['id'] as int?;
        if (id != null && _visitedGames.containsKey(id)) {
          final r = _visitedGames[id]!['result'] as String? ?? 'draw';
          map[entry.key] = r;
          break;
        }
      }
    }
    return map;
  }

  // ── 빌드 ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = _C(context);
    final myColor = _myTeamCode != null ? teamColor(_myTeamCode) : SemColor.brand(context);
    final bottomPad = (ApiService.myTeamData.value.isNotEmpty ? 130.0 : 80.0)
        + MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      backgroundColor: cs.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _buildAppBar(cs, myColor),
          Expanded(child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: bottomPad),
            child: Column(children: [
              _buildMonthNav(cs),
              _buildVisitStatsBar(cs, myColor),
              _buildDowHeader(cs),
              _isLoading ? _buildCalendarShimmer() : _buildCalendarGrid(cs, myColor),
              Divider(height: 1, color: cs.line),
              _buildDayDetail(cs),
            ]),
          )),
        ]),
      ),
    );
  }

  Widget _buildAppBar(_C cs, Color myColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      decoration: BoxDecoration(color: cs.paper, border: Border(bottom: BorderSide(color: cs.line))),
      child: Row(children: [
        Text('캘린더', style: TextStyle(fontSize: Typo.h2, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.5)),
        const Spacer(),
        if (_favoriteTeamIds.isNotEmpty) ...[
          Tooltip(
            message: '마이팀만 보기',
            child: _Btn32(
              bg: _myTeamOnly ? myColor.withValues(alpha: 0.12) : Colors.transparent,
              border: _myTeamOnly ? myColor.withValues(alpha: 0.5) : cs.line2,
              onTap: () => setState(() => _myTeamOnly = !_myTeamOnly),
              child: Icon(_myTeamOnly ? Icons.star_rounded : Icons.star_outline_rounded, size: 18,
                  color: _myTeamOnly ? myColor : cs.ink3),
            ),
          ),
          const SizedBox(width: 7),
        ],
        Tooltip(
          message: '일정·직관 기록 추가',
          child: _Btn32(
            border: cs.line2,
            onTap: () => _showAddMenu(_selectedDate ?? DateTime.now()),
            child: Icon(Icons.add, size: 18, color: cs.ink3),
          ),
        ),
        const SizedBox(width: 7),
        Tooltip(
          message: '마이페이지',
          child: _Btn32(
            border: cs.line2,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyPageScreen())),
            child: Icon(Icons.person_outline, size: 18, color: cs.ink3),
          ),
        ),
      ]),
    );
  }

  Widget _buildMonthNav(_C cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Tooltip(message: '이전 달', child: _NavBtn(icon: Icons.chevron_left, cs: cs, onTap: _prevMonth)),
        Text('${_focusedMonth.year}년 ${_focusedMonth.month}월',
            style: TextStyle(fontSize: Typo.title, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.3)),
        Tooltip(message: '다음 달', child: _NavBtn(icon: Icons.chevron_right, cs: cs, onTap: _nextMonth)),
      ]),
    );
  }

  Widget _buildVisitStatsBar(_C cs, Color myColor) {
    final dayVisits = _dayVisitResult;
    if (_isLoading || dayVisits.isEmpty) return const SizedBox.shrink();
    int wins = 0, losses = 0, draws = 0;
    for (final r in dayVisits.values) {
      if (r == 'win') {
        wins++;
      } else if (r == 'loss') {
        losses++;
      } else {
        draws++;
      }
    }
    final total = wins + losses + draws;
    final pct = total > 0 ? (wins / total * 100).toStringAsFixed(0) : '0';

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.paper, border: Border.all(color: cs.line),
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: cs.dark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 2, offset: const Offset(0, 1))],
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: myColor.withValues(alpha: cs.dark ? 0.22 : 0.10), borderRadius: BorderRadius.circular(Radii.sm)),
          child: Icon(Icons.stadium, size: 18, color: myColor),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('직관 승률', style: TextStyle(fontSize: Typo.body, fontWeight: Typo.bold, color: cs.ink)),
            const SizedBox(width: 6),
            Text('$pct%', style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra, color: myColor)),
          ]),
          const SizedBox(height: 5),
          Row(children: [
            _StatChip(label: '$wins승', color: const Color(0xFF2563EB)),
            const SizedBox(width: 5),
            _StatChip(label: '$losses패', color: SemColor.live),
            if (draws > 0) ...[
              const SizedBox(width: 5),
              _StatChip(label: '$draws무', color: cs.sub),
            ],
          ]),
        ])),
        Row(children: [
          GestureDetector(
            onTap: _showStadiumStats,
            child: _TextPill(label: '통계', color: cs.ink3, border: cs.line),
          ),
          const SizedBox(width: 5),
          GestureDetector(
            onTap: _showStadiumRanking,
            child: _TextPill(label: '랭킹', color: SemColor.live, border: SemColor.live.withValues(alpha: 0.25)),
          ),
        ]),
      ]),
    );
  }

  Widget _buildDowHeader(_C cs) {
    const days = ['일', '월', '화', '수', '목', '금', '토'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(children: List.generate(7, (i) => Expanded(
        child: Center(child: Text(days[i], style: TextStyle(
          fontSize: Typo.caption, fontWeight: Typo.medium,
          color: i == 0 ? SemColor.live : i == 6 ? const Color(0xFF2563EB) : cs.sub,
        ))),
      ))),
    );
  }

  Widget _buildCalendarShimmer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[700]! : Colors.grey[100]!;
    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Column(
        children: List.generate(5, (_) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
          child: Row(
            children: List.generate(7, (_) => Expanded(
              child: Container(
                height: 44,
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            )),
          ),
        )),
      ),
    );
  }

  Widget _buildCalendarGrid(_C cs, Color myColor) {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDay = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final startWeekday = firstDay.weekday % 7;
    final rows = ((startWeekday + lastDay.day) / 7).ceil();

    return Column(
      children: List.generate(rows, (row) {
        final weekDays = List.generate(7, (col) {
          final dayNum = row * 7 + col - startWeekday + 1;
          if (dayNum < 1 || dayNum > lastDay.day) return null;
          return DateTime(_focusedMonth.year, _focusedMonth.month, dayNum);
        });

        final validDays = weekDays.whereType<DateTime>().toList();
        if (validDays.isEmpty) return const SizedBox();
        final weekStart = validDays.first;
        final weekEnd = validDays.last;

        final weekEvents = _personalEvents.where((e) {
          try {
            final s = DateTime.parse(e['start_date'] ?? e['date'] ?? '');
            final en = DateTime.parse(e['end_date'] ?? e['start_date'] ?? e['date'] ?? '');
            return !s.isAfter(weekEnd) && !en.isBefore(weekStart);
          } catch (_) { return false; }
        }).toList();

        return Column(
          children: [
            ...weekEvents.take(2).map((e) => _buildEventBarRow(e, weekDays, cs)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: weekDays.asMap().entries.map((entry) {
                  final col = entry.key;
                  final day = entry.value;
                  if (day == null) return const Expanded(child: SizedBox(height: 46));
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedDate = day),
                      child: _buildDayCell(day, col, cs, myColor),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildDayCell(DateTime day, int col, _C cs, Color myColor) {
    final games = _gamesOn(day);
    final isSel = _selectedDate?.year == day.year &&
        _selectedDate?.month == day.month &&
        _selectedDate?.day == day.day;
    final now = DateTime.now();
    final isToday = now.year == day.year && now.month == day.month && now.day == day.day;
    final visitResult = _dayVisitResult[_dateKey(day)];

    final bg = isSel ? cs.ink
        : isToday ? myColor.withValues(alpha: cs.dark ? 0.25 : 0.12)
        : Colors.transparent;
    final border = visitResult != null && !isSel
        ? (visitResult == 'win'
            ? const Color(0xFF2563EB).withValues(alpha: 0.5)
            : visitResult == 'loss'
                ? SemColor.live.withValues(alpha: 0.45)
                : cs.line2)
        : Colors.transparent;
    final numColor = isSel ? (cs.dark ? const Color(0xFF0F0F12) : Colors.white)
        : isToday ? myColor
        : col == 0 ? SemColor.live
        : col == 6 ? const Color(0xFF2563EB)
        : cs.ink2;

    return Container(
      height: 46, margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('${day.day}', style: TextStyle(
          fontSize: Typo.caption,
          fontWeight: isSel || isToday ? Typo.extra : Typo.medium,
          color: numColor,
        )),
        if (games.isNotEmpty) ...[
          const SizedBox(height: 3),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(
            games.length > 3 ? 3 : games.length,
            (_) => Container(
              width: 4, height: 4, margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(shape: BoxShape.circle,
                color: isSel
                    ? (cs.dark ? const Color(0xFF0F0F12) : Colors.white).withValues(alpha: 0.65)
                    : cs.sub),
            ),
          )),
        ],
      ]),
    );
  }

  Widget _buildEventBarRow(Map event, List<DateTime?> weekDays, _C cs) {
    final startStr = event['start_date'] ?? event['date'] ?? '';
    final endStr = event['end_date'] ?? startStr;
    if (startStr.isEmpty) return const SizedBox(height: 18);
    DateTime eventStart, eventEnd;
    try {
      eventStart = DateTime.parse(startStr);
      eventEnd = DateTime.parse(endStr);
    } catch (_) { return const SizedBox(height: 18); }

    final color = _eventColor(event['color'] as String?);
    final title = event['title'] as String? ?? '';

    int firstIncludedCol = -1;
    for (int i = 0; i < weekDays.length; i++) {
      final d = weekDays[i];
      if (d != null && !d.isBefore(eventStart) && !d.isAfter(eventEnd)) {
        firstIncludedCol = i;
        break;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        height: 18,
        child: Row(
          children: weekDays.asMap().entries.map((entry) {
            final col = entry.key;
            final day = entry.value;
            final included = day != null && !day.isBefore(eventStart) && !day.isAfter(eventEnd);
            if (!included) return const Expanded(child: SizedBox());

            final isFirst = col == firstIncludedCol;
            final nextDay = col < 6 ? weekDays[col + 1] : null;
            final isLast = nextDay == null || nextDay.isAfter(eventEnd);

            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedDate = day),
                child: Container(
                  height: 14,
                  margin: EdgeInsets.only(top: 2, bottom: 2, left: isFirst ? 1 : 0, right: isLast ? 1 : 0),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: cs.dark ? 0.72 : 0.85),
                    borderRadius: BorderRadius.only(
                      topLeft: isFirst ? const Radius.circular(5) : Radius.zero,
                      bottomLeft: isFirst ? const Radius.circular(5) : Radius.zero,
                      topRight: isLast ? const Radius.circular(5) : Radius.zero,
                      bottomRight: isLast ? const Radius.circular(5) : Radius.zero,
                    ),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.only(left: isFirst ? 5 : 0),
                  child: isFirst
                      ? Text(title,
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                          overflow: TextOverflow.clip, softWrap: false)
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── 선택 날짜 상세 ──────────────────────────────────────────────────────────

  Widget _buildDayDetail(_C cs) {
    final selected = _selectedDate;
    if (selected == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 36, bottom: 28),
        child: Center(child: Text('날짜를 선택하세요', style: TextStyle(fontSize: Typo.body, color: cs.sub))),
      );
    }
    final games = _gamesOn(selected);
    final personal = _eventsOn(selected);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (games.isNotEmpty) ...[
          _SectionLabel(label: 'KBO 경기', cs: cs),
          const SizedBox(height: 10),
          ...games.map((g) => _buildGameTile(g as Map<String, dynamic>, cs)),
        ],
        if (personal.isNotEmpty) ...[
          const SizedBox(height: 14),
          _SectionLabel(label: '개인 일정', cs: cs),
          const SizedBox(height: 10),
          ...personal.map((e) => _buildPersonalEventTile(e, cs)),
        ],
        if (games.isEmpty && personal.isEmpty)
          Center(child: Padding(
            padding: const EdgeInsets.only(top: 36),
            child: Text('${selected.month}/${selected.day} 경기 및 일정 없음',
                style: TextStyle(fontSize: Typo.body, color: cs.sub)),
          )),
      ]),
    );
  }

  List<Map> _eventsOn(DateTime d) => _personalEvents.where((e) {
    try {
      final s = DateTime.parse(e['start_date'] ?? e['date'] ?? '');
      final en = DateTime.parse(e['end_date'] ?? e['start_date'] ?? e['date'] ?? '');
      return !d.isBefore(s) && !d.isAfter(en);
    } catch (_) { return false; }
  }).toList();

  // ── 게임 타일 ───────────────────────────────────────────────────────────────

  Widget _buildGameTile(Map<String, dynamic> game, _C cs) {
    final status = game['status'] as String? ?? '';
    final homeCode = game['home_team_code'] as String? ?? '';
    final awayCode = game['away_team_code'] as String? ?? '';
    final homeId = game['home_team_id'] as int?;
    final awayId = game['away_team_id'] as int?;
    final isLive = status == '진행';
    final isDone = status == '종료';
    final isCancel = status == '취소';
    final isUpcoming = status == '예정' || status == '라인업';

    String? mineCode;
    if (_favoriteTeamIds.contains(homeId)) {
      mineCode = homeCode;
    } else if (_favoriteTeamIds.contains(awayId)) {
      mineCode = awayCode;
    }
    final tc = mineCode != null ? teamColor(mineCode) : null;

    final winPitcher = game['win_pitcher'] as String?;
    final losePitcher = game['lose_pitcher'] as String?;
    final homeStarter = game['home_starter'] as String?;
    final awayStarter = game['away_starter'] as String?;
    final isDraw = game['is_draw'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: tc != null ? tc.withValues(alpha: cs.dark ? 0.12 : 0.06) : cs.paper,
        border: Border.all(color: tc != null ? tc.withValues(alpha: cs.dark ? 0.45 : 0.28) : cs.line),
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: tc == null && !cs.dark
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 2, offset: const Offset(0, 1))]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.lg),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => GameDetailScreen(gameId: game['id'] as int))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              // 헤더
              Row(children: [
                _Capsule(bg: cs.paper2, child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: cs.line2)),
                  const SizedBox(width: 5),
                  Text(game['stadium'] as String? ?? '',
                      style: TextStyle(fontSize: 10, fontWeight: Typo.medium, color: cs.ink3)),
                ])),
                const Spacer(),
                if (tc != null)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: tc, borderRadius: BorderRadius.circular(Radii.xs)),
                    child: const Text('마이팀', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                if (isUpcoming) ...[
                  Tooltip(
                    message: '내 캘린더에 추가',
                    child: GestureDetector(
                      onTap: () => _addToCalendar(game),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: Icon(Icons.calendar_today_outlined, size: 15, color: cs.ink3),
                      ),
                    ),
                  ),
                ],
                _StatusBadge(isLive: isLive, isDone: isDone, isCancel: isCancel,
                    time: game['start_time'] as String?, cs: cs),
              ]),
              const SizedBox(height: 12),
              // 팀 vs 스코어
              Row(children: [
                Expanded(child: _TeamCol(code: homeCode, name: game['home_team'] as String? ?? '', role: '홈', cs: cs)),
                SizedBox(width: 80, child: Center(child: isLive || isDone
                    ? Column(children: [
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('${game['home_score'] ?? 0}',
                              style: TextStyle(fontSize: 28, fontWeight: Typo.extra, color: cs.ink)),
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 9),
                            child: Text(':', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w300, color: cs.line2))),
                          Text('${game['away_score'] ?? 0}',
                              style: TextStyle(fontSize: 28, fontWeight: Typo.extra, color: cs.ink)),
                        ]),
                        if (isLive)
                          Text('${game['current_inning'] ?? ''}회 ${game['inning_half'] ?? ''}',
                              style: const TextStyle(fontSize: 10, fontWeight: Typo.bold, color: SemColor.live)),
                      ])
                    : Text(
                        isCancel ? '취소' : (game['start_time'] as String? ?? '예정'),
                        style: TextStyle(fontSize: 18, fontWeight: Typo.extra,
                            color: isCancel ? SemColor.live : cs.ink3)),
                )),
                Expanded(child: _TeamCol(code: awayCode, name: game['away_team'] as String? ?? '', role: '원정', cs: cs)),
              ]),
              // 투수
              if ((isDone && (winPitcher != null || losePitcher != null || isDraw)) ||
                  (isUpcoming && (homeStarter != null || awayStarter != null))) ...[
                const SizedBox(height: 12),
                Divider(height: 1, color: tc != null ? tc.withValues(alpha: 0.15) : cs.line),
                const SizedBox(height: 10),
                if (isDone && isDraw)
                  Center(child: Text('무승부', style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: cs.ink3)))
                else if (isDone)
                  Row(children: [
                    Expanded(child: Center(child: Text(
                        winPitcher != null ? '승 $winPitcher' : '',
                        style: const TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: SemColor.success)))),
                    Text('승·패', style: TextStyle(fontSize: 9, color: cs.sub)),
                    Expanded(child: Center(child: Text(
                        losePitcher != null ? '패 $losePitcher' : '',
                        style: const TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: SemColor.live)))),
                  ])
                else
                  Row(children: [
                    Expanded(child: Center(child: Text(homeStarter ?? '',
                        style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: cs.ink3)))),
                    Text('선발', style: TextStyle(fontSize: 9, color: cs.sub)),
                    Expanded(child: Center(child: Text(awayStarter ?? '',
                        style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: cs.ink3)))),
                  ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  // ── 개인 일정 ───────────────────────────────────────────────────────────────

  static const _eventColors = {
    'blue': Color(0xFF2563EB),
    'red': Color(0xFFC30452),
    'green': Color(0xFF16A34A),
    'orange': Color(0xFFD97706),
    'purple': Color(0xFF7C3AED),
    'gray': Color(0xFF0891B2),
  };

  Color _eventColor(String? colorKey) =>
      _eventColors[colorKey ?? 'blue'] ?? const Color(0xFF2563EB);

  Widget _buildPersonalEventTile(Map event, _C cs) {
    final title = event['title'] as String? ?? '';
    final description = event['description'] as String?;
    final id = event['id'] as int?;
    final color = _eventColor(event['color'] as String?);
    final startTime = event['start_time'] as String?;
    final endTime = event['end_time'] as String?;
    final timeLabel = startTime != null
        ? (endTime != null ? '$startTime – $endTime' : startTime)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.paper, border: Border.all(color: color.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: IntrinsicHeight(child: Row(children: [
        Container(
          width: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(Radii.md)),
          ),
        ),
        Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(children: [
              Flexible(child: Text(title,
                  style: TextStyle(fontSize: Typo.body, fontWeight: Typo.bold, color: cs.ink),
                  overflow: TextOverflow.ellipsis)),
              if (timeLabel != null) ...[
                const SizedBox(width: 6),
                Text(timeLabel, style: TextStyle(fontSize: 10, fontWeight: Typo.medium, color: color)),
              ],
            ]),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(description, style: TextStyle(fontSize: Typo.caption, color: cs.ink3, height: 1.4),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ]),
        )),
        if (id != null)
          IconButton(
            icon: Icon(Icons.close, size: 16, color: cs.sub),
            tooltip: '일정 삭제',
            onPressed: () => _confirmDeleteEvent(id),
            padding: EdgeInsets.zero,
          ),
        const SizedBox(width: 4),
      ])),
    );
  }

  Future<void> _confirmDeleteEvent(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('일정 삭제'),
        content: const Text('이 일정을 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ApiService.deleteCalendarEvent(id);
        await _loadPersonalEvents();
      } catch (_) {}
    }
  }

  // ── 추가 메뉴 / 직관 기록 ───────────────────────────────────────────────────

  Future<void> _showAddMenu(DateTime date) async {
    final selectedGames = _gamesByDate[_dateKey(date)] ?? [];
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: CircleAvatar(backgroundColor: SemColor.brand(context), child: const Icon(Icons.event, color: Colors.white, size: 20)),
              title: const Text('일정 추가', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${date.month}/${date.day} 개인 일정 등록'),
              onTap: () { Navigator.pop(context); _openAddEvent(date); },
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFE65100), child: Icon(Icons.stadium, color: Colors.white, size: 20)),
              title: const Text('직관 기록', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(selectedGames.isEmpty ? '이 날은 경기가 없습니다' : '${selectedGames.length}경기 중 선택'),
              enabled: selectedGames.isNotEmpty,
              onTap: selectedGames.isEmpty ? null : () {
                Navigator.pop(context);
                if (selectedGames.length == 1) {
                  _handleVisit(selectedGames[0] as Map, date);
                } else {
                  _showPickGameForVisit(date, selectedGames);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddEvent(DateTime date) async {
    final games = _gamesByDate[_dateKey(date)] ?? [];
    final created = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => CalEventAddScreen(date: date, gameCount: games.length)));
    if (created == true && mounted) await _loadPersonalEvents();
  }

  Future<void> _showPickGameForVisit(DateTime date, List games) async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('직관 기록할 경기 선택', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          ...games.map((g) {
            final gm = g as Map;
            final gameId = gm['id'] as int;
            final visited = _visitedGames.containsKey(gameId);
            return ListTile(
              leading: TeamLogo(teamCode: gm['home_team_code'] ?? '', size: 28),
              title: Text('${gm['home_team']} vs ${gm['away_team']}'),
              subtitle: Text(gm['start_time'] ?? ''),
              trailing: visited ? const Icon(Icons.check_circle, color: Colors.green, size: 18) : null,
              onTap: () {
                Navigator.pop(context);
                _handleVisit(gm, date);
              },
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // 직관 기록: 기존 기록 있으면 조회 다이얼로그, 없으면 추가 화면(VisitRecordScreen)
  Future<void> _handleVisit(Map game, DateTime date) async {
    final gameId = game['id'] as int;
    final existing = _visitedGames[gameId];
    if (existing != null) {
      await _showExistingVisitDialog(gameId, existing);
      return;
    }
    final result = await Navigator.push<Map>(context, MaterialPageRoute(
        builder: (_) => VisitRecordScreen(game: game, date: date)));
    if (result != null && mounted) {
      setState(() => _visitedGames[gameId] = result);
    }
  }

  Future<void> _showExistingVisitDialog(int gameId, Map existing) async {
    final imageUrl = existing['image_url'] as String?;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('직관 기록'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('결과: ${existing['result'] == 'win' ? '승리' : existing['result'] == 'loss' ? '패배' : '무승부'}'),
                if ((existing['memo'] as String?)?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('메모: ${existing['memo']}'),
                  ),
                if (imageUrl != null && imageUrl.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 140,
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('닫기'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('기록 삭제'),
            ),
          ],
        ),
      );
      if (ok == true && mounted) {
        try {
          await ApiService.deleteStadiumVisit(existing['id'] as int);
          if (mounted) setState(() => _visitedGames.remove(gameId));
        } catch (_) {}
      }
  }

  // ── 직관 통계/랭킹 시트 ─────────────────────────────────────────────────────

  Future<void> _showStadiumStats() async {
    Map<String, dynamic>? data;
    try {
      data = await ApiService.getStadiumStats();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final byStadium = (data['by_stadium'] as List? ?? []).cast<Map>();
    final byMonth = (data['by_month'] as List? ?? []).cast<Map>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (_, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 12),
                width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text('직관 통계', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (byStadium.isNotEmpty) ...[
              const Text('구장별', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal)),
              const SizedBox(height: 8),
              ...byStadium.map((s) {
                final total = s['total'] as int;
                final wins = s['wins'] as int;
                final losses = s['losses'] as int;
                final pct = total > 0 ? (wins / total * 100).toStringAsFixed(0) : '0';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(s['name'] as String, style: const TextStyle(fontSize: 13))),
                      Text('$wins승 $losses패', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(width: 8),
                      Container(
                        width: 44,
                        alignment: Alignment.centerRight,
                        child: Text('$pct%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: wins > losses ? Colors.blue : wins < losses ? Colors.red : Colors.grey,
                            )),
                      ),
                    ],
                  ),
                );
              }),
              const Divider(height: 24),
            ],
            if (byMonth.isNotEmpty) ...[
              const Text('월별', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal)),
              const SizedBox(height: 8),
              ...byMonth.map((m) {
                final wins = m['wins'] as int;
                final losses = m['losses'] as int;
                final total = m['total'] as int;
                final pct = total > 0 ? (wins / total * 100).toStringAsFixed(0) : '0';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Text('${m['year']}년 ${m['month']}월', style: const TextStyle(fontSize: 13)),
                      const Spacer(),
                      Text('$total회 ($wins승 $losses패)', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(width: 8),
                      Text('$pct%',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: wins > losses ? Colors.blue : wins < losses ? Colors.red : Colors.grey,
                          )),
                    ],
                  ),
                );
              }),
            ],
            if (byStadium.isEmpty && byMonth.isEmpty)
              const Center(child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('직관 기록이 없습니다', style: TextStyle(color: Colors.grey)),
              )),
          ],
        ),
      ),
    );
  }

  // 공용 위젯으로 추출 (widgets/stadium_ranking_sheet.dart) — 커뮤니티 탭과 공유
  Future<void> _showStadiumRanking() => StadiumRankingSheet.show(context);

  void _addToCalendar(Map<String, dynamic> game) {
    final homeTeam = game['home_team'] as String? ?? '';
    final awayTeam = game['away_team'] as String? ?? '';
    final stadium = game['stadium'] as String? ?? '';
    final startTimeStr = game['start_time'] as String? ?? '18:30';
    final selected = _selectedDate ?? DateTime.now();

    // 시작 시간 파싱 (HH:mm)
    final parts = startTimeStr.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 18 : 18;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 30 : 30;

    final start = DateTime(selected.year, selected.month, selected.day, hour, minute);
    final end = start.add(const Duration(hours: 3));

    final event = Event(
      title: '$awayTeam vs $homeTeam',
      description: 'KBO 2026 정규시즌\n경기장: $stadium',
      location: stadium,
      startDate: start,
      endDate: end,
      allDay: false,
    );
    Add2Calendar.addEvent2Cal(event);
  }
}

// ── 서브 위젯 ─────────────────────────────────────────────────────────────────

class _TeamCol extends StatelessWidget {
  final String code, name, role;
  final _C cs;
  const _TeamCol({required this.code, required this.name, required this.role, required this.cs});
  @override
  Widget build(BuildContext context) => Column(children: [
    TeamLogo(teamCode: code, size: 44),
    const SizedBox(height: 7),
    Text(name, style: TextStyle(fontSize: 14, fontWeight: Typo.extra, color: cs.ink),
        textAlign: TextAlign.center),
    const SizedBox(height: 3),
    Text(role, style: TextStyle(fontSize: 10, color: cs.sub)),
  ]);
}

class _StatusBadge extends StatelessWidget {
  final bool isLive, isDone, isCancel;
  final String? time;
  final _C cs;
  const _StatusBadge({required this.isLive, required this.isDone, required this.isCancel, this.time, required this.cs});
  @override
  Widget build(BuildContext context) {
    if (isLive) {
      return _Capsule(
        bg: SemColor.live.withValues(alpha: 0.1),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 5, height: 5, margin: const EdgeInsets.only(right: 5),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: SemColor.live)),
          const Text('LIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: SemColor.live)),
        ]),
      );
    }
    if (isCancel) {
      return _Capsule(
        bg: SemColor.live.withValues(alpha: 0.08),
        child: const Text('취소', style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: SemColor.live)),
      );
    }
    return _Capsule(
      bg: cs.paper2,
      child: Text(isDone ? '종료' : (time ?? '예정'),
        style: TextStyle(fontSize: 10, fontWeight: Typo.bold,
          color: isDone ? cs.ink3 : const Color(0xFF2563EB))),
    );
  }
}

class _Btn32 extends StatelessWidget {
  final Widget child;
  final Color border;
  final Color? bg;
  final VoidCallback onTap;
  const _Btn32({required this.child, required this.border, this.bg, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: bg ?? Colors.transparent, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: child,
    ),
  );
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final _C cs;
  final VoidCallback onTap;
  const _NavBtn({required this.icon, required this.cs, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 34, height: 34,
      decoration: BoxDecoration(border: Border.all(color: cs.line2), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: cs.ink3, size: 20),
    ),
  );
}

class _Capsule extends StatelessWidget {
  final Widget child;
  final Color bg;
  const _Capsule({required this.child, required this.bg});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.pill)),
    child: child,
  );
}

class _StatChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatChip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Radii.xs)),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: Typo.medium, color: color)),
  );
}

class _TextPill extends StatelessWidget {
  final String label;
  final Color color, border;
  const _TextPill({required this.label, required this.color, required this.border});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(Radii.pill),
      border: Border.all(color: border.withValues(alpha: 0.4)),
    ),
    child: Text(label, style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.medium, color: color)),
  );
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final _C cs;
  const _SectionLabel({required this.label, required this.cs});
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(label,
        style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub, letterSpacing: 0.8)),
  );
}

// ── 색상 컨텍스트 헬퍼 ────────────────────────────────────────────────────────

class _C {
  final Color bg, paper, paper2, ink, ink2, ink3, sub, line, line2, track;
  final bool dark;
  _C(BuildContext ctx)
    : dark   = Theme.of(ctx).brightness == Brightness.dark,
      bg     = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF0F0F12) : const Color(0xFFFAFAFB),
      paper  = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF18181C) : Colors.white,
      paper2 = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6),
      ink    = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFFF4F4F5) : const Color(0xFF111113),
      ink2   = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFFC9C9D1) : const Color(0xFF3F3F46),
      ink3   = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73),
      sub    = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2),
      line   = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0),
      line2  = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF33333A) : const Color(0xFFE0E0E4),
      track  = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF2C2C33) : const Color(0xFFE8E8EC);
}
