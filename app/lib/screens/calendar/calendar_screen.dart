import 'package:flutter/material.dart';
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

  Widget _buildGameTile(Map<String, dynamic> game) {
    final status = game['status'] as String? ?? '';
    final homeTeam = game['home_team'] as String? ?? '';
    final awayTeam = game['away_team'] as String? ?? '';
    final homeCode = game['home_team_code'] as String? ?? '';
    final awayCode = game['away_team_code'] as String? ?? '';
    final homeScore = game['home_score'];
    final awayScore = game['away_score'];
    final startTime = game['start_time'] as String? ?? '';
    final id = game['id'] as int;

    Color statusColor;
    String statusLabel;
    switch (status) {
      case '진행':
        statusColor = Colors.green;
        statusLabel = '진행중';
        break;
      case '종료':
        statusColor = Colors.grey;
        statusLabel = '종료';
        break;
      case '취소':
        statusColor = Colors.red;
        statusLabel = '취소';
        break;
      default:
        statusColor = Colors.blue;
        statusLabel = startTime.isNotEmpty ? startTime : '예정';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => GameDetailScreen(gameId: id))),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              TeamLogo(teamCode: homeCode, size: 32),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$homeTeam vs $awayTeam',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    if (status == '종료' && homeScore != null)
                      Text('$homeScore : $awayScore',
                          style: const TextStyle(fontSize: 13, color: Colors.black87))
                    else
                      Text(startTime, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              TeamLogo(teamCode: awayCode, size: 32),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(statusLabel,
                    style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
