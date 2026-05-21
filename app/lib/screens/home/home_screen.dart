import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/game.dart';
import '../../api/api_service.dart';
import '../../utils/team_theme.dart';
import '../game/game_detail_screen.dart';
import '../team/team_screen.dart';
import '../player/player_screen.dart';
import '../community/community_screen.dart';
import '../calendar/calendar_screen.dart';
import '../auth/login_screen.dart';

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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGames();
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
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await context.read<AuthProvider>().logout();
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
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

          // 경기 목록
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _games.isEmpty
                    ? const Center(child: Text('경기가 없습니다'))
                    : RefreshIndicator(
                        onRefresh: _loadGames,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _games.length,
                          itemBuilder: (context, index) {
                            final game = _games[index];
                            return GameCard(game: Game.fromJson(game));
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
class GameCard extends StatelessWidget {
  final Game game;

  const GameCard({super.key, required this.game});

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
                  Text(
                    game.stadium ?? '',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
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

              // 선발투수 표시 (예정/라인업)
              if ((game.status == '예정' || game.status == '라인업') &&
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
            ],
          ),
        ),
      ),
    );
  }
}