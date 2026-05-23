import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../api/api_service.dart';
import 'player_stats_section.dart';

class PlayerDetailScreen extends StatefulWidget {
  final int playerId;
  const PlayerDetailScreen({super.key, required this.playerId});

  @override
  State<PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends State<PlayerDetailScreen> {
  Map<String, dynamic>? _playerData;
  List<dynamic> _dailyStats = [];
  bool _isLoading = true;
  bool _useEng = false;
  bool _isFav = false;
  bool _favLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPlayer();
    _loadFavStatus();
  }

  Future<void> _loadFavStatus() async {
    try {
      final data = await ApiService.getFavoritePlayers();
      final players = data['players'] as List? ?? [];
      if (mounted) setState(() => _isFav = players.any((p) => p['id'] == widget.playerId));
    } catch (_) {}
  }

  Future<void> _toggleFav() async {
    setState(() => _favLoading = true);
    try {
      if (_isFav) {
        await ApiService.removeFavoritePlayer(widget.playerId);
      } else {
        await ApiService.addFavoritePlayer(widget.playerId);
      }
      if (mounted) setState(() => _isFav = !_isFav);
    } catch (_) {}
    if (mounted) setState(() => _favLoading = false);
  }

  Future<void> _loadPlayer() async {
    try {
      final results = await Future.wait([
        ApiService.getPlayerDetail(widget.playerId),
        ApiService.getPlayerDaily(widget.playerId, season: 2026),
      ]);
      setState(() {
        _playerData = results[0] as Map<String, dynamic>;
        final dailyData = results[1] as Map<String, dynamic>;
        _dailyStats = dailyData['daily'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      // daily 실패해도 기본 데이터라도 표시
      try {
        final data = await ApiService.getPlayerDetail(widget.playerId);
        setState(() { _playerData = data; _isLoading = false; });
      } catch (_) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_playerData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('선수 상세')),
        body: const Center(child: Text('선수 정보를 불러오지 못했습니다')),
      );
    }

    final player = _playerData!;
    return Scaffold(
      appBar: AppBar(
        title: Text(player['name'] ?? ''),
        actions: [
          _favLoading
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
                  icon: Icon(_isFav ? Icons.star : Icons.star_border, color: Colors.amber),
                  onPressed: _toggleFav,
                ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(player),
            _buildInfoCard(player),
            if (_dailyStats.isNotEmpty) _buildTrendCard(player),
            PlayerStatsSection(
              statsList: (_playerData!['stats'] as List?) ?? [],
              playerType: _playerData!['player_type'] as String? ?? '',
              useEng: _useEng,
              onToggleEng: () => setState(() => _useEng = !_useEng),
              position: _playerData!['position'] as String?,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildRosterBadge(Map<String, dynamic> status) {
    final type = status['change_type'] as String? ?? '';
    Color color;
    IconData icon;
    switch (type) {
      case '부상자명단':
        color = Colors.red;
        icon = Icons.local_hospital;
        break;
      case '등록말소':
        color = Colors.orange;
        icon = Icons.arrow_downward;
        break;
      case '임의탈퇴':
        color = Colors.grey;
        icon = Icons.person_off;
        break;
      default:
        return const SizedBox.shrink();
    }
    final reason = status['reason'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          reason.isNotEmpty ? '$type · $reason' : type,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
        ),
      ]),
    );
  }

  Widget _buildHeader(Map<String, dynamic> player) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFF1A237E),
      child: Row(
        children: [
          CircleAvatar(
            radius: 38,
            backgroundImage: player['profile_image'] != null ? NetworkImage(player['profile_image']) : null,
            child: player['profile_image'] == null ? const Icon(Icons.person, size: 38, color: Colors.white) : null,
            backgroundColor: const Color(0xFF283593),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(player['name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                Text(
                  '${player['team'] ?? ''} | ${(player['position'] != null && player['position'].toString().isNotEmpty) ? player['position'] : player['player_type'] ?? ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Text('#${player['number'] ?? '-'}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                if (player['roster_status'] != null)
                  _buildRosterBadge(player['roster_status']),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(Map<String, dynamic> player) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('기본 정보'),
              _infoRow('생년월일', player['birth_date'] ?? '-'),
              _infoRow('신장/체중', '${player['height'] ?? '-'}cm / ${player['weight'] ?? '-'}kg'),
              _infoRow('팀', player['team'] ?? '-'),
              _infoRow('투/타', '${player['throws'] ?? '-'} / ${player['bats'] ?? '-'}'),
            ],
          ),
        ),
      ),
    );
  }

  /// 시즌 트렌드 그래프 카드 (타자: 누적 타율, 투수: ERA)
  Widget _buildTrendCard(Map<String, dynamic> player) {
    final isHitter = player['player_type'] == '타자';

    // 최근 20게임만 사용, stat_type으로 필터
    final filtered = _dailyStats
        .where((d) {
          if (isHitter) {
            return d['stat_type'] == 'hitter' && d['avg'] != null;
          } else {
            return d['stat_type'] == 'pitcher' && d['era'] != null;
          }
        })
        .toList();

    final recent = filtered.length > 20
        ? filtered.sublist(filtered.length - 20)
        : filtered;

    if (recent.isEmpty) return const SizedBox.shrink();

    // 데이터 포인트 생성
    final spots = <FlSpot>[];
    final labels = <String>[];
    for (int i = 0; i < recent.length; i++) {
      final d = recent[i];
      final val = isHitter
          ? (d['avg'] as num?)?.toDouble()
          : (d['era'] as num?)?.toDouble();
      if (val != null) {
        spots.add(FlSpot(i.toDouble(), val));
        // 날짜 MM/DD 형식
        final dateStr = d['game_date'] as String? ?? '';
        if (dateStr.length >= 10) {
          labels.add('${dateStr.substring(5, 7)}/${dateStr.substring(8, 10)}');
        } else {
          labels.add('');
        }
      }
    }

    if (spots.isEmpty) return const SizedBox.shrink();

    final values = spots.map((s) => s.y).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final padding = isHitter ? 0.05 : 1.0;
    final yMin = (minVal - padding).clamp(0.0, double.infinity);
    final yMax = maxVal + padding;

    final chartColor = isHitter ? const Color(0xFF1A237E) : const Color(0xFFB71C1C);
    final chartLabel = isHitter ? '타율 (AVG)' : 'ERA';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _sectionLabel('시즌 트렌드'),
                  const Spacer(),
                  Text(chartLabel, style: TextStyle(fontSize: 11, color: chartColor, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 160,
                child: LineChart(
                  LineChartData(
                    minY: yMin,
                    maxY: yMax,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: Colors.grey.withOpacity(0.2),
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.withOpacity(0.4), width: 1),
                        left: BorderSide(color: Colors.grey.withOpacity(0.4), width: 1),
                      ),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 38,
                          getTitlesWidget: (value, meta) {
                            final text = isHitter
                                ? value.toStringAsFixed(3)
                                : value.toStringAsFixed(2);
                            return Text(text, style: TextStyle(fontSize: 9, color: Colors.grey[600]));
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          interval: recent.length <= 5 ? 1 : (recent.length / 4).ceilToDouble(),
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                labels[idx],
                                style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        curveSmoothness: 0.25,
                        color: chartColor,
                        barWidth: 2.5,
                        dotData: FlDotData(
                          show: spots.length <= 10,
                          getDotPainter: (spot, percent, barData, index) =>
                              FlDotCirclePainter(
                                radius: 3,
                                color: chartColor,
                                strokeWidth: 1.5,
                                strokeColor: Colors.white,
                              ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          color: chartColor.withOpacity(0.08),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => Colors.black87,
                        tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((spot) {
                            final idx = spot.x.toInt();
                            final label = idx < labels.length ? labels[idx] : '';
                            final valText = isHitter
                                ? spot.y.toStringAsFixed(3)
                                : spot.y.toStringAsFixed(2);
                            return LineTooltipItem(
                              '$label\n$valText',
                              const TextStyle(color: Colors.white, fontSize: 11),
                            );
                          }).toList();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A237E))),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
