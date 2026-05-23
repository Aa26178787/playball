import 'package:flutter/material.dart';
import 'package:add_2_calendar/add_2_calendar.dart';
import '../../api/api_service.dart';
import '../../utils/team_theme.dart';
import '../game/game_detail_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedMonth = DateTime.now();
  Map<String, List> _gamesByDate = {};
  bool _isLoading = false;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _loadCalendar();
  }

  Future<void> _loadCalendar() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getCalendar(_focusedMonth.year, _focusedMonth.month);
      final raw = data['games'] as Map<String, dynamic>? ?? {};
      setState(() {
        _gamesByDate = raw.map((k, v) => MapEntry(k, v as List));
        _isLoading = false;
        // auto-select today if in month
        final today = DateTime.now();
        if (today.year == _focusedMonth.year && today.month == _focusedMonth.month) {
          _selectedDate = DateTime(today.year, today.month, today.day);
        } else {
          _selectedDate = null;
        }
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  void _prevMonth() {
    setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1));
    _loadCalendar();
  }

  void _nextMonth() {
    setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1));
    _loadCalendar();
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List _gamesOn(DateTime d) => _gamesByDate[_dateKey(d)] ?? [];

  @override
  Widget build(BuildContext context) {
    final selected = _selectedDate;
    final selectedGames = selected != null ? _gamesOn(selected) : <dynamic>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('캘린더', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
      ),
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

          // 달력 그리드
          _isLoading
              ? const Expanded(child: Center(child: CircularProgressIndicator()))
              : _buildCalendarGrid(),

          const Divider(height: 1),

          // 선택된 날짜 경기 목록
          Expanded(
            child: selected == null
                ? const Center(child: Text('날짜를 선택하세요', style: TextStyle(color: Colors.grey)))
                : selectedGames.isEmpty
                    ? Center(
                        child: Text(
                          '${selected.month}/${selected.day} 경기 없음',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: selectedGames.length,
                        itemBuilder: (context, i) => _buildGameTile(selectedGames[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDay = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final startWeekday = firstDay.weekday % 7; // Sun=0
    final totalCells = startWeekday + lastDay.day;
    final rows = (totalCells / 7).ceil();

    return Column(
      children: List.generate(rows, (row) {
        return Row(
          children: List.generate(7, (col) {
            final cellIdx = row * 7 + col;
            final dayNum = cellIdx - startWeekday + 1;
            if (dayNum < 1 || dayNum > lastDay.day) {
              return const Expanded(child: SizedBox(height: 52));
            }
            final day = DateTime(_focusedMonth.year, _focusedMonth.month, dayNum);
            final games = _gamesOn(day);
            final isSelected = _selectedDate != null &&
                _selectedDate!.year == day.year &&
                _selectedDate!.month == day.month &&
                _selectedDate!.day == day.day;
            final isToday = DateTime.now().year == day.year &&
                DateTime.now().month == day.month &&
                DateTime.now().day == day.day;

            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedDate = day),
                child: Container(
                  height: 52,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF1A237E)
                        : isToday
                            ? const Color(0xFFE8EAF6)
                            : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        '$dayNum',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? Colors.white
                              : col == 0
                                  ? Colors.red
                                  : col == 6
                                      ? Colors.blue
                                      : null,
                        ),
                      ),
                      if (games.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        _buildGameDots(games, isSelected),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
        );
      }),
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
                      color: statusColor.withOpacity(0.2),
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
                          child: const Icon(Icons.calendar_today, size: 18, color: Color(0xFF1A237E)),
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
                        Text('홈', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
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
                        Text('원정', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
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
                            color: Colors.grey.withOpacity(0.1),
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
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('승 $winPitcher',
                                    style: const TextStyle(fontSize: 11, color: Colors.blue)),
                              ),
                            if (losePitcher != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
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
                        const Text('vs', style: TextStyle(fontSize: 10, color: Colors.grey)),
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
}
