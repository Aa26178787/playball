import 'package:flutter/material.dart';
import 'dart:async';
import '../../api/api_service.dart';

class GameDetailScreen extends StatefulWidget {
  final int gameId;

  const GameDetailScreen({super.key, required this.gameId});

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends State<GameDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _gameData;
  Map<String, dynamic>? _relayData;
  Map<String, dynamic>? _rosterData;
  Map<String, dynamic>? _previewData;
  Map<String, dynamic>? _recordDetailData;
  Map<String, dynamic>? _relayAllData;
  bool _isLoading = true;
  Timer? _refreshTimer;

  static const _pitchTypeMap = {
    'FAST': '직구', 'CURV': '커브', 'SLID': '슬라이더',
    'FORK': '포크', 'CHAN': '체인지업', 'TWOS': '투심',
    'CUTS': '커터', 'SINK': '싱커', 'KNUC': '너클볼',
    'CHUP': '체인지업', 'CUTT': '커터', 'SPLT': '스플리터',
    'SCRW': '스크루볼', 'PALM': '팜볼', 'SWEE': '스위퍼',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 0 && _relayAllData == null) {
        ApiService.getGameRelayAll(widget.gameId)
            .then((d) => setState(() => _relayAllData = d))
            .catchError((_) {});
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final gameData = await ApiService.getGameDetail(widget.gameId);
      setState(() {
        _gameData = gameData;
        _isLoading = false;
      });

      Future.wait([
        ApiService.getGameRoster(widget.gameId)
            .then((d) => setState(() => _rosterData = d))
            .catchError((_) {}),
        ApiService.getGamePreview(widget.gameId)
            .then((d) => setState(() => _previewData = d))
            .catchError((_) {}),
        ApiService.getGameRecordDetail(widget.gameId)
            .then((d) => setState(() => _recordDetailData = d))
            .catchError((_) {}),
        ApiService.getGameRelayAll(widget.gameId)
            .then((d) => setState(() => _relayAllData = d))
            .catchError((_) {}),
      ]);

      if (gameData['game']['status'] == '진행') {
        ApiService.getGameRelay(widget.gameId)
            .then((d) => setState(() => _relayData = d))
            .catchError((_) {});

        // 30초마다 자동 새로고침
        _refreshTimer?.cancel();
        _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
          if (mounted && _gameData?['game']['status'] == '진행') {
            _refreshLiveData();
          } else {
            _refreshTimer?.cancel();
          }
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshLiveData() async {
    try {
      final gameData = await ApiService.getGameDetail(widget.gameId);
      if (!mounted) return;
      setState(() => _gameData = gameData);

      if (gameData['game']['status'] == '진행') {
        ApiService.getGameRelay(widget.gameId)
            .then((d) { if (mounted) setState(() => _relayData = d); })
            .catchError((_) {});
        ApiService.getGameRelayAll(widget.gameId)
            .then((d) { if (mounted) setState(() => _relayAllData = d); })
            .catchError((_) {});
      } else {
        // 경기 종료 감지 시 타이머 취소 후 전체 데이터 새로고침
        _refreshTimer?.cancel();
        _loadData();
      }
    } catch (e) {
      // 에러 무시
    }
  }

  // 승리확률 헬퍼
  Map<String, dynamic>? _getWinRate() {
    if (_gameData?['game']['status'] == '진행' && _relayData != null) {
      final wr = _relayData!['win_rate'];
      if (wr != null && wr['homeTeamWinRate'] != null) return wr;
    }
    return _relayAllData?['win_rate'];
  }

  String _convertPosition(String? pos) {
    if (pos == null || pos.isEmpty) return '';
    const posMap = {
      '투': '투수', '포': '포수',
      '一': '1루수', '二': '2루수', '三': '3루수',
      '유': '유격수', '좌': '좌익수', '중': '중견수', '우': '우익수',
      '지': '지명타자', '주': '주자', '타': '대타',
      '二三': '2·3루수', '一二': '1·2루수', '二一': '2·1루수',
      '三二': '3·2루수', '一三': '1·3루수', '三유': '3루·유격',
      '유三': '유격·3루', '중좌': '중·좌익', '좌중': '좌·중견',
      '우중': '우·중견', '중우': '중·우익', '一유': '1루·유격',
      '유一': '유격·1루', '二유': '2루·유격', '유二': '유격·2루',
      '주一': '주자→1루', '주二': '주자→2루', '주三': '주자→3루',
      '주유': '주자→유격', '주좌': '주자→좌익', '주중': '주자→중견',
      '주우': '주자→우익', '주포': '주자→포수',
      '타포': '대타→포수', '타유': '대타→유격', '타一': '대타→1루',
      '타二': '대타→2루', '타三': '대타→3루', '타좌': '대타→좌익',
      '타중': '대타→중견', '타우': '대타→우익', '타지': '대타→지명',
    };
    return posMap[pos] ?? pos;
  }

  String? _speedToString(dynamic speed) {
    if (speed == null) return null;
    final s = speed.toString();
    if (s == '0' || s == 'null') return null;
    return s;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_gameData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('경기 상세')),
        body: const Center(child: Text('경기 정보를 불러오지 못했습니다')),
      );
    }

