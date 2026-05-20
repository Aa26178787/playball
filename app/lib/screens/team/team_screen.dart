import 'package:flutter/material.dart';
import '../../api/api_service.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  List _teams = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTeams();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('팀 순위')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTeams,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A237E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(width: 30, child: Text('순위', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                        Expanded(child: Text('팀', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                        SizedBox(width: 30, child: Text('G', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                        SizedBox(width: 30, child: Text('승', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                        SizedBox(width: 30, child: Text('패', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                        SizedBox(width: 30, child: Text('무', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                        SizedBox(width: 45, child: Text('승률', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                        SizedBox(width: 30, child: Text('게차', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                        SizedBox(width: 45, child: Text('연속', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._teams.map((team) => _buildTeamRow(team)),
                ],
              ),
            ),
    );
  }

  Widget _buildTeamRow(Map<String, dynamic> team) {
    final streak = team['streak'] as int? ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text('${team['rank'] ?? '-'}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Expanded(
            child: Text(team['name'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          SizedBox(width: 30, child: Text('${team['total_games'] ?? 0}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          SizedBox(width: 30, child: Text('${team['wins'] ?? 0}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          SizedBox(width: 30, child: Text('${team['losses'] ?? 0}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          SizedBox(width: 30, child: Text('${team['draws'] ?? 0}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          SizedBox(width: 45, child: Text((team['win_rate'] as num?)?.toStringAsFixed(3) ?? '-', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          SizedBox(width: 30, child: Text('${team['games_behind'] ?? '-'}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          SizedBox(
            width: 45,
            child: Text(
              _streakText(streak),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _streakColor(streak)),
            ),
          ),
        ],
      ),
    );
  }
}