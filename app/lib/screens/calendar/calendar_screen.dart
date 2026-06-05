import 'dart:io';
import 'package:flutter/material.dart';
import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:shimmer/shimmer.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../api/api_service.dart';
import '../../utils/local_cache.dart';
import '../../utils/team_theme.dart';
import '../game/game_detail_screen.dart';
import '../mypage/my_page_screen.dart';

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
  bool _myTeamOnly = false;

  @override
  void initState() {
    super.initState();
    _loadCalendar();
    _loadPersonalEvents();
    _loadFavoriteTeams();
  }

  Future<void> _loadFavoriteTeams() async {
    final cached = await LocalCache.get('favorite_teams') as List?;
    if (cached != null && mounted) {
      setState(() => _favoriteTeamIds = Set.from(cached.map((t) => (t as Map)['id'] as int)));
    }
    try {
      final data = await ApiService.getFavoriteTeams();
      final teams = data['teams'] as List? ?? [];
      await LocalCache.set('favorite_teams', teams);
      if (mounted) setState(() => _favoriteTeamIds = Set.from(teams.map((t) => (t as Map)['id'] as int)));
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
      if (mounted) setState(() {
        _gamesByDate = raw.map((k, v) => MapEntry(k, v as List));
        _isLoading = false;
        _autoSelectToday();
      });
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

  Widget _buildVisitStatsBar() {
    final dayVisits = _dayVisitResult;
    if (dayVisits.isEmpty) return const SizedBox.shrink();
    int wins = 0, losses = 0, draws = 0;
    for (final r in dayVisits.values) {
      if (r == 'win') wins++;
      else if (r == 'loss') losses++;
      else draws++;
    }
    final total = wins + losses + draws;
    final pct = total > 0 ? (wins / total * 100).toStringAsFixed(0) : '0';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111113).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.stadium, size: 15, color: Color(0xFF111113)),
          const SizedBox(width: 6),
          Text('직관 승률',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF111113))),
          const SizedBox(width: 10),
          _visitStatChip('${wins}승', Colors.blue),
          const SizedBox(width: 4),
          _visitStatChip('${losses}패', Colors.red),
          if (draws > 0) ...[
            const SizedBox(width: 4),
            _visitStatChip('${draws}무', Colors.grey),
          ],
          const Spacer(),
          Text('$pct%',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: wins > losses ? Colors.blue : wins < losses ? Colors.red : Colors.grey)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _showStadiumStats,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('통계', style: TextStyle(fontSize: 11, color: Colors.teal, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _showStadiumRanking,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF111113).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('랭킹', style: TextStyle(fontSize: 11, color: Color(0xFF111113), fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

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

  Future<void> _showStadiumRanking() async {
    final data = await ApiService.getStadiumRanking(limit: 50);
    final ranking = data['ranking'] as List? ?? [];
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (_, sc) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.emoji_events, color: Color(0xFF111113), size: 18),
                  SizedBox(width: 6),
                  Text('직관승률 랭킹', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(width: 6),
                  Text('(최소 5회)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            const Divider(height: 1),
            ranking.isEmpty
                ? const Expanded(child: Center(child: Text('아직 랭킹 데이터가 없습니다', style: TextStyle(color: Colors.grey))))
                : Expanded(
                    child: ListView.builder(
                      controller: sc,
                      itemCount: ranking.length,
                      itemBuilder: (_, i) {
                        final r = ranking[i] as Map;
                        final rank = r['rank'] as int;
                        final winRate = ((r['win_rate'] as num) * 100).toStringAsFixed(1);
                        final medalColor = rank == 1
                            ? const Color(0xFFFFD700)
                            : rank == 2
                                ? const Color(0xFFC0C0C0)
                                : rank == 3
                                    ? const Color(0xFFCD7F32)
                                    : Colors.grey[600]!;
                        return ListTile(
                          dense: true,
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: rank <= 3 ? medalColor.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text('$rank',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: rank <= 3 ? medalColor : Colors.grey[600])),
                          ),
                          title: Text(r['nickname'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${r['wins']}승 ${r['losses']}패${(r['draws'] as int) > 0 ? ' ${r['draws']}무' : ''} · 총 ${r['total']}회',
                              style: const TextStyle(fontSize: 11)),
                          trailing: Text('$winRate%',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: rank <= 3 ? medalColor : const Color(0xFF111113))),
                        );
                      },
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _visitStatChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
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

  List<Map> _eventsOn(DateTime d) => _personalEvents.where((e) {
    try {
      final s = DateTime.parse(e['start_date'] ?? e['date'] ?? '');
      final en = DateTime.parse(e['end_date'] ?? e['start_date'] ?? e['date'] ?? '');
      return !d.isBefore(s) && !d.isAfter(en);
    } catch (_) { return false; }
  }).toList();

  @override
  Widget build(BuildContext context) {
    final selected = _selectedDate;
    final selectedGames = selected != null ? _gamesOn(selected) : <dynamic>[];

    final selectedPersonalEvents = selected != null ? _eventsOn(selected) : <dynamic>[];

    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text('캘린더', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF111113))),
        actions: [
          if (_favoriteTeamIds.isNotEmpty)
            IconButton(
              icon: Icon(_myTeamOnly ? Icons.star : Icons.star_border, color: _myTeamOnly ? const Color(0xFF111113) : null),
              tooltip: '마이팀만 보기',
              onPressed: () => setState(() => _myTeamOnly = !_myTeamOnly),
            ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: '마이페이지',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyPageScreen())),
          ),
        ],
      ),
      floatingActionButton: selected != null
          ? Padding(
              padding: EdgeInsets.only(
                bottom: (ApiService.myTeamData.value.isNotEmpty ? 142.0 : 90.0) + MediaQuery.of(context).viewPadding.bottom,
              ),
              child: FloatingActionButton(
                backgroundColor: const Color(0xFF111113),
                onPressed: () => _showAddMenu(selected),
                child: const Icon(Icons.add, color: Colors.white),
              ),
            )
          : null,
      body: Column(
        children: [
          // 월 헤더
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: _prevMonth),
                Text(
                  '${_focusedMonth.year}년 ${_focusedMonth.month}월',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: _nextMonth),
              ],
            ),
          ),

          // 요일 헤더
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: ['일', '월', '화', '수', '목', '금', '토'].map((d) => Expanded(
                child: Center(
                  child: Text(d,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: d == '일' ? Colors.red : d == '토' ? Colors.blue : Colors.grey[700],
                    ),
                  ),
                ),
              )).toList(),
            ),
          ),
          const SizedBox(height: 4),

          // 직관 승률 배너
          if (!_isLoading) _buildVisitStatsBar(),

          // 달력 그리드
          _isLoading ? _buildCalendarShimmer() : _buildCalendarGrid(),

          const Divider(height: 1),

          // 선택된 날짜 경기 + 개인 일정 목록
          Expanded(
            child: selected == null
                ? const Center(child: Text('날짜를 선택하세요', style: TextStyle(color: Colors.grey)))
                : (selectedGames.isEmpty && selectedPersonalEvents.isEmpty)
                    ? Center(
                        child: Text(
                          '${selected.month}/${selected.day} 일정 없음',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView(
                        padding: EdgeInsets.fromLTRB(12, 8, 12, ApiService.myTeamData.value.isNotEmpty ? 130.0 : 80.0),
                        children: [
                          if (selectedGames.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4, top: 4),
                              child: Text('KBO 경기',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600])),
                            ),
                            ...selectedGames.map((g) => _buildGameTile(g as Map<String, dynamic>)),
                          ],
                          if (selectedPersonalEvents.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4, top: 12),
                              child: Text('개인 일정',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600])),
                            ),
                            ...selectedPersonalEvents.map((e) => _buildPersonalEventTile(e as Map)),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
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
            ...weekEvents.take(2).map((e) => _buildEventBarRow(e, weekDays)),
            Row(
              children: weekDays.asMap().entries.map((entry) {
                final col = entry.key;
                final day = entry.value;
                if (day == null) return const Expanded(child: SizedBox(height: 46));
                final games = _gamesOn(day);
                final isSelected = _selectedDate?.year == day.year &&
                    _selectedDate?.month == day.month &&
                    _selectedDate?.day == day.day;
                final isToday = DateTime.now().year == day.year &&
                    DateTime.now().month == day.month &&
                    DateTime.now().day == day.day;
                final visitResult = _dayVisitResult[_dateKey(day)];
                final visitColor = visitResult == 'win' ? Colors.blue
                    : visitResult == 'loss' ? Colors.red
                    : visitResult == 'draw' ? Colors.grey
                    : null;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedDate = day),
                    child: Container(
                      height: 46,
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF111113) : isToday ? const Color(0xFFE8EAF6) : null,
                        borderRadius: BorderRadius.circular(8),
                        border: visitColor != null && !isSelected
                            ? Border.all(color: visitColor.withValues(alpha: 0.6), width: 1.5)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text('${day.day}', style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white
                                : col == 0 ? Colors.red
                                : col == 6 ? Colors.blue
                                : null,
                          )),
                          if (games.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            _buildGameDots(games, isSelected),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildEventBarRow(Map event, List<DateTime?> weekDays) {
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

    return SizedBox(
      height: 18,
      child: Row(
        children: weekDays.asMap().entries.map((entry) {
          final col = entry.key;
          final day = entry.value;
          final included = day != null && !day.isBefore(eventStart) && !day.isAfter(eventEnd);
          if (!included) return Expanded(child: Container(height: 14, margin: const EdgeInsets.symmetric(vertical: 2)));

          final isFirst = col == firstIncludedCol;
          final nextDay = col < 6 ? weekDays[col + 1] : null;
          final isLast = nextDay == null || nextDay.isAfter(eventEnd);

          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedDate = day),
              child: Container(
                height: 14,
                margin: EdgeInsets.fromLTRB(isFirst ? 2 : 0, 2, isLast ? 2 : 0, 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.only(
                    topLeft: isFirst ? const Radius.circular(4) : Radius.zero,
                    bottomLeft: isFirst ? const Radius.circular(4) : Radius.zero,
                    topRight: isLast ? const Radius.circular(4) : Radius.zero,
                    bottomRight: isLast ? const Radius.circular(4) : Radius.zero,
                  ),
                ),
                child: isFirst ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(title,
                    style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ) : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGameDots(List games, bool isSelected) {
    // show up to 3 team code dots
    final dots = games.take(3).toList();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: dots.map((g) {
        final code = g['home_team_code'] as String? ?? '';
        final color = isSelected ? Colors.white : (teamColor(code) ?? Colors.grey);
        return Container(
          width: 5,
          height: 5,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        );
      }).toList(),
    );
  }

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

  static const _eventColors = {
    'blue': Colors.blue,
    'red': Colors.red,
    'green': Colors.green,
    'orange': Colors.orange,
    'purple': Colors.purple,
    'gray': Colors.grey,
  };

  Color _eventColor(String? colorKey) =>
      _eventColors[colorKey ?? 'blue'] ?? Colors.blue;

  Widget _buildPersonalEventTile(Map event) {
    final title = event['title'] as String? ?? '';
    final description = event['description'] as String?;
    final colorKey = event['color'] as String? ?? 'blue';
    final id = event['id'] as int?;
    final color = _eventColor(colorKey);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: ListTile(
        leading: Container(
          width: 6,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: description != null && description.isNotEmpty
            ? Text(description, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        trailing: id != null
            ? IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                onPressed: () => _confirmDeleteEvent(id),
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
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
              leading: const CircleAvatar(backgroundColor: Color(0xFF111113), child: Icon(Icons.event, color: Colors.white, size: 20)),
              title: const Text('일정 추가', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${date.month}/${date.day} 개인 일정 등록'),
              onTap: () { Navigator.pop(context); _showAddEventDialog(date); },
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFE65100), child: Icon(Icons.stadium, color: Colors.white, size: 20)),
              title: const Text('직관 기록', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(selectedGames.isEmpty ? '이 날은 경기가 없습니다' : '${selectedGames.length}경기 중 선택'),
              enabled: selectedGames.isNotEmpty,
              onTap: selectedGames.isEmpty ? null : () {
                Navigator.pop(context);
                if (selectedGames.length == 1) {
                  final game = selectedGames[0] as Map;
                  _showVisitDialog(game['id'] as int, _visitedGames[game['id'] as int]);
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
                _showVisitDialog(gameId, _visitedGames[gameId]);
              },
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _showAddEventDialog(DateTime date) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AddEventDialog(
        initialDate: date,
        eventColors: _eventColors,
      ),
    );
    if (result != null && mounted) {
      try {
        final startDt = result['startDate'] as DateTime;
        final endDt = result['endDate'] as DateTime;
        await ApiService.createCalendarEvent(
          _dateKey(startDt),
          result['title'] as String,
          description: (result['desc'] as String).isEmpty ? null : result['desc'] as String,
          color: result['color'] as String,
          endDate: endDt.isAtSameMomentAs(startDt) ? null : _dateKey(endDt),
        );
        await _loadPersonalEvents();
      } catch (_) {}
    }
  }

  Widget _buildGameTile(Map<String, dynamic> game) {
    final status = game['status'] as String? ?? '';
    final homeTeam = game['home_team'] as String? ?? '';
    final awayTeam = game['away_team'] as String? ?? '';
    final homeCode = game['home_team_code'] as String? ?? '';
    final awayCode = game['away_team_code'] as String? ?? '';
    final homeScore = game['home_score'] as int? ?? 0;
    final awayScore = game['away_score'] as int? ?? 0;
    final startTime = game['start_time'] as String? ?? '';
    final stadium = game['stadium'] as String? ?? '';
    final winPitcher = game['win_pitcher'] as String?;
    final losePitcher = game['lose_pitcher'] as String?;
    final homeStarter = game['home_starter'] as String?;
    final awayStarter = game['away_starter'] as String?;
    final isDraw = game['is_draw'] == true;
    final id = game['id'] as int;

    Color statusColor;
    String statusLabel;
    switch (status) {
      case '진행':
        statusColor = Colors.green;
        statusLabel = '${game['current_inning'] ?? ''}회 ${game['inning_half'] ?? ''}';
        break;
      case '종료':
        statusColor = Colors.grey;
        statusLabel = '종료';
        break;
      case '취소':
        statusColor = Colors.red;
        statusLabel = '취소';
        break;
      case '라인업':
        statusColor = Colors.green;
        statusLabel = '라인업';
        break;
      default:
        statusColor = Colors.blue;
        statusLabel = '예정';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => GameDetailScreen(gameId: id))),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 상태 + 경기장 + 캘린더 추가 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  Row(
                    children: [
                      Text(stadium, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      if (status == '예정' || status == '라인업') ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _addToCalendar(game),
                          child: const Icon(Icons.calendar_today, size: 18, color: Color(0xFF111113)),
                        ),
                      ],
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
                        TeamLogo(teamCode: homeCode, size: 40),
                        const SizedBox(height: 4),
                        Text(homeTeam,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center),
                        Text('홈', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: (status == '예정' || status == '취소' || status == '라인업')
                        ? Text(
                            status == '취소' ? '취소' : startTime,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: status == '취소' ? Colors.red : null,
                            ),
                          )
                        : Text(
                            '$homeScore : $awayScore',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        TeamLogo(teamCode: awayCode, size: 40),
                        const SizedBox(height: 4),
                        Text(awayTeam,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center),
                        Text('원정', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                      ],
                    ),
                  ),
                ],
              ),

              // 승/패 투수 또는 무승부 (종료만)
              if (status == '종료' && (winPitcher != null || losePitcher != null || isDraw))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: isDraw
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('무승부',
                              style: TextStyle(fontSize: 11, color: Colors.grey)),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (winPitcher != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('승 $winPitcher',
                                    style: const TextStyle(fontSize: 11, color: Colors.blue)),
                              ),
                            if (losePitcher != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('패 $losePitcher',
                                    style: const TextStyle(fontSize: 11, color: Colors.red)),
                              ),
                          ],
                        ),
                ),

              // 선발투수 (예정/라인업)
              if ((status == '예정' || status == '라인업') &&
                  (homeStarter != null || awayStarter != null))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (homeStarter != null)
                        _starterChip(homeStarter, true),
                      if (homeStarter != null && awayStarter != null)
                        const Text('vs', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      if (awayStarter != null)
                        _starterChip(awayStarter, false),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showVisitDialog(int gameId, Map? existing) async {
    if (existing != null) {
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
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
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
      return;
    }

    // 새 직관 기록
    String selectedResult = 'win';
    final memoCtrl = TextEditingController();
    String? pickedImagePath;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('직관 기록 추가'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('경기 결과', style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _resultChip('win', '승리', Colors.blue, selectedResult, (v) => setS(() => selectedResult = v)),
                    _resultChip('loss', '패배', Colors.red, selectedResult, (v) => setS(() => selectedResult = v)),
                    _resultChip('draw', '무승부', Colors.grey, selectedResult, (v) => setS(() => selectedResult = v)),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: memoCtrl,
                  decoration: const InputDecoration(
                    labelText: '메모 (선택)',
                    hintText: '직관 후기 입력',
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () async {
                    final picker = ImagePicker();
                    final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                    if (xfile != null) setS(() => pickedImagePath = xfile.path);
                  },
                  child: Container(
                    width: double.infinity,
                    height: pickedImagePath != null ? 140 : 60,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: pickedImagePath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(File(pickedImagePath!), fit: BoxFit.cover),
                          )
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_photo_alternate_outlined, color: Colors.grey, size: 24),
                              SizedBox(height: 4),
                              Text('사진 추가 (선택)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('저장')),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      try {
        String? imageUrl;
        if (pickedImagePath != null) {
          try {
            imageUrl = await ApiService.uploadPostImage(pickedImagePath!);
          } catch (_) {}
        }
        final res = await ApiService.addStadiumVisit(
          gameId, selectedResult,
          memo: memoCtrl.text.trim().isEmpty ? null : memoCtrl.text.trim(),
          imageUrl: imageUrl,
        );
        setState(() {
          _visitedGames[gameId] = {
            'id': res['id'],
            'game_id': gameId,
            'result': selectedResult,
            'memo': memoCtrl.text.trim(),
            'image_url': imageUrl,
          };
        });
      } catch (_) {}
    }
    memoCtrl.dispose();
  }

  Widget _resultChip(String value, String label, Color color, String selected, void Function(String) onTap) {
    final isSelected = value == selected;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : Colors.transparent),
        ),
        child: Text(label,
            style: TextStyle(
                color: isSelected ? Colors.white : color,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
      ),
    );
  }

  Widget _starterChip(String name, bool isHome) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.indigo.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${isHome ? '홈' : '원정'} $name',
        style: const TextStyle(fontSize: 11, color: Colors.indigo),
      ),
    );
  }
}