    final game = _gameData!['game'];
    final innings = _gameData!['innings'] as List;
    final pitchers = _gameData!['pitchers'] as List;
    final batters = _gameData!['batters'] as List;

    return Scaffold(
      appBar: AppBar(
        title: Text('${game['home_team']} vs ${game['away_team']}'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          tabs: const [
            Tab(text: '이닝'),
            Tab(text: '프리뷰'),
            Tab(text: '로스터'),
            Tab(text: '투수'),
            Tab(text: '타자'),
            Tab(text: '기록'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildScoreHeader(game),
          if (game['status'] == '진행' && _relayData != null)
            _buildLiveStatus(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildInningsTab(innings),
                _buildPreviewTab(),
                _buildRosterTab(),
                _buildPitchersTab(pitchers),
                _buildBattersTab(batters),
                _buildRecordDetailTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreHeader(Map<String, dynamic> game) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFF1A237E),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(game['home_team'],
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
              ),
              Text(
                game['status'] == '예정'
                    ? 'VS'
                    : '${game['home_score']} : ${game['away_score']}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: Text(game['away_team'],
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            game['status'] == '진행'
                ? '${game['current_inning']}회 ${game['inning_half'] ?? ''}'
                : game['status'],
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // 승리확률 제거 - 스코어보드 아래로 이동
  Widget _buildLiveStatus() {
    final state = _relayData!['current_state'];
    if (state == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.green.withOpacity(0.1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildCountWidget('S', state['strike'] ?? 0, 2, Colors.red),
          _buildCountWidget('B', state['ball'] ?? 0, 3, Colors.green),
          _buildCountWidget('O', state['out'] ?? 0, 2, Colors.orange),
          const SizedBox(width: 16),
          _buildBaseWidget(state),
        ],
      ),
    );
  }

  Widget _buildCountWidget(String label, int count, int max, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
        const SizedBox(height: 4),
        Row(
          children: List.generate(
              max,
              (i) => Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < count ? color : Colors.grey[700],
                    ),
                  )),
        ),
      ],
    );
  }

  Widget _buildBaseWidget(Map<String, dynamic> state) {
    return SizedBox(
      width: 50,
      height: 50,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(top: 0, left: 17, child: _baseBox(state['base2'] == true)),
          Positioned(right: 0, top: 17, child: _baseBox(state['base1'] == true)),
          Positioned(left: 0, top: 17, child: _baseBox(state['base3'] == true)),
        ],
      ),
    );
  }

  Widget _baseBox(bool occupied) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: occupied ? Colors.yellow : Colors.grey[700],
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildInningsTab(List innings) {
    final awayTeam = _gameData!['game']['away_team'] as String;
    final homeTeam = _gameData!['game']['home_team'] as String;
    final awayShort = awayTeam.length > 3 ? awayTeam.substring(0, 3) : awayTeam;
    final homeShort = homeTeam.length > 3 ? homeTeam.substring(0, 3) : homeTeam;

    final relays = _relayAllData?['relays'] as List? ?? [];

    final Map<int, List> grouped = {};
    for (final r in relays) {
      final inning = r['inning'] as int? ?? 0;
      grouped.putIfAbsent(inning, () => []).add(r);
    }
    final sortedInnings = grouped.keys.toList()..sort();

    List<Map<String, dynamic>> groupByBatter(List items) {
      final List<Map<String, dynamic>> result = [];
      String? currentBatter;
      List<dynamic> currentPitches = [];
      Map<String, dynamic>? currentResult;
      String? currentPitcher;
      List<dynamic> currentEvents = [];

      void flush() {
        if (currentBatter != null) {
          result.add({
            'batter': currentBatter,
            'pitcher': currentPitcher,
            'pitches': List.from(currentPitches),
            'result': currentResult,
            'events': List.from(currentEvents),
          });
        }
        currentPitches = [];
        currentResult = null;
        currentEvents = [];
      }

      for (final r in items) {
        final batterName = r['batter_name'] as String?;
        final rtype = r['type'] as int?;
        final pitcherName = r['pitcher_name'] as String?;

        if (rtype == 0) continue;

        if (rtype == 8) {
          if (batterName != null && batterName != currentBatter) {
            flush();
            currentBatter = batterName;
            currentPitcher = pitcherName;
          } else if (currentResult != null) {
            flush();
            currentPitcher = pitcherName;
          }
          continue;
        }

        if (batterName != null && batterName != currentBatter) {
          flush();
          currentBatter = batterName;
          currentPitcher = pitcherName;
        }

        if (rtype == 1) {
          final pitchNum = r['pitch_num'] as int?;
          final lastPitchNum = currentPitches.isNotEmpty
              ? (currentPitches.last['pitch_num'] as int? ?? 0)
              : 0;
          if (pitchNum != null && pitchNum <= lastPitchNum && currentPitches.isNotEmpty) {
            flush();
            currentPitcher = pitcherName;
          }
          currentPitches.add(r);
          if (pitcherName != null) currentPitcher = pitcherName;
        } else if (rtype == 13 || rtype == 23) {
          currentResult = r as Map<String, dynamic>;
        } else if (rtype != null && [2, 7, 14, 20, 21, 22, 24, 25, 30, 31].contains(rtype)) {
          currentEvents.add(r);
        }
      }
      flush();
      return result;
    }

    final winRate = _getWinRate();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (innings.isNotEmpty) ...[
            const Text('스코어보드',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, constraints) {
              const teamColWidth = 48.0;
              return Column(
                children: [
                  _buildScoreRow(
                    teamName: '팀',
                    cells: [...innings.map((i) => '${i['inning']}'), 'R', 'H', 'B', 'E'],
                    teamColWidth: teamColWidth,
                    isHeader: true,
                  ),
                  _buildScoreRow(
                    teamName: awayShort,
                    cells: [
                      ...innings.map((i) => '${i['away_runs']}'),
                      '${_gameData!['game']['away_score']}',
                      '${_gameData!['game']['away_hits'] ?? 0}',
                      '${_gameData!['game']['away_walks'] ?? 0}',
                      '${_gameData!['game']['away_errors'] ?? 0}',
                    ],
                    teamColWidth: teamColWidth,
                    boldCols: [innings.length],
                  ),
                  _buildScoreRow(
                    teamName: homeShort,
                    cells: [
                      ...innings.map((i) => '${i['home_runs']}'),
                      '${_gameData!['game']['home_score']}',
                      '${_gameData!['game']['home_hits'] ?? 0}',
                      '${_gameData!['game']['home_walks'] ?? 0}',
                      '${_gameData!['game']['home_errors'] ?? 0}',
                    ],
                    teamColWidth: teamColWidth,
                    boldCols: [innings.length],
                  ),
                ],
              );
            }),
            // 승리확률 - 진행 중/종료 모두 표시
            if (winRate != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            _gameData!['game']['home_team'],
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${winRate['homeTeamWinRate']}%',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A237E),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Column(
                      children: [
                        Icon(Icons.sports_baseball, size: 16, color: Colors.grey),
                        SizedBox(height: 2),
                        Text('승리확률', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            _gameData!['game']['away_team'],
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${winRate['awayTeamWinRate']}%',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A237E),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],

          if (_relayAllData == null)
            const Center(child: CircularProgressIndicator())
          else if (relays.isEmpty)
            const Center(child: Text('중계 데이터가 없습니다'))
          else ...[
            const Text('이닝별 중계',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ...sortedInnings.map((inningNum) {
              final items = grouped[inningNum]!;

              final topItems = items.where((r) {
                final h = r['inning_half']?.toString() ?? '0';
                return h == '0';
              }).toList();
              final botItems = items.where((r) {
                final h = r['inning_half']?.toString() ?? '0';
                return h == '1';
              }).toList();

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  initiallyExpanded: false,
                  title: Text('$inningNum회',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  children: [
                    if (topItems.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        color: Colors.blue.withOpacity(0.05),
                        child: Text('$inningNum회초 $awayTeam 공격',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[700])),
                      ),
                      ...groupByBatter(topItems).map((e) => _buildBatterRelayTile(e)),
                    ],
                    if (botItems.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        color: Colors.red.withOpacity(0.05),
                        child: Text('$inningNum회말 $homeTeam 공격',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.red[700])),
                      ),
                      ...groupByBatter(botItems).map((e) => _buildBatterRelayTile(e)),
                    ],
                  ],
                ),
              );
            }).toList(),
          ],
        ],
      ),
    );
  }

  Widget _buildBatterRelayTile(Map<String, dynamic> entry) {
    final batterName = entry['batter'] as String? ?? '';
    final pitcherName = entry['pitcher'] as String?;
    final pitches = entry['pitches'] as List? ?? [];
    final resultRelay = entry['result'] as Map<String, dynamic>?;
    final events = entry['events'] as List? ?? [];

    final resultTitle = resultRelay?['title'] as String? ?? '';
    final result = resultTitle.contains(' : ')
        ? resultTitle.split(' : ').sublist(1).join(' : ').trim()
        : resultTitle;

    Color resultColor = Colors.grey;
    if (result.contains('안타') || result.contains('홈런') || result.contains('출루'))
      resultColor = Colors.green;
    if (result.contains('아웃') || result.contains('삼진'))
      resultColor = Colors.red;
    if (result.contains('볼넷') || result.contains('몸에 맞는 볼'))
      resultColor = Colors.blue;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.15))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
            child: Row(
              children: [
                Text(batterName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                if (pitcherName != null) ...[
                  Text(' vs ',
                      style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                  Text(pitcherName,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
                const Spacer(),
                if (result.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: resultColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: resultColor.withOpacity(0.4)),
                    ),
                    child: Text(result,
                        style: TextStyle(
                            fontSize: 11,
                            color: resultColor,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),

          ...events.map((r) {
            final rtype = r['type'] as int?;
            final title = r['title'] as String? ?? '';

            IconData icon = Icons.info_outline;
            Color color = Colors.grey;

            if (rtype == 14 || rtype == 31) {
              icon = Icons.directions_run;
              color = Colors.orange;
            } else if (rtype == 2 || rtype == 20) {
              icon = Icons.swap_horiz;
              color = Colors.purple;
            } else if (rtype == 7 || rtype == 21) {
              icon = Icons.group;
              color = Colors.teal;
            } else if (rtype == 22) {
              icon = Icons.videocam;
              color = Colors.indigo;
            } else if (rtype == 23) {
              icon = Icons.warning_amber;
              color = Colors.amber;
            } else if (rtype == 24) {
              icon = Icons.swap_vert;
              color = Colors.blueGrey;
            } else if (rtype == 25) {
              icon = Icons.pause_circle_outline;
              color = Colors.red;
            }

            return Padding(
              padding: const EdgeInsets.only(left: 8, right: 8, bottom: 3),
              child: Row(
                children: [
                  Icon(icon, size: 13, color: color),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(title,
                        style: TextStyle(fontSize: 11, color: color),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            );
          }).toList(),

          ...pitches.map((r) {
            final pitchResult = r['pitch_result'] as String?;
            final speed = _speedToString(r['speed']);
            final stuff = r['stuff'] as String?;
            final pitchNum = r['pitch_num'];
            final title = r['title'] as String?;

            String pitchResultText = '';
            if (title != null) {
              final parts = title.split(' ');
              if (parts.length >= 2) pitchResultText = parts[1];
            }

            Color pitchColor = Colors.grey;
            if (pitchResult == 'S') pitchColor = Colors.red;
            if (pitchResult == 'T') pitchColor = Colors.red;
            if (pitchResult == 'B') pitchColor = Colors.green;
            if (pitchResult == 'F') pitchColor = Colors.orange;
            if (pitchResult == 'H') pitchColor = Colors.blue;
            if (pitchResult == 'X') pitchColor = Colors.blue;

            return Padding(
              padding: const EdgeInsets.only(left: 16, right: 8, bottom: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(pitchNum != null ? '${pitchNum}구' : '',
                        style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                  ),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: pitchColor.withOpacity(0.2),
                    ),
                    child: Center(
                      child: Text(pitchResult ?? '',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: pitchColor)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 48,
                    child: Text(pitchResultText,
                        style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  ),
                  if (stuff != null)
                    Text(stuff, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  if (speed != null)
                    Text('${speed}km/h',
                        style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                ],
              ),
            );
          }).toList(),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildScoreRow({
    required String teamName,
    required List<String> cells,
    required double teamColWidth,
    bool isHeader = false,
    List<int> boldCols = const [],
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isHeader ? const Color(0xFF1A237E) : Colors.transparent,
        border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.3))),
      ),
      child: Row(
        children: [
          Container(
            width: teamColWidth,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.grey.withOpacity(0.3))),
            ),
            child: Text(
              teamName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isHeader ? Colors.white : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...cells.asMap().entries.map((entry) {
            final idx = entry.key;
            final val = entry.value;
            final isBold = boldCols.contains(idx);
            return Expanded(
              child: Container(
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                      right: BorderSide(color: Colors.grey.withOpacity(0.2))),
                ),
                child: Text(
                  val,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        (isHeader || isBold) ? FontWeight.bold : FontWeight.normal,
                    color: isHeader
                        ? Colors.white
                        : isBold
                            ? const Color(0xFF1A237E)
                            : null,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPreviewTab() {
    if (_gameData!['game']['status'] == '예정') {
      return const Center(child: Text('경기 시작 후 확인할 수 있습니다'));
    }
    if (_previewData == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final homeTeam = _gameData!['game']['home_team'];
    final awayTeam = _gameData!['game']['away_team'];
    final homeStarter = _previewData!['home_starter'];
    final awayStarter = _previewData!['away_starter'];
    final homeTop = _previewData!['home_top_player'];
    final awayTop = _previewData!['away_top_player'];
    final seasonVs = _previewData!['season_vs'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (seasonVs != null) ...[
            _rosterSectionHeader('시즌 상대 전적'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A237E).withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1A237E).withOpacity(0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      Text(homeTeam, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        '${seasonVs['home_wins']}승 ${seasonVs['home_losses']}패 ${seasonVs['home_draws']}무',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                  const Text('VS',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Color(0xFF1A237E))),
                  Column(
                    children: [
                      Text(awayTeam, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        '${seasonVs['away_wins']}승 ${seasonVs['away_losses']}패 ${seasonVs['away_draws']}무',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          _rosterSectionHeader('선발 투수'),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildStarterCard(homeStarter, homeTeam)),
              const SizedBox(width: 8),
              Expanded(child: _buildStarterCard(awayStarter, awayTeam)),
            ],
          ),
          const SizedBox(height: 20),
          if (homeTop != null || awayTop != null) ...[
            _rosterSectionHeader('키 플레이어'),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildTopPlayerCard(homeTop, homeTeam)),
                const SizedBox(width: 8),
                Expanded(child: _buildTopPlayerCard(awayTop, awayTeam)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStarterCard(Map<String, dynamic>? starter, String teamName) {
    if (starter == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text('$teamName 선발 미정',
              style: TextStyle(color: Colors.grey[500])),
        ),
      );
    }

    final season = starter['season_stats'] as Map<String, dynamic>? ?? {};
    final vs = starter['vs_stats'] as Map<String, dynamic>? ?? {};
    final pitchKinds = starter['pitch_kinds'] as List? ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(teamName, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            const SizedBox(height: 4),
            Text(starter['name'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(starter['hit_type'] ?? '',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            const Divider(height: 16),
            Text('시즌 성적',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              children: [
                _statChip('ERA', '${season['era'] ?? '-'}'),
                _statChip('${season['wins'] ?? 0}승 ${season['losses'] ?? 0}패', ''),
                _statChip('이닝', season['innings'] ?? '-'),
                _statChip('K', '${season['kk'] ?? 0}'),
                _statChip('BB', '${season['bb'] ?? 0}'),
              ],
            ),
            if (vs['games'] != null && vs['games'] != '0') ...[
              const SizedBox(height: 8),
              Text('상대 성적',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600])),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                children: [
                  _statChip('ERA', '${vs['era'] ?? '-'}'),
                  _statChip('이닝', vs['innings'] ?? '-'),
                  _statChip('K', '${vs['kk'] ?? 0}'),
                ],
              ),
            ],
            if (pitchKinds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('구종 비율',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600])),
              const SizedBox(height: 4),
              ...pitchKinds.map((pk) {
                final typeName = _pitchTypeMap[pk['type']] ?? pk['type'] ?? '';
                final ratio = (pk['ratio'] as num?)?.toStringAsFixed(1) ?? '-';
                final speed = pk['speed'] ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 60,
                          child: Text(typeName, style: const TextStyle(fontSize: 11))),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: (pk['ratio'] as num? ?? 0) / 100,
                            backgroundColor: Colors.grey[200],
                            valueColor: const AlwaysStoppedAnimation(Color(0xFF1A237E)),
                            minHeight: 8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('$ratio% ${speed}km',
                          style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopPlayerCard(Map<String, dynamic>? top, String teamName) {
    if (top == null) return const SizedBox.shrink();

    final season = top['season_stats'] as Map<String, dynamic>? ?? {};
    final game = top['game_stats'] as Map<String, dynamic>? ?? {};
    final results = (game['result'] as String? ?? '')
        .split('|')
        .where((s) => s.isNotEmpty)
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(teamName, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            const SizedBox(height: 4),
            Text(top['name'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(height: 16),
            Text('시즌 성적',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              children: [
                _statChip('타율', '${season['avg'] ?? '-'}'),
                _statChip('홈런', '${season['hr'] ?? 0}'),
                _statChip('타점', '${season['rbi'] ?? 0}'),
                _statChip('출루율', '${season['obp'] ?? '-'}'),
              ],
            ),
            if (results.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('이번 경기',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600])),
              const SizedBox(height: 4),
              Text(
                '${game['ab'] ?? 0}타수 ${game['hit'] ?? 0}안타 ${game['hr'] ?? 0}홈런 ${game['rbi'] ?? 0}타점',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: results
                    .map((r) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: r.contains('안타')
                                ? Colors.green.withOpacity(0.15)
                                : r.contains('삼진')
                                    ? Colors.red.withOpacity(0.15)
                                    : Colors.grey.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(r,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: r.contains('안타')
                                      ? Colors.green
                                      : r.contains('삼진')
                                          ? Colors.red
                                          : Colors.grey[600])),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildRosterTab() {
    if (_rosterData == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final homeTeam = _gameData!['game']['home_team'];
    final awayTeam = _gameData!['game']['away_team'];

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(tabs: [Tab(text: homeTeam), Tab(text: awayTeam)]),
          Expanded(
            child: TabBarView(
              children: [
                _buildTeamRoster(_rosterData!['home']),
                _buildTeamRoster(_rosterData!['away']),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamRoster(Map<String, dynamic> teamData) {
    final batters = teamData['batters'] as List;
    final pitchers = teamData['pitchers'] as List;

    final starterBatters = batters
        .where((b) =>
            b['batting_order'] != null &&
            b['batting_order'] != 0 &&
            b['is_starter'] == true)
        .toList()
      ..sort((a, b) =>
          (a['batting_order'] as num).compareTo(b['batting_order'] as num).toInt());

    final backupBatters = batters
        .where((b) =>
            b['batting_order'] == null ||
            b['batting_order'] == 0 ||
            b['is_starter'] != true)
        .toList();

    final starterPitcher = pitchers.cast<Map<String, dynamic>>().firstWhere(
          (p) => p['is_starter'] == true,
          orElse: () => <String, dynamic>{},
        );

    final bullpen =
        pitchers.where((p) => p['is_starter'] != true && p['is_starter'] != null).toList();
    final Map<String, List> bullpenGroups = {
      '좌완투수': [], '우완투수': [], '우완사이드': [], '우완언더': [], '기타': [],
    };
    for (final p in bullpen) {
      final style = p['pitching_style'] ?? '';
      if (bullpenGroups.containsKey(style)) {
        bullpenGroups[style]!.add(p);
      } else {
        bullpenGroups['기타']!.add(p);
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _rosterSectionHeader('선발'),
        const SizedBox(height: 8),
        if (starterPitcher.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.05),
              border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
            ),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: starterPitcher['profile_image'] != null
                        ? NetworkImage(starterPitcher['profile_image'])
                        : null,
                    child: starterPitcher['profile_image'] == null
                        ? const Icon(Icons.person, size: 18)
                        : null,
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange.withOpacity(0.5)),
                    ),
                    child: const Text('선발',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.orange,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              title: Text(
                '${starterPitcher['name'] ?? ''} (#${starterPitcher['number'] ?? '-'})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: Text(
                starterPitcher['pitching_style'] ?? '투수',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ),
          ),
        ...starterBatters.map((b) => _starterBatterTile(b)),
        const SizedBox(height: 16),
        if (backupBatters.isNotEmpty) ...[
          _rosterSectionHeader('후보 야수'),
          const SizedBox(height: 8),
          ...backupBatters.map((b) => _backupPlayerTile(
                b['name'] ?? '',
                b['position'] ?? '',
                b['profile_image'],
                b['number'])),
          const SizedBox(height: 16),
        ],
        if (bullpen.isNotEmpty) ...[
          _rosterSectionHeader('불펜 투수'),
          const SizedBox(height: 8),
          ...bullpenGroups.entries
              .where((e) => e.value.isNotEmpty)
              .expand((e) => [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, top: 8, bottom: 4),
                      child: Text(e.key,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600])),
                    ),
                    ...e.value.map((p) => _backupPlayerTile(
                          p['name'] ?? '',
                          '',
                          p['profile_image'],
                          p['number'])),
                  ]),
        ],
      ],
    );
  }

  Widget _rosterSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF1A237E),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
    );
  }

  Widget _starterBatterTile(Map<String, dynamic> b) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: b['profile_image'] != null
                ? NetworkImage(b['profile_image'])
                : null,
            child: b['profile_image'] == null
                ? const Icon(Icons.person, size: 18)
                : null,
          ),
          const SizedBox(width: 6),
          CircleAvatar(
            radius: 12,
            backgroundColor: const Color(0xFF1A237E),
            child: Text('${(b['batting_order'] as num).toInt()}',
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      title: Text('${b['name'] ?? ''} (#${b['number'] ?? '-'})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(b['position'] ?? '',
          style: TextStyle(fontSize: 12, color: Colors.grey[500])),
    );
  }

  Widget _backupPlayerTile(
      String name, String subtitle, String? profileImage, dynamic number) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: CircleAvatar(
        radius: 18,
        backgroundImage: profileImage != null ? NetworkImage(profileImage) : null,
        child: profileImage == null ? const Icon(Icons.person, size: 18) : null,
      ),
      title: Text('$name (#${number ?? '-'})',
          style: const TextStyle(fontSize: 14)),
      subtitle: subtitle.isNotEmpty
          ? Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[500]))
          : null,
    );
  }

  Widget _buildPitchersTab(List pitchers) {
    if (pitchers.isEmpty) {
      return const Center(child: Text('투수 기록이 없습니다'));
    }

    final homePitchers = pitchers.where((p) => p['team_side'] == 'home').toList();
    final awayPitchers = pitchers.where((p) => p['team_side'] == 'away').toList();
    final winPitcher = pitchers.firstWhere((p) => p['result'] == '승', orElse: () => {});
    final losePitcher = pitchers.firstWhere((p) => p['result'] == '패', orElse: () => {});
    final savePitcher = pitchers.firstWhere((p) => p['result'] == '세이브', orElse: () => {});
    final homeTeam = _gameData!['game']['home_team'];
    final awayTeam = _gameData!['game']['away_team'];

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          if (winPitcher.isNotEmpty || losePitcher.isNotEmpty)
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A237E).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1A237E).withOpacity(0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (winPitcher.isNotEmpty)
                    _resultSummary('승', winPitcher['name'], Colors.blue),
                  if (losePitcher.isNotEmpty)
                    _resultSummary('패', losePitcher['name'], Colors.red),
                  if (savePitcher.isNotEmpty)
                    _resultSummary('세이브', savePitcher['name'], Colors.green),
                ],
              ),
            ),
          TabBar(tabs: [Tab(text: homeTeam), Tab(text: awayTeam)]),
          Expanded(
            child: TabBarView(
              children: [
                _buildPitcherList(homePitchers),
                _buildPitcherList(awayPitchers),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPitcherList(List pitchers) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: pitchers.map((p) => _pitcherTile(p)).toList(),
    );
  }

  Widget _resultSummary(String label, String name, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4),
        Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  String _formatInnings(dynamic innings) {
    if (innings == null) return '0';
    final double inn = (innings as num).toDouble();
    final int full = inn.toInt();
    final double frac = inn - full;
    if (frac < 0.05) return '$full';
    if (frac < 0.15) return '$full⅓';
    return '$full⅔';
  }

  Widget _pitcherTile(Map<String, dynamic> p) {
    final pitchCount = p['pitch_count'] ?? 0;
    final result = p['result'] ?? '';
    Color resultColor = Colors.grey;
    if (result == '승') resultColor = Colors.blue;
    if (result == '패') resultColor = Colors.red;
    if (result == '세이브') resultColor = Colors.green;
    if (result == '홀드') resultColor = Colors.orange;

    final profileImage = p['profile_image'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: CircleAvatar(
          radius: 20,
          backgroundImage: profileImage != null ? NetworkImage(profileImage) : null,
          child: profileImage == null ? const Icon(Icons.person, size: 20) : null,
        ),
        title: Row(
          children: [
            Text(p['name'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(width: 6),
            if (result.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: resultColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: resultColor.withOpacity(0.5)),
                ),
                child: Text(result,
                    style: TextStyle(
                        fontSize: 11,
                        color: resultColor,
                        fontWeight: FontWeight.bold)),
              ),
            if (pitchCount > 0) ...[
              const SizedBox(width: 6),
              Text('${pitchCount}구',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400])),
            ],
          ],
        ),
        subtitle: Text(
          '${_formatInnings(p['innings_pitched'])}이닝  자책 ${p['earned_runs']}  실점 ${p['runs_allowed'] ?? p['earned_runs']}  삼진 ${p['strikeouts']}  사사구 ${p['walks'] ?? 0}',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
      ),
    );
  }

  Widget _buildBattersTab(List batters) {
    if (batters.isEmpty) {
      return const Center(child: Text('타자 기록이 없습니다'));
    }

    final homeBatters = batters.where((b) => b['team_side'] == 'home').toList();
    final awayBatters = batters.where((b) => b['team_side'] == 'away').toList();
    final homeTeam = _gameData!['game']['home_team'];
    final awayTeam = _gameData!['game']['away_team'];

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(tabs: [Tab(text: homeTeam), Tab(text: awayTeam)]),
          Expanded(
            child: TabBarView(
              children: [
                _buildBatterList(homeBatters),
                _buildBatterList(awayBatters),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatterList(List batters) {
    final Map<int, List<Map<String, dynamic>>> grouped = {};
    for (final b in batters) {
      final order = b['batting_order'] as int? ?? 0;
      if (order == 0) continue;
      grouped.putIfAbsent(order, () => []).add(b as Map<String, dynamic>);
    }
    final sortedKeys = grouped.keys.toList()..sort();

    Map<String, String?> profileImages = {};
    if (_rosterData != null) {
      for (final side in ['home', 'away']) {
        final sideBatters = (_rosterData![side]['batters'] as List?) ?? [];
        for (final rb in sideBatters) {
          profileImages[rb['name']] = rb['profile_image'];
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: sortedKeys.expand((order) {
        final players = grouped[order]!;
        return players.asMap().entries.map((entry) {
          final i = entry.key;
          final b = entry.value;
          final isFirst = i == 0;
          final isLast = i == players.length - 1;
          final pos = _convertPosition(b['position']);
          final profileImage = profileImages[b['name']];

          return Container(
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.withOpacity(isLast ? 0.4 : 0.15),
                  width: isLast ? 1.5 : 0.5,
                ),
              ),
            ),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage:
                        profileImage != null ? NetworkImage(profileImage) : null,
                    child: profileImage == null
                        ? const Icon(Icons.person, size: 18)
                        : null,
                  ),
                  const SizedBox(width: 6),
                  isFirst
                      ? CircleAvatar(
                          radius: 12,
                          backgroundColor: const Color(0xFF1A237E),
                          child: Text('$order',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        )
                      : SizedBox(
                          width: 24,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.arrow_downward,
                                  size: 13, color: Colors.orange),
                              Text('교체',
                                  style: TextStyle(
                                      fontSize: 9, color: Colors.grey[500])),
                            ],
                          ),
                        ),
                ],
              ),
              title: Row(
                children: [
                  Text(b['name'] ?? '',
                      style: TextStyle(
                          fontWeight:
                              isFirst ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14)),
                  const SizedBox(width: 6),
                  if (pos.isNotEmpty)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(pos,
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[600])),
                    ),
                ],
              ),
              subtitle: Text(
                '${b['at_bats']}타수 ${b['hits']}안타 ${b['rbis']}타점 ${b['home_runs']}홈런',
                style: TextStyle(
                    fontSize: 11,
                    color: isFirst ? Colors.grey[500] : Colors.grey[600]),
              ),
              trailing: Text(
                (b['avg'] as num).toStringAsFixed(3),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isFirst ? null : Colors.grey[500]),
              ),
            ),
          );
        }).toList();
      }).toList(),
    );
  }

  Widget _buildRecordDetailTab() {
    if (_recordDetailData == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final keyStats = _recordDetailData!['key_stats'] as Map<String, dynamic>? ?? {};
    final teamPitching = _recordDetailData!['team_pitching'] as Map<String, dynamic>? ?? {};
    final etcRecords = _recordDetailData!['etc_records'] as List? ?? [];
    final homeTeam = _gameData!['game']['home_team'];
    final awayTeam = _gameData!['game']['away_team'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rosterSectionHeader('주요 기록'),
          const SizedBox(height: 12),
          Table(
            border: TableBorder.all(color: Colors.grey.withOpacity(0.3)),
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1.5),
              2: FlexColumnWidth(1.5),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFF1A237E)),
                children: [
                  _tableCell('항목', isHeader: true),
                  _tableCell(homeTeam, isHeader: true),
                  _tableCell(awayTeam, isHeader: true),
                ],
              ),
              _buildStatRow('삼진', keyStats['home']?['strikeouts'], keyStats['away']?['strikeouts']),
              _buildStatRow('안타', keyStats['home']?['hits'], keyStats['away']?['hits']),
              _buildStatRow('홈런', keyStats['home']?['home_runs'], keyStats['away']?['home_runs']),
              _buildStatRow('실책', keyStats['home']?['errors'], keyStats['away']?['errors']),
              _buildStatRow('도루', keyStats['home']?['stolen_bases'], keyStats['away']?['stolen_bases']),
            ],
          ),
          const SizedBox(height: 20),
          _rosterSectionHeader('팀 투구'),
          const SizedBox(height: 12),
          Table(
            border: TableBorder.all(color: Colors.grey.withOpacity(0.3)),
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1.5),
              2: FlexColumnWidth(1.5),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFF1A237E)),
                children: [
                  _tableCell('항목', isHeader: true),
                  _tableCell(homeTeam, isHeader: true),
                  _tableCell(awayTeam, isHeader: true),
                ],
              ),
              _buildStatRow('이닝', teamPitching['home']?['innings'], teamPitching['away']?['innings']),
              _buildStatRow('피안타', teamPitching['home']?['hits'], teamPitching['away']?['hits']),
              _buildStatRow('실점', teamPitching['home']?['runs'], teamPitching['away']?['runs']),
              _buildStatRow('자책', teamPitching['home']?['earned_runs'], teamPitching['away']?['earned_runs']),
              _buildStatRow('사사구', teamPitching['home']?['walks'], teamPitching['away']?['walks']),
              _buildStatRow('삼진', teamPitching['home']?['strikeouts'], teamPitching['away']?['strikeouts']),
              _buildStatRow('투구수', teamPitching['home']?['pitch_count'], teamPitching['away']?['pitch_count']),
            ],
          ),
          const SizedBox(height: 20),
          if (etcRecords.isNotEmpty) ...[
            _rosterSectionHeader('특이 기록'),
            const SizedBox(height: 12),
            ...etcRecords.map((e) {
              final type = e['type'] as String? ?? '';
              final desc = e['description'] as String? ?? '';
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A237E).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(type,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A237E))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(desc, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _tableCell(String text, {bool isHeader = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          color: isHeader ? Colors.white : null,
        ),
      ),
    );
  }

  TableRow _buildStatRow(String label, dynamic home, dynamic away) {
    return TableRow(children: [
      _tableCell(label),
      _tableCell('${home ?? '-'}'),
      _tableCell('${away ?? '-'}'),
    ]);
  }
}