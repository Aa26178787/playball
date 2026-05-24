import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../api/api_service.dart';
import 'player_stats_section.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PlayerDetailScreen extends StatefulWidget {
  final int playerId;
  const PlayerDetailScreen({super.key, required this.playerId});

  @override
  State<PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends State<PlayerDetailScreen> {
  Map<String, dynamic>? _playerData;
  List<dynamic> _dailyStats = [];
  Map<String, dynamic>? _pitchStats;
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
      final playerData = results[0] as Map<String, dynamic>;
      setState(() {
        _playerData = playerData;
        final dailyData = results[1] as Map<String, dynamic>;
        _dailyStats = dailyData['daily'] ?? [];
        _isLoading = false;
      });
      // 투수면 구종 차트도 로드
      if (playerData['player_type'] == '투수') {
        try {
          final ps = await ApiService.getPlayerPitchStats(widget.playerId);
          if (mounted) setState(() => _pitchStats = ps);
        } catch (_) {}
      }
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
    final playerType = player['player_type'] as String? ?? '';
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
      floatingActionButton: FloatingActionButton.small(
        tooltip: '상대전적 조회',
        onPressed: () => _showMatchupSheet(player),
        child: const Icon(Icons.compare_arrows),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(player),
            _buildInfoCard(player),
            if (_dailyStats.isNotEmpty) _buildRecent5Games(player),
            if (_pitchStats != null) _buildPitchStatsCard(),
            if (_dailyStats.isNotEmpty) _buildTrendCard(player),
            PlayerStatsSection(
              statsList: (_playerData!['stats'] as List?) ?? [],
              playerType: playerType,
              useEng: _useEng,
              onToggleEng: () => setState(() => _useEng = !_useEng),
              position: _playerData!['position'] as String?,
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  void _showMatchupSheet(Map<String, dynamic> player) {
    final playerType = player['player_type'] as String? ?? '';
    final isBatter = playerType == '타자';
    final searchCtrl = TextEditingController();
    List<Map> results = [];
    Map<String, dynamic>? matchupData;
    bool searching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          Future<void> doSearch(String q) async {
            if (q.trim().isEmpty) return;
            setModal(() { searching = true; matchupData = null; });
            try {
              final data = await ApiService.searchPlayers(q.trim(),
                  playerType: isBatter ? '투수' : '타자');
              setModal(() {
                results = (data['players'] as List? ?? [])
                    .map((p) => Map<String, dynamic>.from(p as Map)).toList();
                searching = false;
              });
            } catch (_) {
              setModal(() => searching = false);
            }
          }

          Future<void> doMatchup(Map opponent) async {
            setModal(() { searching = true; matchupData = null; });
            try {
              final data = isBatter
                  ? await ApiService.getMatchupStats(widget.playerId, opponent['id'] as int)
                  : await ApiService.getMatchupStats(opponent['id'] as int, widget.playerId);
              setModal(() { matchupData = data; searching = false; results = []; });
            } catch (_) {
              setModal(() => searching = false);
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 16, right: 16, top: 16,
            ),
            child: SizedBox(
              height: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('상대전적 — ${player['name']} vs ${isBatter ? '투수' : '타자'}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: isBatter ? '투수 이름 검색' : '타자 이름 검색',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => doSearch(searchCtrl.text),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onSubmitted: doSearch,
                  ),
                  const SizedBox(height: 8),
                  if (searching)
                    const Expanded(child: Center(child: CircularProgressIndicator()))
                  else if (matchupData != null)
                    _buildMatchupResult(matchupData!, player['name'] as String)
                  else
                    Expanded(
                      child: ListView(
                        children: results.map((p) => ListTile(
                          title: Text(p['name'] ?? ''),
                          subtitle: Text('${p['team'] ?? ''} | ${p['position'] ?? ''}',
                              style: const TextStyle(fontSize: 12)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => doMatchup(p),
                        )).toList(),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMatchupResult(Map<String, dynamic> data, String thisName) {
    final batter = data['batter'] as Map;
    final pitcher = data['pitcher'] as Map;
    final games = data['games'] ?? 0;
    final ab = data['at_bats'] ?? 0;
    final h = data['hits'] ?? 0;
    final hr = data['home_runs'] ?? 0;
    final rbi = data['rbis'] ?? 0;
    final bb = data['walks'] ?? 0;
    final k = data['strikeouts'] ?? 0;
    final avg = (data['avg'] as num?)?.toStringAsFixed(3) ?? '.000';

    return Expanded(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('${batter['name']} vs ${pitcher['name']}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ),
          if (games == 0)
            const Expanded(child: Center(
              child: Text('상대전적 데이터가 없습니다', style: TextStyle(color: Colors.grey))))
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('$games경기 출전', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _statBox('타율', avg),
                        _statBox('타수', '$ab'),
                        _statBox('안타', '$h'),
                        _statBox('홈런', '$hr'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _statBox('타점', '$rbi'),
                        _statBox('볼넷', '$bb'),
                        _statBox('삼진', '$k'),
                        _statBox('출루율', ab > 0 ? ((h + bb) / (ab + bb)).toStringAsFixed(3) : '.000'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value) {
    return Column(children: [
      Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
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
            backgroundImage: player['profile_image'] != null ? CachedNetworkImageProvider(player['profile_image']) : null,
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
            return d['stat_type'] == 'hitter' && ((d['pa'] as num?) ?? 0) > 0;
          } else {
            final ip = (d['ip'] as num?)?.toDouble() ?? 0;
            return d['stat_type'] == 'pitcher' && ip > 0;
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
      double? val;
      if (isHitter) {
        val = (d['avg'] as num?)?.toDouble();
      } else {
        final ip = (d['ip'] as num?)?.toDouble() ?? 0;
        final er = (d['er'] as num?)?.toDouble() ?? 0;
        final realIp = _ipToDecimal(ip);
        val = realIp > 0 ? er * 9 / realIp : null;
      }
      if (val != null) {
        spots.add(FlSpot(i.toDouble(), val));
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
    final yMax = isHitter ? (maxVal + padding).clamp(0.0, 1.0) : maxVal + padding;

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
                        preventCurveOverShooting: true,
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

  String _formatIp(num? ip) {
    if (ip == null) return '-';
    final whole = ip.floor();
    final frac = ((ip - whole) * 10).round();
    if (frac == 0) return '$whole';
    if (frac == 1) return '$whole⅓';
    return '$whole⅔';
  }

  String _fmtDate(String? dateStr) {
    if (dateStr == null || dateStr.length < 10) return '-';
    final month = int.tryParse(dateStr.substring(5, 7)) ?? 0;
    final day = int.tryParse(dateStr.substring(8, 10)) ?? 0;
    return '$month월 ${day}일';
  }

  Widget _buildRecent5Games(Map<String, dynamic> player) {
    final isHitter = player['player_type'] == '타자';
    final filtered = _dailyStats
        .where((d) {
          if (isHitter) {
            return d['stat_type'] == 'hitter' && ((d['pa'] as num?) ?? 0) > 0;
          }
          return d['stat_type'] == 'pitcher' && ((d['ip'] as num?) ?? 0) > 0;
        })
        .toList();
    if (filtered.isEmpty) return const SizedBox.shrink();
    final recent = filtered.length > 5
        ? filtered.sublist(filtered.length - 5).reversed.toList()
        : filtered.reversed.toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        children: [
          isHitter ? _buildHitterSummary(recent) : _buildPitcherSummary(recent),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('최근 5경기'),
                  isHitter ? _buildHitterRows(recent) : _buildPitcherRows(recent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHitterSummary(List<dynamic> rows) {
    final totalAb = rows.fold<int>(0, (s, d) => s + ((d['ab'] as num?)?.toInt() ?? 0));
    final totalH  = rows.fold<int>(0, (s, d) => s + ((d['hits'] as num?)?.toInt() ?? 0));
    final totalHr = rows.fold<int>(0, (s, d) => s + ((d['home_runs'] as num?)?.toInt() ?? 0));
    final totalRbi = rows.fold<int>(0, (s, d) => s + ((d['rbi'] as num?)?.toInt() ?? 0));
    final totalBb  = rows.fold<int>(0, (s, d) => s + ((d['walks'] as num?)?.toInt() ?? 0));
    final totalHbp = rows.fold<int>(0, (s, d) => s + ((d['hbp'] as num?)?.toInt() ?? 0));
    final total2b  = rows.fold<int>(0, (s, d) => s + ((d['doubles'] as num?)?.toInt() ?? 0));
    final total3b  = rows.fold<int>(0, (s, d) => s + ((d['triples'] as num?)?.toInt() ?? 0));

    final avg = totalAb > 0 ? totalH / totalAb : 0.0;
    final tb  = totalH + total2b + 2 * total3b + 3 * totalHr;
    final slg = totalAb > 0 ? tb / totalAb : 0.0;
    final obpD = totalAb + totalBb + totalHbp;
    final obp  = obpD > 0 ? (totalH + totalBb + totalHbp) / obpD : 0.0;
    final ops  = obp + slg;

    return Card(
      color: const Color(0xFF1A237E).withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('최근 5경기 요약',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1A237E))),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _summaryBox('AVG', avg.toStringAsFixed(3)),
                _summaryBox('OPS', ops.toStringAsFixed(3)),
                _summaryBox('HR', '$totalHr'),
                _summaryBox('RBI', '$totalRbi'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPitcherSummary(List<dynamic> rows) {
    final totalEr = rows.fold<int>(0, (s, d) => s + ((d['er'] as num?)?.toInt() ?? 0));
    final totalH  = rows.fold<int>(0, (s, d) => s + ((d['h'] as num?)?.toInt() ?? 0));
    final totalBb = rows.fold<int>(0, (s, d) => s + ((d['bb'] as num?)?.toInt() ?? 0));
    final totalSo = rows.fold<int>(0, (s, d) => s + ((d['so'] as num?)?.toInt() ?? 0));
    final realIp  = rows.fold<double>(0.0, (s, d) => s + _ipToDecimal((d['ip'] as num?)?.toDouble() ?? 0));

    final era  = realIp > 0 ? totalEr * 9 / realIp : 0.0;
    final whip = realIp > 0 ? (totalH + totalBb) / realIp : 0.0;

    return Card(
      color: const Color(0xFF1A237E).withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('최근 5경기 요약',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1A237E))),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _summaryBox('ERA', era.toStringAsFixed(2)),
                _summaryBox('WHIP', whip.toStringAsFixed(2)),
                _summaryBox('K', '$totalSo'),
                _summaryBox('IP', _fmtRealIp(realIp)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _ipToDecimal(double ip) {
    final full = ip.floor();
    final thirds = ((ip - full) * 10).round();
    return full + thirds / 3.0;
  }

  String _fmtRealIp(double realIp) {
    final full = realIp.floor();
    final thirds = ((realIp - full) * 3).round().clamp(0, 2);
    return thirds == 0 ? '$full' : '$full.$thirds';
  }

  Widget _summaryBox(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildHitterRows(List<dynamic> rows) {
    final headers = ['날짜', '상대', '타수', '안타', 'HR', 'RBI', 'BB', 'OPS'];
    final cols = [72.0, 42.0, 32.0, 32.0, 28.0, 28.0, 28.0, 44.0];
    return Column(children: [
      _tableRow(headers, cols, isHeader: true),
      ...rows.map((d) {
        final ab  = (d['ab'] as num?)?.toInt() ?? 0;
        final h   = (d['hits'] as num?)?.toInt() ?? 0;
        final hr  = (d['home_runs'] as num?)?.toInt() ?? 0;
        final bb  = (d['walks'] as num?)?.toInt() ?? 0;
        final hbp = (d['hbp'] as num?)?.toInt() ?? 0;
        final d2b = (d['doubles'] as num?)?.toInt() ?? 0;
        final d3b = (d['triples'] as num?)?.toInt() ?? 0;
        final tb  = h + d2b + 2 * d3b + 3 * hr;
        final slg = ab > 0 ? tb / ab : 0.0;
        final obpD = ab + bb + hbp;
        final obp  = obpD > 0 ? (h + bb + hbp) / obpD : 0.0;
        final ops  = obp + slg;
        return _tableRow([
          _fmtDate(d['game_date'] as String?),
          d['opponent'] as String? ?? '-',
          '$ab',
          '$h',
          '$hr',
          '${(d['rbi'] as num?)?.toInt() ?? 0}',
          '$bb',
          ab > 0 ? ops.toStringAsFixed(3) : '-',
        ], cols);
      }),
    ]);
  }

  Widget _buildPitcherRows(List<dynamic> rows) {
    final headers = ['날짜', '상대', 'ERA', '이닝', '피안타', '실점', '볼넷', '삼진'];
    final cols = [72.0, 40.0, 42.0, 40.0, 36.0, 32.0, 32.0, 32.0];
    return Column(children: [
      _tableRow(headers, cols, isHeader: true),
      ...rows.map((d) {
        final ip = (d['ip'] as num?)?.toDouble() ?? 0;
        final er = (d['er'] as num?)?.toDouble() ?? 0;
        final realIp = _ipToDecimal(ip);
        final era = realIp > 0 ? (er * 9 / realIp).toStringAsFixed(2) : '-';
        return _tableRow([
          _fmtDate(d['game_date'] as String?),
          d['opponent'] as String? ?? '-',
          era,
          _formatIp(d['ip'] as num?),
          '${(d['h'] as num?)?.toInt() ?? 0}',
          '${(d['r'] as num?)?.toInt() ?? 0}',
          '${(d['bb'] as num?)?.toInt() ?? 0}',
          '${(d['so'] as num?)?.toInt() ?? 0}',
        ], cols);
      }),
    ]);
  }

  Widget _tableRow(List<String> cells, List<double> widths, {bool isHeader = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: List.generate(cells.length, (i) {
          final isFirst = i == 0;
          return SizedBox(
            width: widths[i],
            child: Text(
              cells[i],
              style: TextStyle(
                fontSize: isFirst ? 12 : 12,
                fontWeight: isHeader ? FontWeight.w700 : FontWeight.normal,
                color: isHeader ? const Color(0xFF1A237E) : null,
              ),
              textAlign: isFirst ? TextAlign.left : TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }),
      ),
    );
  }

  static const _pitchColors = {
    '직구': Color(0xFFE53935), '포심': Color(0xFFE53935), '패스트볼': Color(0xFFE53935),
    '투심': Color(0xFFFF7043), '싱커': Color(0xFFFF7043),
    '슬라이더': Color(0xFF1E88E5), '커터': Color(0xFF039BE5),
    '커브': Color(0xFF43A047), '너클커브': Color(0xFF66BB6A),
    '체인지업': Color(0xFF8E24AA), '스플리터': Color(0xFF6D4C41),
    '포크': Color(0xFF795548), '너클볼': Color(0xFFFF8F00),
  };

  Widget _buildPitchStatsCard() {
    final types = (_pitchStats?['pitch_types'] as List?) ?? [];
    final total = (_pitchStats?['total'] as num?)?.toInt() ?? 0;
    if (types.isEmpty || total == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _sectionLabel('구종 분포'),
                const Spacer(),
                Text('총 $total구', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ]),
              const SizedBox(height: 10),
              ...types.map((t) {
                final type = t['type'] as String? ?? '';
                final pct = (t['pct'] as num?)?.toDouble() ?? 0;
                final cnt = (t['count'] as num?)?.toInt() ?? 0;
                final color = _pitchColors[type] ?? Colors.grey;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(
                      width: 56,
                      child: Text(type, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      child: Stack(children: [
                        Container(height: 14, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4))),
                        FractionallySizedBox(
                          widthFactor: pct / 100,
                          child: Container(height: 14, decoration: BoxDecoration(color: color.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(4))),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 52,
                      child: Text('${pct.toStringAsFixed(1)}% ($cnt)',
                          style: const TextStyle(fontSize: 11), textAlign: TextAlign.right),
                    ),
                  ]),
                );
              }),
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