class _AddEventDialog extends StatefulWidget {
  final DateTime initialDate;
  final Map<String, Color> eventColors;

  const _AddEventDialog({required this.initialDate, required this.eventColors});

  @override
  State<_AddEventDialog> createState() => _AddEventDialogState();
}

class _AddEventDialogState extends State<_AddEventDialog> {
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late DateTime _startDate;
  late DateTime _endDate;
  String _selectedColor = 'blue';

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    _startDate = widget.initialDate;
    _endDate = widget.initialDate;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} (${['월', '화', '수', '목', '금', '토', '일'][d.weekday - 1]})';

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    final firstDate = isStart ? DateTime(2020, 1, 1) : _startDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: DateTime(2030, 12, 31),
      locale: const Locale('ko', 'KR'),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      } else {
        _endDate = picked;
      }
    });
  }

  Widget _dateTile(String label, DateTime date, {required bool isStart}) {
    return InkWell(
      onTap: () => _pickDate(isStart: isStart),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_fmt(date),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool multiDay = !_startDate.isAtSameMomentAs(_endDate);
    return AlertDialog(
      title: const Text('일정 추가'),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 날짜 범위 영역
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _dateTile('시작', _startDate, isStart: true),
                  Divider(height: 1, color: Colors.grey.shade200),
                  _dateTile('종료', _endDate, isStart: false),
                ],
              ),
            ),
            if (multiDay)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  '${_endDate.difference(_startDate).inDays + 1}일간',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '제목 *',
                hintText: '일정 제목 입력',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: '메모 (선택)',
                hintText: '메모 입력',
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 14),
            const Text('색상', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: widget.eventColors.entries.map((e) {
                final isChosen = _selectedColor == e.key;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = e.key),
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: e.value,
                      shape: BoxShape.circle,
                      border: isChosen ? Border.all(color: Colors.black54, width: 2.5) : null,
                    ),
                    child: isChosen ? const Icon(Icons.check, color: Colors.white, size: 17) : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () {
            final title = _titleCtrl.text.trim();
            if (title.isEmpty) return;
            Navigator.pop(context, {
              'startDate': _startDate,
              'endDate': _endDate,
              'title': title,
              'desc': _descCtrl.text.trim(),
              'color': _selectedColor,
            });
          },
          child: const Text('추가'),
        ),
      ],
    );
  }
}
