import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../api/api_service.dart';
import '../../utils/local_cache.dart';
import '../../utils/team_theme.dart';
import '../../utils/app_theme.dart';
import 'pitch_location_chart.dart';
import '../player/player_detail_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

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
  int _relayRetryCount = 0;
  Map<String, dynamic>? _weatherData;
  Map<String, dynamic>? _pitchTypesData;
  List _highlights = [];
  bool _highlightsLoading = false;
  Map<String, String> _playerRosterStatus = {};
  Map<int, int> _rankMap = {};
  bool _isLoading = true;
  int _loadAttempt = 0;
  bool _isLoadingInFlight = false;
  bool _isRelayRefreshing = false;
  bool _scoringExpanded = true;
  bool _fieldPinned = false;
  List _sameDayGames = [];
  int _lineupSubIndex = 0;
  int _statsSubIndex = 0;
  Timer? _refreshTimer;
  final ScrollController _inningScrollController = ScrollController();

  static const _pitchColors = {
    '직구': Color(0xFFE53935),
    '포심': Color(0xFFE53935),
    '패스트볼': Color(0xFFE53935),
    '투심': Color(0xFFFF7043),
    '싱커': Color(0xFFFF7043),
    '슬라이더': Color(0xFF1E88E5),
    '커터': Color(0xFF039BE5),
    '커브': Color(0xFF43A047),
    '체인지업': Color(0xFF8E24AA),
    '스플리터': Color(0xFF6D4C41),
    '포크볼': Color(0xFF546E7A),
    '너클볼': Color(0xFF757575),
  };

  static Color _pitchColor(String type) {
    for (final entry in _pitchColors.entries) {
      if (type.contains(entry.key)) return entry.value;
    }
    return const Color(0xFF9E9E9E);
  }

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
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) setState(() {});
      if (_tabController.index == 0 && _relayAllData == null) {
        ApiService.getGameRelayAll(widget.gameId)
            .then((d) { if (mounted) setState(() => _relayAllData = d); })
            .catchError((_) { if (mounted && _relayAllData == null) _scheduleRelayRetry(); });
      }
      if (_tabController.index == 3 && _highlights.isEmpty && !_highlightsLoading) {
        _loadHighlights();
      }
    });

    // 메모리 캐시 → 첫 빌드부터 즉시 content (shimmer 없음)
    final mem = ApiService.getGameDetailMem(widget.gameId);
    if (mem != null) {
      _gameData = mem;
      _isLoading = false;
    }

    _loadData();
  }

  Future<void> _loadHighlights() async {
    if (_highlights.isEmpty) setState(() => _highlightsLoading = true);
    try {
      final data = await ApiService.getGameHighlights(widget.gameId);
      if (mounted) {
        setState(() { _highlights = data['highlights'] ?? []; _highlightsLoading = false; });
        if (_isPastGame(_gameData)) await LocalCache.set(_ck('highlights'), data);
      }
    } catch (_) {
      if (mounted) setState(() => _highlightsLoading = false);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    _inningScrollController.dispose();
    super.dispose();
  }

  void _scrollInningsToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_inningScrollController.hasClients) {
        _inningScrollController.animateTo(
          _inningScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _isPastGame(Map<String, dynamic>? gameData) =>
      gameData?['game']?['status'] == '종료' || gameData?['game']?['status'] == '취소';

  String _ck(String suffix) => 'game_${widget.gameId}_$suffix';

  Future<void> _loadData() async {
    if (_isLoadingInFlight) return;
    _isLoadingInFlight = true;
    try {
      await _loadDataInner();
    } finally {
      _isLoadingInFlight = false;
    }
  }

  Future<void> _loadDataInner() async {
    // Phase 1: 모든 캐시를 병렬로 읽기 (LIVE 포함 stale-while-revalidate)
    final cacheResults = await Future.wait([
      LocalCache.get(_ck('detail'), maxAgeSeconds: 86400),
      LocalCache.get(_ck('roster'), maxAgeSeconds: 86400),
      LocalCache.get(_ck('relay'), maxAgeSeconds: 86400),
      LocalCache.get(_ck('preview'), maxAgeSeconds: 86400),
      LocalCache.get(_ck('record'), maxAgeSeconds: 86400),
      LocalCache.get(_ck('highlights'), maxAgeSeconds: 3600),
      LocalCache.get(_ck('relay_state'), maxAgeSeconds: 86400),  // 필드뷰 stale
      LocalCache.get(_ck('weather'), maxAgeSeconds: 86400),
      LocalCache.get(_ck('pitch_types'), maxAgeSeconds: 86400),
      LocalCache.get('team_rankings'),
    ]);
    final cachedDetail     = cacheResults[0] as Map?;
    final cachedRoster     = cacheResults[1] as Map?;
    final cachedRelay      = cacheResults[2] as Map?;
    final cachedPreview    = cacheResults[3] as Map?;
    final cachedRecord     = cacheResults[4] as Map?;
    final cachedHL         = cacheResults[5] as Map?;
    final cachedRelayState = cacheResults[6] as Map?;
    final cachedWeather    = cacheResults[7] as Map?;
    final cachedPitchTypes = cacheResults[8] as Map?;
    final cachedRankings   = cacheResults[9] as List?;

    if (!mounted) return;
    setState(() {
      if (_gameData == null) {
        // 메모리 캐시 없을 때만 LocalCache로 세팅
        if (cachedDetail != null && cachedDetail['game']?['home_team_code'] != null) {
          _gameData = Map<String, dynamic>.from(cachedDetail);
          _isLoading = false;
        } else {
          _isLoading = true;
        }
      }
      if (cachedRoster     != null) _rosterData      = Map<String, dynamic>.from(cachedRoster);
      if (cachedRelay      != null) _relayAllData    = Map<String, dynamic>.from(cachedRelay);
      if (cachedPreview    != null) _previewData     = Map<String, dynamic>.from(cachedPreview);
      if (cachedRecord     != null) _recordDetailData= Map<String, dynamic>.from(cachedRecord);
      if (cachedHL         != null) _highlights      = cachedHL['highlights'] as List? ?? [];
      if (cachedRelayState != null) _relayData       = Map<String, dynamic>.from(cachedRelayState);
      if (cachedWeather    != null) _weatherData     = Map<String, dynamic>.from(cachedWeather);
      if (cachedPitchTypes != null) _pitchTypesData  = Map<String, dynamic>.from(cachedPitchTypes);
      if (cachedRankings   != null) _rankMap = {for (final r in cachedRankings) (r['id'] as int): (r['rank'] as int? ?? 0)};
    });
    ApiService.getTeamRankings().then((data) {
      final list = data['rankings'] as List? ?? [];
      if (mounted) setState(() => _rankMap = {for (final r in list) (r['id'] as int): (r['rank'] as int? ?? 0)});
      LocalCache.set('team_rankings', list);
    }).catchError((_) {});

    // Phase 2: fetch from API
    try {
      final gameData = await ApiService.getGameDetail(widget.gameId);
      ApiService.setGameDetailMem(widget.gameId, gameData);
      if (!mounted) return;
      setState(() { _gameData = gameData; _isLoading = false; });

      // LIVE 게임 포함 항상 캐시 — 다음 진입 시 stale-while-revalidate
      await LocalCache.set(_ck('detail'), gameData);
      final isPast = _isPastGame(gameData);

      // 같은 날 경기 목록 (미니 카드용)
      final dateStr = gameData['game']['game_date'] as String?;
      if (dateStr != null) {
        ApiService.getGamesByDate(dateStr).then((d) {
          final games = d['games'] as List? ?? [];
          if (mounted) setState(() => _sameDayGames = games.where((g) => g['id'] != widget.gameId).toList());
        }).catchError((_) {});
      }

      Future.wait([
        ApiService.getGameRoster(widget.gameId)
            .then((d) async {
              if (!mounted) return;
              setState(() { _rosterData = d; });
              await LocalCache.set(_ck('roster'), d);
              try {
                final homeId = gameData['game']['home_team_id'] as int?;
                final awayId = gameData['game']['away_team_id'] as int?;
                final teamIds = [homeId, awayId].whereType<int>().toList();
                final changesList = await Future.wait(teamIds.map((id) =>
                    ApiService.getTeamRosterChanges(id, days: 60)
                        .catchError((_) => <String, dynamic>{})));
                final statusMap = <String, String>{};
                for (final changes in changesList) {
                  for (final c in (changes['changes'] as List? ?? [])) {
                    final name = c['player_name'] as String? ?? '';
                    final type = c['change_type'] as String? ?? '';
                    if (name.isNotEmpty && !statusMap.containsKey(name)) statusMap[name] = type;
                  }
                }
                if (mounted) setState(() => _playerRosterStatus = statusMap);
              } catch (_) {}
            })
            .catchError((_) {}),
        ApiService.getGamePreview(widget.gameId)
            .then((d) async {
              if (mounted) setState(() => _previewData = d);
              await LocalCache.set(_ck('preview'), d);
            })
            .catchError((_) {}),
        ApiService.getGameRecordDetail(widget.gameId)
            .then((d) async {
              if (mounted) setState(() => _recordDetailData = d);
              await LocalCache.set(_ck('record'), d);
            })
            .catchError((_) {}),
        ApiService.getGameRelayAll(widget.gameId)
            .then((d) async {
              if (!mounted) return;
              setState(() { _relayAllData = d; _relayRetryCount = 0; });
              if (_tabController.index == 0) _scrollInningsToBottom();
              await LocalCache.set(_ck('relay'), d);
            })
            .catchError((_) { if (mounted && _relayAllData == null) _scheduleRelayRetry(); }),
        ApiService.getGameWeather(widget.gameId)
            .then((w) async {
              if (mounted) setState(() => _weatherData = w);
              if (w != null) await LocalCache.set(_ck('weather'), w);
            })
            .catchError((_) {}),
        ApiService.getGamePitchTypes(widget.gameId)
            .then((d) async {
              if (mounted) setState(() => _pitchTypesData = d);
              await LocalCache.set(_ck('pitch_types'), d);
            })
            .catchError((_) {}),
      ]);

      if (gameData['game']['status'] == '진행') {
        ApiService.getGameRelay(widget.gameId)
            .then((d) async {
              if (mounted) setState(() => _relayData = d);
              await LocalCache.set(_ck('relay_state'), d);
            })
            .catchError((_) {});

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
      if (!mounted) return;
      if (_loadAttempt < 2) {
        _loadAttempt++;
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) _loadData();
        });
        // keep _isLoading = true → shimmer stays visible
      } else {
        setState(() => _isLoading = false);
      }
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
            .then((d) {
              if (mounted) {
                setState(() { _relayAllData = d; _relayRetryCount = 0; });
                if (_tabController.index == 0) _scrollInningsToBottom();
              }
            })
            .catchError((_) { if (mounted && _relayAllData == null) _scheduleRelayRetry(); });
      } else {
        // 경기 종료 감지 시 타이머 취소 후 전체 데이터 새로고침
        _refreshTimer?.cancel();
        _loadData();
      }
    } catch (e) {
      // 에러 무시
    }
  }

  Future<void> _refreshRelayAll() async {
    if (_isRelayRefreshing) return;
    setState(() => _isRelayRefreshing = true);
    try {
      final gameData = await ApiService.getGameDetail(widget.gameId);
      final relayAll = await ApiService.getGameRelayAll(widget.gameId);
      if (!mounted) return;
      setState(() {
        _gameData = gameData;
        _relayAllData = relayAll;
      });
      if (gameData['game']['status'] == '진행') {
        ApiService.getGameRelay(widget.gameId)
            .then((d) { if (mounted) setState(() => _relayData = d); })
            .catchError((_) {});
      }
      _scrollInningsToBottom();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isRelayRefreshing = false);
    }
  }

  void _scheduleRelayRetry() {
    if (_relayRetryCount >= 3) return;
    _relayRetryCount++;
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted || _relayAllData != null) return;
      ApiService.getGameRelayAll(widget.gameId)
          .then((d) {
            if (mounted) setState(() { _relayAllData = d; _relayRetryCount = 0; });
          })
          .catchError((_) { if (mounted && _relayAllData == null) _scheduleRelayRetry(); });
    });
  }

  Widget _buildRelayShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Column(
        children: List.generate(5, (i) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
        )),
      ),
    );
  }

  // 승리확률 그래프
  Widget _buildWinRateChart(String homeTeam, String awayTeam) {
    final relays = _relayAllData?['relays'] as List? ?? [];
    final pts = relays.where((r) {
      final wr = r['home_win_rate'];
      return wr != null && (wr as num) > 0 && (wr as num) < 100;
    }).toList();

    if (pts.isEmpty) {
      final wr = _getWinRate();
      if (wr == null) return const SizedBox.shrink();
      final home = (wr['homeTeamWinRate'] as num?)?.toDouble() ?? 50;
      final away = (wr['awayTeamWinRate'] as num?)?.toDouble() ?? 50;
      return _buildWinRateStatic(home, away, homeTeam, awayTeam);
    }

    // downsample to max 80 points
    final step = pts.length > 80 ? (pts.length / 80).ceil() : 1;
    final sampled = <dynamic>[];
    for (int i = 0; i < pts.length; i += step) sampled.add(pts[i]);
    if (sampled.last != pts.last) sampled.add(pts.last);

    final spots = <FlSpot>[];
    for (int i = 0; i < sampled.length; i++) {
      final wr = (sampled[i]['home_win_rate'] as num).toDouble();
      spots.add(FlSpot(i.toDouble(), wr));
    }

    final lastWr = spots.last.y;
    final homeColor = const Color(0xFF111113);
    final awayColor = const Color(0xFFC62828);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(children: [
          const Text('승리확률 추이', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const Spacer(),
          Container(width: 10, height: 10, color: homeColor),
          const SizedBox(width: 4),
          Text(homeTeam, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 8),
          Container(width: 10, height: 10, color: awayColor),
          const SizedBox(width: 4),
          Text(awayTeam, style: const TextStyle(fontSize: 11)),
        ]),
        const SizedBox(height: 4),
        SizedBox(
          height: 120,
          child: LineChart(LineChartData(
            minY: 0,
            maxY: 100,
            gridData: FlGridData(
              show: true,
              drawHorizontalLine: true,
              horizontalInterval: 25,
              getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFFE0E0E0), strokeWidth: 1),
              drawVerticalLine: false,
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 25,
                getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              )),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            extraLinesData: ExtraLinesData(horizontalLines: [
              HorizontalLine(y: 50, color: Color(0xFFE0E0E4), strokeWidth: 1,
                dashArray: [4, 4]),
            ]),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: homeColor,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [homeColor.withOpacity(0.25), homeColor.withOpacity(0.0)],
                  ),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                  '홈 ${s.y.toStringAsFixed(1)}%',
                  const TextStyle(fontSize: 11, color: Colors.white),
                )).toList(),
              ),
            ),
          )),
        ),
        // 현재 승률 표시
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(homeTeam, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('${lastWr.toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: homeColor)),
              const Text(' : ', style: TextStyle(fontSize: 14, color: Colors.grey)),
              Text('${(100 - lastWr).toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: awayColor)),
              const SizedBox(width: 8),
              Text(awayTeam, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWinRateStatic(double home, double away, String homeTeam, String awayTeam) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Color(0xFFF5F5F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Expanded(child: Column(children: [
          Text(homeTeam, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${home.toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF111113))),
        ])),
        const Column(children: [
          Icon(Icons.sports_baseball, size: 16, color: Colors.grey),
          SizedBox(height: 2),
          Text('승리확률', style: TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
        Expanded(child: Column(children: [
          Text(awayTeam, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${away.toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFC62828))),
        ])),
      ]),
    );
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
    if (_isLoading || _gameData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('경기 상세')),
        body: RefreshIndicator(
          onRefresh: () async { _loadAttempt = 0; setState(() => _isLoading = true); await _loadData(); },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: MediaQuery.of(context).size.height - 120,
              child: _buildRelayShimmer(),
            ),
          ),
        ),
      );
    }

    final game = _gameData!['game'];
    final innings = _gameData!['innings'] as List;
    final pitchers = _gameData!['pitchers'] as List;
    final batters = _gameData!['batters'] as List;

    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Text('${game['home_team']} vs ${game['away_team']}'),
        actions: [
          IconButton(
            tooltip: _fieldPinned ? '필드뷰 고정 해제' : '필드뷰 상단 고정',
            icon: Icon(_fieldPinned ? Icons.push_pin : Icons.push_pin_outlined),
            color: _fieldPinned ? const Color(0xFFE53935) : null,
            onPressed: () => setState(() => _fieldPinned = !_fieldPinned),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => _GameShareSheet(game: game),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 핀 시: Column[panel-spacer, Expanded(scrollable)]. 핀 영역 아래에서만 scroll.
          // 핀 X: 일반 SingleChildScrollView 전체 scroll.
          _fieldPinned
              ? Column(
                  children: [
                    // panel-spacer: 스코어보드/팀로고 등 헤더 영역을 panel로 가림
                    SizedBox(height: _sameDayGames.isNotEmpty ? 460 : 360),
                    Expanded(
                      // gameHeader skip — 핀 시 panel 바로 아래 TabBarView (득점요약/이닝중계)만 표시
                      child: TabBarView(
                        controller: _tabController,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildInningsTab(innings),
                          _buildLineupTab(),
                          _buildStatsTab(pitchers, batters),
                          _buildHighlightsTab(),
                        ],
                      ),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildGameHeader(game, roundedBottom: true),
                      SizedBox(
                        height: MediaQuery.of(context).size.height
                                - kToolbarHeight
                                - MediaQuery.of(context).padding.top
                                - 100,
                        child: TabBarView(
                          controller: _tabController,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _buildInningsTab(innings),
                            _buildLineupTab(),
                            _buildStatsTab(pitchers, batters),
                            _buildHighlightsTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          // 핀 활성화 시 상단 sticky panel (필드뷰 + 다른 경기)
          if (_fieldPinned)
            Positioned(
              top: 0, left: 0, right: 0,
              child: _buildPinnedPanel(game),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.of(context).viewPadding.bottom,
            child: _buildGameFloatingNav(),
          ),
        ],
      ),
    );
  }

  Widget _buildSameDayStrip() {
    // mockup MiniGames — 2-col grid
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink   = isDark ? const Color(0xFFF4F4F5) : const Color(0xFF111113);
    final sub   = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final paper = isDark ? const Color(0xFF18181C) : Colors.white;
    final paper2= isDark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6);
    final line  = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
    const live  = Color(0xFFE53935);

    return Container(
      color: paper,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 5, left: 2),
            child: Text('다른 경기',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: sub, letterSpacing: 0.3)),
          ),
          // 1x4 한 줄 배치 (5경기 - 현재경기 = 4)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 6, crossAxisSpacing: 6,
              childAspectRatio: 1.4,
            ),
            itemCount: _sameDayGames.length,
            itemBuilder: (_, i) {
              final g = _sameDayGames[i] as Map;
              final homeCode = g['home_team_code'] as String? ?? '';
              final awayCode = g['away_team_code'] as String? ?? '';
              final homeScore = g['home_score'];
              final awayScore = g['away_score'];
              final status = g['status'] as String? ?? '';
              final isLive = status == '진행';
              final isDone = status == '종료';
              final isCurrent = g['id'] == widget.gameId;

              String scoreText;
              if (isDone || isLive) {
                scoreText = '${awayScore ?? 0}:${homeScore ?? 0}';
              } else {
                scoreText = g['start_time'] as String? ?? '-';
              }

              return GestureDetector(
                onTap: isCurrent ? null
                    : () => Navigator.pushReplacement(context,
                        MaterialPageRoute(builder: (_) => GameDetailScreen(gameId: g['id'] as int))),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  decoration: BoxDecoration(
                    color: isCurrent ? paper2 : paper,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isCurrent ? ink : line, width: isCurrent ? 1.5 : 1),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TeamLogo(teamCode: awayCode, size: 16),
                          const SizedBox(width: 3),
                          Text('vs', style: TextStyle(fontSize: 9, color: sub, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 3),
                          TeamLogo(teamCode: homeCode, size: 16),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isLive) ...[
                            Container(width: 4, height: 4,
                                decoration: const BoxDecoration(color: live, shape: BoxShape.circle)),
                            const SizedBox(width: 3),
                          ],
                          Text(scoreText,
                              style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800,
                                color: isLive ? live : ink,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              )),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // 진행중 게임: _relayData.current_state 우선 사용 (Naver 직조회 — DB(30s 사이클)보다 fresh)
  int _liveScore(Map<String, dynamic> game, String key) {
    if (game['status'] == '진행' && _relayData != null) {
      final cs = _relayData!['current_state'];
      if (cs is Map) {
        final v = cs[key];
        if (v is int) return v;
        if (v is String) return int.tryParse(v) ?? 0;
      }
    }
    return (game[key] as int?) ?? 0;
  }

  Widget _buildGameHeader(Map<String, dynamic> game, {bool roundedBottom = true, bool includeField = true}) {
    final status = game['status'] as String? ?? '';
    final isLive = status == '진행';
    final isDone = status == '종료';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final homeCode  = game['home_team_code'] as String? ?? '';
    final awayCode  = game['away_team_code']  as String? ?? '';
    final homeTeam  = game['home_team']  as String? ?? '';
    final awayTeam  = game['away_team']  as String? ?? '';
    final homeScore = _liveScore(game, 'home_score');
    final awayScore = _liveScore(game, 'away_score');
    final homeRank  = _rankMap[game['home_team_id'] as int?];
    final awayRank  = _rankMap[game['away_team_id'] as int?];
    final homeRecent = List<String>.from(game['home_recent_5'] ?? []);
    final awayRecent = List<String>.from(game['away_recent_5'] ?? []);

    final winRate = _getWinRate();
    final homeWinRate = (winRate?['homeTeamWinRate'] as num?)?.toDouble();
    final awayWinRate = (winRate?['awayTeamWinRate'] as num?)?.toDouble();
    final innings = (_gameData?['innings'] as List?) ?? [];

    // Build field widget
    Widget? fieldWidget;
    if (_relayData != null) {
      final relayState = _relayData!['current_state'];
      final fieldView  = _relayData!['field_view'] as Map<String, dynamic>?;
      if (relayState != null) {
        fieldWidget = _FullFieldView(
          base1: relayState['base1'] == true,
          base2: relayState['base2'] == true,
          base3: relayState['base3'] == true,
          fieldView: fieldView,
          isDark: isDark,
        );
      }
    } else if (_rosterData != null) {
      final homeBatters  = (_rosterData!['home']['batters']  as List? ?? []).cast<Map<String, dynamic>>();
      final homePitchers = (_rosterData!['home']['pitchers'] as List? ?? []).cast<Map<String, dynamic>>();
      final defense = homeBatters
          .where((b) => b['is_starter'] == true && b['batting_order'] != null && b['batting_order'] != 0)
          .map<Map<String, dynamic>>((b) => {
            'name': b['name'] as String? ?? '',
            'image': b['profile_image'],
            'position': b['position'] as String? ?? '',
            'pos_code': '',
          }).toList();
      if (!defense.any((d) => d['position'] == '투수')) {
        final sp = homePitchers.where((p) => p['is_starter'] == true).toList();
        if (sp.isNotEmpty) defense.add({'name': sp.first['name'] as String? ?? '', 'image': sp.first['profile_image'], 'position': '투수', 'pos_code': 'P'});
      }
      fieldWidget = _FullFieldView(
        base1: false, base2: false, base3: false,
        fieldView: {'defense': defense, 'batter': null, 'pitcher': null, 'runners': null},
        isDark: isDark,
      );
    } else {
      // 로스터 로딩 중: 빈 필드뷰 플레이스홀더 (종료/예정 경기)
      fieldWidget = _FullFieldView(
        base1: false, base2: false, base3: false,
        fieldView: null,
        isDark: isDark,
      );
    }

    // ── 토큰 ──────────────────────────────
    final ink    = isDark ? const Color(0xFFF4F4F5) : const Color(0xFF111113);
    final ink2   = isDark ? const Color(0xFFC9C9D1) : const Color(0xFF3F3F46);
    final ink3   = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    final sub    = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final paper  = isDark ? const Color(0xFF18181C) : Colors.white;
    final paper2 = isDark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6);
    final line   = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
    final line2  = isDark ? const Color(0xFF33333A) : const Color(0xFFE0E0E4);
    const live   = Color(0xFFE53935);

    // BSO dot
    Widget bsoDot(bool on, Color c) => Container(
      width: 8, height: 8,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? c : line2,
      ),
    );
    Widget bsoGroup(String lbl, int count, int max, Color c) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(lbl, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ink3)),
        const SizedBox(width: 3),
        ...List.generate(max, (i) => bsoDot(i < count, c)),
      ],
    );

    String shortName(String n) => n.length > 3 ? n.substring(0, 3) : n;

    return ClipRRect(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(roundedBottom ? 16 : 0)),
      child: Container(
        color: paper,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── ScoreBoardDark (mockup 다크 박스 유지) ──
            if (innings.isNotEmpty) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _buildFieldScoreOverlay(innings, game),
                ),
              ),
              const SizedBox(height: 12),
            ] else const SizedBox(height: 14),

            // ── WeatherLine (스코어보드 ↓ 팀로고 ↑ 사이) ──
            if (_weatherData != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 7, height: 7,
                        decoration: BoxDecoration(color: line2, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    DefaultTextStyle(
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ink3),
                      child: _buildWeatherRow(_weatherData!),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── MatchupHeader (paper/ink) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        TeamLogo(teamCode: homeCode, size: 56),
                        const SizedBox(height: 6),
                        Text(shortName(homeTeam),
                            style: TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                        if (homeRank != null && homeRank > 0)
                          Text('${homeRank}위', style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.w600)),
                        if (homeWinRate != null) ...[
                          const SizedBox(height: 4),
                          _buildWinRatePill(homeWinRate),
                        ],
                        if (homeRecent.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          _buildRecentBar(homeRecent, true),
                        ],
                        // 홈팀 승투/패투 (종료 + 무승부 아님)
                        if (isDone && !((homeScore == awayScore))) ...[
                          const SizedBox(height: 6),
                          homeScore > awayScore
                              ? _pitcherBadge(game['win_pitcher'] as String? ?? '', const Color(0xFF1976D2), '승')
                              : _pitcherBadge(game['lose_pitcher'] as String? ?? '', const Color(0xFFC62828), '패'),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('$homeScore',
                              style: TextStyle(color: ink, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.6, fontFeatures: const [FontFeature.tabularFigures()])),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(':',
                                style: TextStyle(color: line2, fontSize: 24, fontWeight: FontWeight.w400)),
                          ),
                          Text('$awayScore',
                              style: TextStyle(color: ink, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.6, fontFeatures: const [FontFeature.tabularFigures()])),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (isLive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: live.withValues(alpha: isDark ? 0.20 : 0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 5, height: 5,
                                decoration: const BoxDecoration(color: live, shape: BoxShape.circle)),
                            const SizedBox(width: 5),
                            Text('${game['current_inning']}회 ${game['inning_half'] ?? ''}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: live)),
                          ]),
                        )
                      else
                        Text(
                          isDone ? '경기 종료'
                              : status == '예정' || status == '라인업' ? (game['start_time'] as String? ?? '예정') : status,
                          style: TextStyle(color: ink3, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        TeamLogo(teamCode: awayCode, size: 56),
                        const SizedBox(height: 6),
                        Text(shortName(awayTeam),
                            style: TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                        if (awayRank != null && awayRank > 0)
                          Text('${awayRank}위', style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.w600)),
                        if (awayWinRate != null) ...[
                          const SizedBox(height: 4),
                          _buildWinRatePill(awayWinRate),
                        ],
                        if (awayRecent.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          _buildRecentBar(awayRecent, false),
                        ],
                        // 원정팀 승투/패투 (종료 + 무승부 아님)
                        if (isDone && !((homeScore == awayScore))) ...[
                          const SizedBox(height: 6),
                          awayScore > homeScore
                              ? _pitcherBadge(game['win_pitcher'] as String? ?? '', const Color(0xFF1976D2), '승')
                              : _pitcherBadge(game['lose_pitcher'] as String? ?? '', const Color(0xFFC62828), '패'),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (includeField) const SizedBox(height: 16),
            // ── FieldSlot (확장 슬롯 + 상단 BSO overlay) ──
            if (includeField && fieldWidget != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: CustomPaint(
                  painter: _DashedRectPainter(color: line2, radius: 16, dashLength: 6, gap: 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: CustomPaint(painter: _GrassExtensionPainter()),
                        ),
                        // 슬롯/배경 확장: padding 20/28 + SizedBox 230
                        Padding(
                          // top 60: BSO overlay (bottom ~33) ↔ CF label (top ~51) 사이 ~18px 여유
                          padding: const EdgeInsets.fromLTRB(16, 60, 16, 20),
                          child: SizedBox(height: 230, width: double.infinity, child: fieldWidget),
                        ),
                        // BSO overlay — 진행중 + relay 데이터 시 필드 상단(중견수 위) center
                        if (isLive && _relayData?['current_state'] != null)
                          Positioned(
                            top: 8, left: 0, right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: live, borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        Container(width: 4, height: 4,
                                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                                        const SizedBox(width: 3),
                                        const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                                      ]),
                                    ),
                                    const SizedBox(width: 8),
                                    _bsoOverlayGroup('B', (_relayData!['current_state']['ball'] as int? ?? 0).clamp(0, 3), 3, const Color(0xFF22C55E)),
                                    const SizedBox(width: 6),
                                    _bsoOverlayGroup('S', (_relayData!['current_state']['strike'] as int? ?? 0).clamp(0, 2), 2, live),
                                    const SizedBox(width: 6),
                                    _bsoOverlayGroup('O', (_relayData!['current_state']['out'] as int? ?? 0).clamp(0, 2), 2, const Color(0xFFFFA000)),
                                    const SizedBox(width: 8),
                                    _isRelayRefreshing
                                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : GestureDetector(
                                            onTap: _refreshRelayAll,
                                            child: const Icon(Icons.refresh, size: 16, color: Colors.white),
                                          ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── 다른 경기 (1x4) — 필드뷰 아래 ──
            if (includeField && _sameDayGames.isNotEmpty) _buildSameDayStrip(),

            const SizedBox(height: 14),
            Container(height: 1, color: line),
          ],
        ),
      ),
    );
  }

  // BSO overlay (검은 반투명 배경 위 흰 텍스트 + 컬러 dot)
  Widget _bsoOverlayGroup(String lbl, int count, int max, Color c) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(lbl, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
        const SizedBox(width: 3),
        ...List.generate(max, (i) => Container(
          width: 7, height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < count ? c : Colors.white.withValues(alpha: 0.25),
          ),
        )),
      ],
    );
  }

  Widget _buildWinRatePill(double rate) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink2  = isDark ? const Color(0xFFC9C9D1) : const Color(0xFF3F3F46);
    final sub   = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final paper2= isDark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: paper2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('승리확률 ', style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.w600)),
          Text('${rate.toStringAsFixed(0)}%',
              style: TextStyle(color: ink2, fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildFieldScoreOverlay(List innings, Map<String, dynamic> game) {
    // mockup ScoreBoardDark 정확 매칭
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final awayCode = game['away_team_code'] as String? ?? '';
    final homeCode = game['home_team_code'] as String? ?? '';
    final awayShort = teamDisplayName(awayCode);
    final homeShort = teamDisplayName(homeCode);

    final sbBg = isDark ? Colors.black : const Color(0xFF1B1B1F);

    // mockup styles
    final hdrInning = TextStyle(color: Colors.white.withValues(alpha: 0.40), fontSize: 11, fontWeight: FontWeight.w600);
    final hdrRHBE = TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 11, fontWeight: FontWeight.w700);
    const teamStyle = TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700);
    final dimVal = TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]);
    final zeroVal = TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]);
    const liveVal = TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]);
    const rStyle = TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]);
    final secStyle = TextStyle(color: Colors.white.withValues(alpha: 0.60), fontSize: 11, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]);

    const teamColW = 40.0;
    const rhbeW = 24.0;
    const innN = 9;

    Widget innExpanded(Widget child) => Expanded(child: Center(child: child));

    Widget dataRow(String teamLabel, List<int> inningRuns, int r, int h, int b, int e) {
      // 미진행 이닝(played==false) 빈칸 + dim val
      final cur = inningRuns.length;
      return SizedBox(
        height: 30,
        child: Row(children: [
          SizedBox(width: teamColW, child: Text(teamLabel, style: teamStyle, overflow: TextOverflow.ellipsis)),
          for (int n = 1; n <= innN; n++) innExpanded(Builder(builder: (_) {
            final played = n <= cur;
            if (!played) return Text('', style: dimVal);
            final v = inningRuns[n - 1];
            return Text('$v', textAlign: TextAlign.center, style: v > 0 ? liveVal : zeroVal);
          })),
          SizedBox(width: rhbeW, child: Center(child: Text('$r', style: rStyle))),
          SizedBox(width: rhbeW, child: Center(child: Text('$h', style: secStyle))),
          SizedBox(width: rhbeW, child: Center(child: Text('$b', style: secStyle))),
          SizedBox(width: rhbeW, child: Center(child: Text('$e', style: secStyle))),
        ]),
      );
    }

    final awayRuns = innings.map((i) => (i as Map)['away_runs'] as int? ?? 0).toList();
    final homeRuns = innings.map((i) => (i as Map)['home_runs'] as int? ?? 0).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: sbBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 헤더 row
          SizedBox(
            height: 18,
            child: Row(children: [
              const SizedBox(width: teamColW),
              for (int n = 1; n <= innN; n++) innExpanded(Text('$n', style: hdrInning)),
              SizedBox(width: rhbeW, child: Center(child: Text('R', style: hdrRHBE))),
              SizedBox(width: rhbeW, child: Center(child: Text('H', style: hdrRHBE))),
              SizedBox(width: rhbeW, child: Center(child: Text('B', style: hdrRHBE))),
              SizedBox(width: rhbeW, child: Center(child: Text('E', style: hdrRHBE))),
            ]),
          ),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.12), margin: const EdgeInsets.only(bottom: 3)),
          // 어웨이 → 홈
          dataRow(awayShort, awayRuns,
            _liveScore(game, 'away_score'),
            game['away_hits']  as int? ?? 0,
            game['away_walks'] as int? ?? 0,
            game['away_errors'] as int? ?? 0,
          ),
          dataRow(homeShort, homeRuns,
            _liveScore(game, 'home_score'),
            game['home_hits']  as int? ?? 0,
            game['home_walks'] as int? ?? 0,
            game['home_errors'] as int? ?? 0,
          ),
        ],
      ),
    );
  }

  Widget _buildScoreHeader(Map<String, dynamic> game) {
    final homeRecent = List<String>.from(game['home_recent_5'] ?? []);
    final awayRecent = List<String>.from(game['away_recent_5'] ?? []);
    final homeRank = _rankMap[game['home_team_id'] as int?];
    final awayRank = _rankMap[game['away_team_id'] as int?];
    return Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFF111113),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    TeamLogo(teamCode: game['home_team_code'] as String? ?? '', size: 48),
                    const SizedBox(height: 6),
                    Text(game['home_team'],
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center),
                    if (homeRank != null && homeRank > 0)
                      Text('${homeRank}위', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    if (homeRecent.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _buildRecentBar(homeRecent, true),
                    ],
                  ],
                ),
              ),
              Text(
                game['status'] == '예정'
                    ? 'VS'
                    : '${_liveScore(game, 'home_score')} : ${_liveScore(game, 'away_score')}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: Column(
                  children: [
                    TeamLogo(teamCode: game['away_team_code'] as String? ?? '', size: 48),
                    const SizedBox(height: 6),
                    Text(game['away_team'],
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center),
                    if (awayRank != null && awayRank > 0)
                      Text('${awayRank}위', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    if (awayRecent.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _buildRecentBar(awayRecent, false),
                    ],
                  ],
                ),
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
          // 승투/패투 (종료 시)
          if (game['status'] == '종료' && (game['win_pitcher'] != null || game['lose_pitcher'] != null)) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (game['win_pitcher'] != null) ...[
                  _pitcherBadge(game['win_pitcher'] as String, Colors.lightBlueAccent, '승'),
                  if (game['lose_pitcher'] != null) const SizedBox(width: 16),
                ],
                if (game['lose_pitcher'] != null)
                  _pitcherBadge(game['lose_pitcher'] as String, Colors.redAccent, '패'),
              ],
            ),
          ],
          if (_weatherData != null) ...[
            const SizedBox(height: 6),
            _buildWeatherRow(_weatherData!),
          ],
        ],
      ),
    );
  }

  // 그날 기록 lookup — pitchers list에서 name 매칭 → "5이닝 2실점 7K"
  String _pitcherDayStats(String name) {
    final pitchers = (_gameData?['pitchers'] as List?) ?? [];
    for (final p in pitchers) {
      if ((p['name'] as String? ?? '') != name) continue;
      final ip = p['innings_pitched'];
      final r = p['runs_allowed'];
      final so = p['strikeouts'];
      final parts = <String>[];
      if (ip != null && ip != 0) parts.add('${ip}이닝');
      if (r != null) parts.add('${r}실점');
      if (so != null && so > 0) parts.add('${so}K');
      return parts.join(' ');
    }
    return '';
  }

  Widget _pitcherBadge(String name, Color color, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF4F4F5) : const Color(0xFF111113);
    final sub = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    final stats = _pitcherDayStats(name);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name, style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w800)),
            if (stats.isNotEmpty)
              Text(stats, style: TextStyle(color: sub, fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _buildRecentBar(List<String> recent, bool isHome) {
    if (recent.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink   = isDark ? const Color(0xFFF4F4F5) : const Color(0xFF111113);
    final ink3  = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    final sub   = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final line2 = isDark ? const Color(0xFF33333A) : const Color(0xFFE0E0E4);
    final track = isDark ? const Color(0xFF2C2C33) : const Color(0xFFE8E8EC);
    final displayed = isHome ? recent.reversed.toList() : recent;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: displayed.map((r) {
        Color bg, fg;
        Color? bd;
        if (r == 'W') {
          bg = ink;
          fg = isDark ? const Color(0xFF0F0F12) : Colors.white;
          bd = Colors.transparent;
        } else if (r == 'L') {
          bg = Colors.transparent;
          fg = sub;
          bd = line2;
        } else {
          bg = track;
          fg = ink3;
          bd = Colors.transparent;
        }
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Container(
            width: 18, height: 18,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: bd, width: 1),
            ),
            alignment: Alignment.center,
            child: Text(r, style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w800)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildWeatherRow(Map<String, dynamic> w) {
    // 부모 DefaultTextStyle (paper 톤 ink3) 따라가도록 color 제거
    if (w['indoor'] == true) {
      return const Text('실내 구장', style: TextStyle(fontSize: 12));
    }
    final emoji = w['emoji'] ?? '';
    final temp = w['temp'];
    final feelsLike = w['feels_like'];
    final humidity = w['humidity'];
    final windSpeed = w['wind_speed'];
    final description = w['description'] ?? '';
    final pop = w['pop'];
    final parts = <String>[
      if (emoji.isNotEmpty) emoji,
      if (description.isNotEmpty) description,
      if (temp != null) '${temp}°C',
      if (feelsLike != null) '체감 ${feelsLike}°',
      if (humidity != null) '습도 $humidity%',
      if (windSpeed != null && (windSpeed as num) > 0) '풍속 ${windSpeed}m/s',
      if (pop != null) '강수 $pop%',
    ];
    return Text(parts.join('  '), style: const TextStyle(fontSize: 12));
  }

  // 핀 활성화 시 sticky panel — 필드뷰 + 다른 경기 strip만 (BSO는 필드뷰 안 overlay)
  Widget _buildPinnedPanel(Map<String, dynamic> game) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final paper  = isDark ? const Color(0xFF18181C) : Colors.white;
    final line2  = isDark ? const Color(0xFF33333A) : const Color(0xFFE0E0E4);
    const live   = Color(0xFFE53935);

    Widget? fieldWidget;
    if (_relayData != null) {
      final relayState = _relayData!['current_state'];
      final fieldView  = _relayData!['field_view'] as Map<String, dynamic>?;
      if (relayState != null) {
        fieldWidget = _FullFieldView(
          base1: relayState['base1'] == true,
          base2: relayState['base2'] == true,
          base3: relayState['base3'] == true,
          fieldView: fieldView,
          isDark: isDark,
        );
      }
    } else if (_rosterData != null) {
      final homeBatters = (_rosterData!['home']['batters'] as List? ?? []).cast<Map<String, dynamic>>();
      final defense = homeBatters
          .where((b) => b['is_starter'] == true && b['batting_order'] != null && b['batting_order'] != 0)
          .map<Map<String, dynamic>>((b) => {
                'name': b['name'] as String? ?? '',
                'image': b['profile_image'],
                'position': b['position'] as String? ?? '',
                'pos_code': '',
              }).toList();
      fieldWidget = _FullFieldView(
        base1: false, base2: false, base3: false,
        fieldView: {'defense': defense, 'batter': null, 'pitcher': null, 'runners': null},
        isDark: isDark,
      );
    } else {
      fieldWidget = _FullFieldView(base1: false, base2: false, base3: false, fieldView: null, isDark: isDark);
    }

    final isLive = (game['status'] as String? ?? '') == '진행';

    return Container(
      color: paper,
      // panel-spacer와 동일 height 강제 — 빈 공간 발생 시 scaffold body 검은 띠 노출 방지
      height: _sameDayGames.isNotEmpty ? 460 : 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: CustomPaint(
              painter: _DashedRectPainter(color: line2, radius: 16, dashLength: 6, gap: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    const Positioned.fill(child: CustomPaint(painter: _GrassExtensionPainter())),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
                      child: SizedBox(height: 230, width: double.infinity, child: fieldWidget),
                    ),
                    // BSO overlay
                    if (isLive && _relayData?['current_state'] != null)
                      Positioned(
                        top: 8, left: 0, right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: live, borderRadius: BorderRadius.circular(999)),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                                    const SizedBox(width: 3),
                                    const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                                  ]),
                                ),
                                const SizedBox(width: 8),
                                _bsoOverlayGroup('B', (_relayData!['current_state']['ball'] as int? ?? 0).clamp(0, 3), 3, const Color(0xFF22C55E)),
                                const SizedBox(width: 6),
                                _bsoOverlayGroup('S', (_relayData!['current_state']['strike'] as int? ?? 0).clamp(0, 2), 2, live),
                                const SizedBox(width: 6),
                                _bsoOverlayGroup('O', (_relayData!['current_state']['out'] as int? ?? 0).clamp(0, 2), 2, const Color(0xFFFFA000)),
                                const SizedBox(width: 8),
                                _isRelayRefreshing
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : GestureDetector(
                                        onTap: _refreshRelayAll,
                                        child: const Icon(Icons.refresh, size: 16, color: Colors.white),
                                      ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_sameDayGames.isNotEmpty) _buildSameDayStrip(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildFieldSection(Map game) {
    final isLive = game['status'] == '진행';
    if (isLive && _relayData != null) return _buildLiveStatus();
    if (_rosterData == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final homeBatters = (_rosterData!['home']['batters'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final homePitchers = (_rosterData!['home']['pitchers'] as List? ?? [])
        .cast<Map<String, dynamic>>();

    final defense = homeBatters
        .where((b) => b['is_starter'] == true &&
            b['batting_order'] != null && b['batting_order'] != 0)
        .map<Map<String, dynamic>>((b) => {
          'name': b['name'] as String? ?? '',
          'image': b['profile_image'],
          'position': b['position'] as String? ?? '',
          'pos_code': '',
        })
        .toList();

    final hasPitcher = defense.any((d) => (d['position'] as String?) == '투수');
    if (!hasPitcher) {
      final spList = homePitchers.where((p) => p['is_starter'] == true).toList();
      if (spList.isNotEmpty) {
        defense.add({
          'name': spList.first['name'] as String? ?? '',
          'image': spList.first['profile_image'],
          'position': '투수',
          'pos_code': 'P',
        });
      }
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF0D2818), const Color(0xFF1B3A22)]
                : [const Color(0xFF1B4332), const Color(0xFF2D6A4F)],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 220,
              child: _FullFieldView(
                base1: false, base2: false, base3: false,
                fieldView: {'defense': defense, 'batter': null, 'pitcher': null, 'runners': null},
                isDark: isDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveStatus() {
    final state = _relayData!['current_state'];
    if (state == null) return const SizedBox.shrink();
    final fieldView = _relayData!['field_view'] as Map<String, dynamic>?;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final balls   = (state['ball']   as int? ?? 0).clamp(0, 3);
    final strikes = (state['strike'] as int? ?? 0).clamp(0, 2);
    final outs    = (state['out']    as int? ?? 0).clamp(0, 2);
    final base1   = state['base1'] == true;
    final base2   = state['base2'] == true;
    final base3   = state['base3'] == true;

    Widget bsoDot(bool on, Color c) => Container(
      width: 11, height: 11,
      margin: const EdgeInsets.symmetric(horizontal: 2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? c : Colors.white.withOpacity(0.18),
        boxShadow: on ? [BoxShadow(color: c.withOpacity(0.65), blurRadius: 5, spreadRadius: 1)] : null,
      ),
    );
    Widget bsoGroup(String lbl, int count, int max, Color c) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(lbl, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
        const SizedBox(width: 4),
        ...List.generate(max, (i) => bsoDot(i < count, c)),
      ],
    );

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF0D2818), const Color(0xFF1B3A22)]
                : [const Color(0xFF1B4332), const Color(0xFF2D6A4F)],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // BSO row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  bsoGroup('B', balls, 3, Colors.green[300]!),
                  const SizedBox(width: 20),
                  bsoGroup('S', strikes, 2, Colors.red[300]!),
                  const SizedBox(width: 20),
                  bsoGroup('O', outs, 2, Colors.orange[300]!),
                ],
              ),
            ),
            // Full field view
            SizedBox(
              height: 230,
              child: _FullFieldView(
                base1: base1, base2: base2, base3: base3,
                fieldView: fieldView,
                isDark: isDark,
              ),
            ),
          ],
        ),
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
      // pitch_num은 Naver 누적 카운트(타석 리셋 없음) → 결과이벤트 기반으로 타석 경계 감지
      // 타석 종료 신호: rtype==13(결과)/rtype==23(결과) → 다음 rtype==1이 새 타석
      // 타석 교체 신호: rtype==8 + batter_name 변경
      final List<Map<String, dynamic>> result = [];

      String? batterName;
      String? pitcherName;
      List currentPitches = [];
      Map<String, dynamic>? atBatResult;
      List currentEvents = [];
      bool pendingNewAtBat = true;

      void flush() {
        if (batterName != null || currentPitches.isNotEmpty) {
          result.add({
            'batter': batterName ?? '?',
            'pitcher': pitcherName,
            'pitches': List.from(currentPitches),
            'result': atBatResult,
            'events': List.from(currentEvents),
          });
        }
        currentPitches = [];
        atBatResult = null;
        currentEvents = [];
        batterName = null;
      }

      for (final r in items) {
        final rtype = r['type'] as int?;
        if (rtype == 0) continue;
        final bn = r['batter_name'] as String?;
        final pn = r['pitcher_name'] as String?;
        if (pn != null && pn.isNotEmpty) pitcherName = pn;

        if (rtype == 8) {
          // 명시적 타자 교체 이벤트
          if (bn != null && bn.isNotEmpty && bn != batterName) {
            flush();
            batterName = bn;
          }
        } else if (rtype == 1) {
          // 결과 이벤트 후 첫 투구 → 새 타석 시작
          if (pendingNewAtBat && currentPitches.isNotEmpty) flush();
          if (pendingNewAtBat) {
            batterName = bn;
            pendingNewAtBat = false;
          }
          // 타석 내 batter_name 업데이트 (앞쪽 잘못된 이름 교정)
          if (bn != null && bn.isNotEmpty) batterName = bn;
          currentPitches.add(r);
        } else if (rtype == 13 || rtype == 23) {
          if (bn != null && bn.isNotEmpty) batterName = bn;
          atBatResult = r as Map<String, dynamic>;
          pendingNewAtBat = true;
        } else if (rtype != null &&
            [2, 7, 14, 20, 21, 22, 24, 25, 30, 31].contains(rtype)) {
          if (bn != null && bn.isNotEmpty) batterName = bn;
          currentEvents.add(r);
        }
      }
      flush();
      return result;
    }

    final winRate = _getWinRate();

    final navBottom = 120.0 + MediaQuery.of(context).viewPadding.bottom;
    return SingleChildScrollView(
      controller: _inningScrollController,
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(18, 14, 18, navBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // mockup divider (헤더와 ScoringSummary 사이)
          Container(height: 1, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0)),
          const SizedBox(height: 16),
          if (innings.isNotEmpty && _relayAllData != null) ...[
            _buildScoringSection(innings, awayTeam, homeTeam),
            const SizedBox(height: 16),
          ],

          if (_relayAllData == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: _buildRelayShimmer(),
            )
          else if (relays.isEmpty)
            const Center(child: Text('중계 데이터가 없습니다'))
          else ...[
            Builder(builder: (ctx) {
              final isDark = Theme.of(ctx).brightness == Brightness.dark;
              final ink   = isDark ? const Color(0xFFF4F4F5) : const Color(0xFF111113);
              final ink3  = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
              final paper = isDark ? const Color(0xFF18181C) : Colors.white;
              final line  = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 12, left: 2),
                    child: Text('이닝별 중계',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: ink, letterSpacing: -0.2)),
                  ),
                  ...sortedInnings.map((inningNum) {
                    final items = grouped[inningNum]!;
                    final topItems = items.where((r) => (r['inning_half']?.toString() ?? '0') == '0').toList();
                    final botItems = items.where((r) => (r['inning_half']?.toString() ?? '0') == '1').toList();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: paper,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: line, width: 1),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                        ),
                        child: ExpansionTile(
                          initiallyExpanded: false,
                          tilePadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
                          title: Text('$inningNum회',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: ink, letterSpacing: -0.1)),
                          iconColor: ink3,
                          collapsedIconColor: ink3,
                          children: [
                            if (topItems.isNotEmpty) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(15, 10, 15, 6),
                                decoration: BoxDecoration(
                                  border: Border(top: BorderSide(color: line, width: 1)),
                                ),
                                child: Text('$inningNum회초 $awayTeam 공격',
                                    style: TextStyle(
                                        fontSize: 12, fontWeight: FontWeight.w700,
                                        color: Color(0xFF1976D2))),
                              ),
                              ...groupByBatter(topItems).map((e) => _buildBatterRelayTile(e)),
                            ],
                            if (botItems.isNotEmpty) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(15, 10, 15, 6),
                                decoration: BoxDecoration(
                                  border: Border(top: BorderSide(color: line, width: 1)),
                                ),
                                child: Text('$inningNum회말 $homeTeam 공격',
                                    style: TextStyle(
                                        fontSize: 12, fontWeight: FontWeight.w700,
                                        color: Color(0xFFC62828))),
                              ),
                              ...groupByBatter(botItems).map((e) => _buildBatterRelayTile(e)),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildBatterRelayTile(Map<String, dynamic> entry) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink   = isDark ? const Color(0xFFF4F4F5) : const Color(0xFF111113);
    final ink2  = isDark ? const Color(0xFFC9C9D1) : const Color(0xFF3F3F46);
    final ink3  = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    final sub   = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final paper2= isDark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6);
    final line  = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
    final line2 = isDark ? const Color(0xFF33333A) : const Color(0xFFE0E0E4);

    final batterName = entry['batter'] as String? ?? '';
    final pitcherName = entry['pitcher'] as String?;
    final pitches = entry['pitches'] as List? ?? [];

    final resultRelay = entry['result'] as Map<String, dynamic>?;
    final events = entry['events'] as List? ?? [];

    final resultTitle = resultRelay?['title'] as String? ?? '';
    final result = resultTitle.contains(' : ')
        ? resultTitle.split(' : ').sublist(1).join(' : ').trim()
        : resultTitle;

    // result chip: out(red)/hit(green)/scoring(amber)/walk(blue)/default(ink3)
    Color resultBg, resultFg;
    if (result.contains('홈런')) {
      resultFg = const Color(0xFFD97706);
      resultBg = const Color(0xFFFBBF24).withValues(alpha: isDark ? 0.30 : 0.18);
    } else if (result.contains('안타') || result.contains('출루')) {
      resultFg = const Color(0xFF16A34A);
      resultBg = const Color(0xFF4ADE80).withValues(alpha: isDark ? 0.20 : 0.12);
    } else if (result.contains('아웃') || result.contains('삼진')) {
      resultFg = const Color(0xFFE53935);
      resultBg = const Color(0xFFF43F5E).withValues(alpha: isDark ? 0.20 : 0.12);
    } else if (result.contains('볼넷') || result.contains('몸에 맞는')) {
      resultFg = const Color(0xFF2563EB);
      resultBg = const Color(0xFF60A5FA).withValues(alpha: isDark ? 0.20 : 0.12);
    } else {
      resultFg = ink3;
      resultBg = paper2;
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: line, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 타석 헤더: 배터 + vs 투수 + result chip + 투구위치
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 7, runSpacing: 5,
            children: [
              Text(batterName,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ink, letterSpacing: -0.1)),
              if (pitcherName != null)
                Text('vs $pitcherName',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: sub)),
              if (result.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: resultBg, borderRadius: BorderRadius.circular(99)),
                  child: Text(result,
                      style: TextStyle(fontSize: 11, color: resultFg, fontWeight: FontWeight.w700)),
                ),
              if (pitches.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    final inningNum = (pitches.first['inning'] as num?)?.toInt();
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                      builder: (_) => PitchLocationSheet(
                        gameId: widget.gameId,
                        gameStatus: _gameData?['game']['status'] as String? ?? '종료',
                        initialPitcher: pitcherName,
                        initialBatter: batterName,
                        initialInning: inningNum,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: paper2, borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: line2, width: 1),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.grid_on, size: 10, color: ink3),
                      const SizedBox(width: 4),
                      Text('투구위치', style: TextStyle(fontSize: 11, color: ink3, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
            ],
          ),
          // 이벤트 (도루/홈인/교체/방문 등)
          if (events.isNotEmpty) const SizedBox(height: 6),
          ...events.map((r) {
            final rtype = r['type'] as int?;
            final title = r['title'] as String? ?? '';
            Color color = ink3;
            if (rtype == 14 || rtype == 31) color = const Color(0xFFD97706);
            else if (rtype == 2 || rtype == 20) color = const Color(0xFF7C3AED);
            else if (rtype == 7 || rtype == 21) color = const Color(0xFF0D9488);
            else if (rtype == 22) color = const Color(0xFF4F46E5);
            else if (rtype == 23) color = const Color(0xFFCA8A04);
            else if (rtype == 24) color = const Color(0xFF475569);
            else if (rtype == 25) color = const Color(0xFFE53935);
            return Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(children: [
                Text('↔ ', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
                Expanded(
                  child: Text(title,
                      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            );
          }),
          // 투구별
          if (pitches.isNotEmpty) const SizedBox(height: 7),
          ...pitches.asMap().entries.map((e) {
            final r = e.value;
            final pitchResult = r['pitch_result'] as String?;
            final speed = _speedToString(r['speed']);
            final stuff = r['stuff'] as String?;
            final pitchNum = e.key + 1;
            final title = r['title'] as String?;

            String pitchResultText = '';
            if (title != null) {
              final parts = title.split(' ');
              if (parts.length >= 2) pitchResultText = parts[1];
            }

            // pitch dot 색: B=green, T/S=red, F=orange, H/X=blue
            Color dotBg, dotFg;
            switch (pitchResult) {
              case 'B': dotBg = const Color(0xFF4ADE80); dotFg = const Color(0xFF14532D); break;
              case 'T': dotBg = const Color(0xFFFB7185); dotFg = const Color(0xFF881337); break;
              case 'S': dotBg = const Color(0xFFF43F5E); dotFg = const Color(0xFF881337); break;
              case 'F': dotBg = const Color(0xFFFB923C); dotFg = const Color(0xFF7C2D12); break;
              case 'H': case 'X': dotBg = const Color(0xFF60A5FA); dotFg = const Color(0xFF1E3A8A); break;
              default: dotBg = line2; dotFg = ink3;
            }

            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                SizedBox(
                  width: 22,
                  child: Text('$pitchNum구',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, color: sub, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(color: dotBg, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(pitchResult ?? '',
                      style: TextStyle(fontSize: 11, color: dotFg, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 50,
                  child: Text(pitchResultText,
                      style: TextStyle(fontSize: 11, color: ink3, fontWeight: FontWeight.w600)),
                ),
                if (stuff != null)
                  Expanded(
                    child: Text(stuff,
                        style: TextStyle(fontSize: 11, color: ink2, fontWeight: FontWeight.w500)),
                  )
                else const Spacer(),
                if (speed != null)
                  Text('${speed}km/h',
                      style: TextStyle(fontSize: 11, color: sub, fontWeight: FontWeight.w600)),
              ]),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildScoringSection(List innings, String awayTeam, String homeTeam) {
    final relays = _relayAllData?['relays'] as List? ?? [];
    if (relays.isEmpty) return const SizedBox.shrink();

    final homeCode = _gameData?['game']['home_team_code'] as String? ?? '';
    final awayCode = _gameData?['game']['away_team_code'] as String? ?? '';

    // Group relay events by inning + half
    final Map<String, List> byHalf = {};
    for (final r in relays) {
      final ing = r['inning'] as int? ?? 0;
      final half = r['inning_half']?.toString() ?? '0';
      byHalf.putIfAbsent('$ing:$half', () => []).add(r);
    }

    // 득점 부여한 atbat 단위로 row 분리. 누적 score 매 row마다.
    int cumAway = 0, cumHome = 0;
    final items = <Map<String, dynamic>>[];
    for (final inn in innings) {
      final num = inn['inning'] as int? ?? 0;
      final awayR = inn['away_runs'] as int? ?? 0;
      final homeR = inn['home_runs'] as int? ?? 0;

      // 한 half-inning에서 RBI atbat을 분리 — 매 RBI마다 1 row
      void splitHalf(int totalRuns, String half, String team, String tCode, bool isAway) {
        if (totalRuns <= 0) return;
        final halfRelays = byHalf['$num:${half == 'top' ? 0 : 1}'] ?? [];

        // atbat 단위로 그룹: [atbat, scorer1, scorer2, ...] 분리
        final groups = <List<Map>>[];
        List<Map>? curGroup;
        for (final r in halfRelays) {
          final rtype = r['type'] as int?;
          if (rtype == 13 || rtype == 23) {
            if (curGroup != null) groups.add(curGroup);
            curGroup = [r as Map];
          } else if (rtype == 14 || rtype == 24 || rtype == 31) {
            final txt = (r['title'] as String? ?? r['text'] as String? ?? '').trim();
            if (!txt.contains('홈인') && !txt.contains('득점')) continue;
            if (curGroup != null) curGroup.add(r as Map);
          }
        }
        if (curGroup != null) groups.add(curGroup);

        // 득점 발생 그룹만 — group 안에 scorers 있거나 결과 텍스트에 점수 키워드
        bool isScoringGroup(List<Map> g) {
          if (g.length > 1) return true; // scorer 있음
          final txt = (g.first['title'] as String? ?? g.first['text'] as String? ?? '');
          return txt.contains('홈런') || txt.contains('점') || txt.contains('홈인');
        }
        final scoringGroups = groups.where(isScoringGroup).toList();
        final groupCount = scoringGroups.length;

        if (groupCount == 0) {
          // fallback: relay 분리 못 함 → 전체 한 row (legacy)
          if (isAway) cumAway += totalRuns; else cumHome += totalRuns;
          items.add({'inning': num, 'half': half, 'team': team, 'teamCode': tCode,
            'cumAway': cumAway, 'cumHome': cumHome,
            'relays': halfRelays, 'isFallback': true});
          return;
        }

        // 그룹별로 runs 분배 (totalRuns / groupCount, 나머지는 마지막에 추가)
        final base = totalRuns ~/ groupCount;
        final remainder = totalRuns - base * groupCount;
        for (int i = 0; i < scoringGroups.length; i++) {
          final runs = base + (i == scoringGroups.length - 1 ? remainder : 0);
          if (isAway) cumAway += runs; else cumHome += runs;
          items.add({'inning': num, 'half': half, 'team': team, 'teamCode': tCode,
            'cumAway': cumAway, 'cumHome': cumHome,
            'relays': scoringGroups[i], 'runs': runs});
        }
      }

      splitHalf(awayR, 'top',    awayTeam, awayCode, true);
      splitHalf(homeR, 'bottom', homeTeam, homeCode, false);
    }
    if (items.isEmpty) return const SizedBox.shrink();

    // r['title'] = opt.text = "타자 : 결과" (at-bat description)
    // r['text']  = item.title = category label ("홈런"/"안타" etc.)
    String _atBatText(Map r) {
      final optText = (r['title'] as String? ?? '').trim();
      if (optText.isNotEmpty) return optText;
      return (r['text'] as String? ?? '').trim();
    }



    ({String batter, String result}) _parsePlay(String raw) {
      if (raw.contains(' : ')) {
        final idx = raw.indexOf(' : ');
        return (batter: raw.substring(0, idx).trim(), result: raw.substring(idx + 3).trim());
      }
      return (batter: '', result: raw);
    }

    // 텍스트 추출: 모든 RBI 타석 + 홈인 정보 (line1 batter+result / line2 홈인)
    List<String> _extractLines(List halfRelays) {
      final lines = <String>[];
      String? curAtBat;
      for (final r in halfRelays) {
        final rtype = r['type'] as int?;
        if (rtype == 13 || rtype == 23) {
          if (curAtBat != null) lines.add(curAtBat);
          final raw = (r['title'] as String? ?? r['text'] as String? ?? '').trim();
          if (raw.isEmpty) { curAtBat = null; continue; }
          curAtBat = raw.contains(' : ')
              ? raw.split(' : ').map((s) => s.trim()).join(' ')
              : raw;
        } else if (rtype == 14 || rtype == 24 || rtype == 31) {
          final txt = (r['title'] as String? ?? r['text'] as String? ?? '').trim();
          if (txt.contains('홈인') || txt.contains('득점')) {
            if (curAtBat != null) {
              lines.add('$curAtBat\n  └ $txt');
              curAtBat = null;
            } else {
              lines.add(txt);
            }
          }
        }
      }
      if (curAtBat != null) lines.add(curAtBat);
      return lines.isEmpty ? ['득점'] : lines;
    }

    final halfCards = items.asMap().entries.map((entry) {
      final idx = entry.key;
      final item = entry.value;
      final isLast = idx == items.length - 1;
      final ing = item['inning'] as int;
      final half = item['half'] as String;
      final teamCode = item['teamCode'] as String;
      final cumAway = item['cumAway'] as int;
      final cumHome = item['cumHome'] as int;
      final halfRelays = item['relays'] as List;
      final halfLabel = half == 'top' ? '초' : '말';

      // Group events: each at-bat + its subsequent홈인 runners
      final plays = <({Map? atbat, List<Map> scorers})>[];
      Map? curAtBat;
      var curScorers = <Map>[];

      void flushPlay() {
        if (curAtBat != null || curScorers.isNotEmpty) {
          plays.add((atbat: curAtBat, scorers: List.from(curScorers)));
        }
        curAtBat = null;
        curScorers = [];
      }

      for (final r in halfRelays) {
        final rtype = r['type'] as int?;
        if (rtype == 13 || rtype == 23) {
          if (curAtBat != null) flushPlay();
          curAtBat = r as Map;
        } else if (rtype == 14 || rtype == 24 || rtype == 31) {
          final txt = (r['title'] as String? ?? r['text'] as String? ?? '').trim();
          if (!txt.contains('홈인') && !txt.contains('득점')) continue;
          curScorers.add(r as Map);
        }
      }
      flushPlay();

      // Build play rows
      final playWidgets = <Widget>[];
      for (final play in plays) {
        final atbat = play.atbat;
        final scorers = play.scorers;

        bool showAtBat = false;
        String batter = '';
        String result = '';
        String pitcher = '';
        Color playColor = Colors.orange;
        IconData playIcon = Icons.people_alt_outlined;

        if (atbat != null) {
          pitcher = (atbat['pitcher_name'] as String? ?? '').trim();
          final txt = _atBatText(atbat);
          if (txt.isNotEmpty) {
            final parsed = _parsePlay(txt);
            result = parsed.result;
            batter = parsed.batter.isNotEmpty
                ? parsed.batter
                : (atbat['batter_name'] as String? ?? '');
            final isHR = result.contains('홈런');
            showAtBat = isHR || scorers.isNotEmpty;
            playColor = isHR ? Colors.deepOrange : Colors.orange;
            playIcon = isHR ? Icons.sports_baseball : Icons.people_alt_outlined;
          } else if (scorers.isNotEmpty) {
            batter = (atbat['batter_name'] as String? ?? '').trim();
            showAtBat = batter.isNotEmpty;
          }
        }

        if (!showAtBat && scorers.isEmpty) continue;

        final onSurface = Theme.of(context).colorScheme.onSurface;
        playWidgets.add(Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showAtBat) Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(playIcon, size: 14, color: playColor),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            style: TextStyle(fontSize: 12, color: onSurface, height: 1.4),
                            children: [
                              if (batter.isNotEmpty) ...[
                                TextSpan(text: batter, style: const TextStyle(fontWeight: FontWeight.bold)),
                                const TextSpan(text: '  '),
                              ],
                              if (result.isNotEmpty)
                                TextSpan(text: result, style: TextStyle(color: playColor, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        if (pitcher.isNotEmpty)
                          Text(
                            '투수: $pitcher',
                            style: TextStyle(fontSize: 11, color: onSurface.withOpacity(0.48)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              for (final s in scorers)
                Padding(
                  padding: EdgeInsets.only(left: showAtBat ? 19.0 : 0.0, top: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_run, size: 12, color: Colors.teal),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          (s['title'] as String? ?? s['text'] as String? ?? '').trim(),
                          style: const TextStyle(fontSize: 11, color: Colors.teal),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ));
      }

      // mockup row: [이닝chip][logo][txt][score badge]
      // isHome ? row : row-reverse (홈 좌측, 원정 우측 정렬)
      final isHome = half == 'bottom';
      final isDarkS = Theme.of(context).brightness == Brightness.dark;
      final inkS  = isDarkS ? const Color(0xFFF4F4F5) : const Color(0xFF111113);
      final ink2S = isDarkS ? const Color(0xFFC9C9D1) : const Color(0xFF3F3F46);
      final ink3S = isDarkS ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
      final paper2S = isDarkS ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6);

      final lines = _extractLines(halfRelays);
      final txt = lines.join('\n');
      // 점수 형식: 홈:원정 누적 (예: '2:0')
      final scoreText = '$cumHome:$cumAway';

      final inningChip = Container(
        width: 28, height: 22,
        decoration: BoxDecoration(color: paper2S, borderRadius: BorderRadius.circular(5)),
        alignment: Alignment.center,
        child: Text('$ing$halfLabel',
            style: TextStyle(fontSize: 10, color: ink3S, fontWeight: FontWeight.w700)),
      );

      final logo = TeamLogo(teamCode: teamCode, size: 20);

      final txtWidget = Flexible(
        child: Text(txt,
            style: TextStyle(fontSize: 12, color: ink2S, fontWeight: FontWeight.w600, height: 1.3),
            textAlign: isHome ? TextAlign.left : TextAlign.right,
            maxLines: 10, overflow: TextOverflow.ellipsis),
      );

      final scoreBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: paper2S, borderRadius: BorderRadius.circular(6)),
        child: Text(scoreText,
            style: TextStyle(fontSize: 12, color: inkS, fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()])),
      );

      final rowChildren = isHome
          ? [inningChip, const SizedBox(width: 8), logo, const SizedBox(width: 8), txtWidget, const SizedBox(width: 8), scoreBadge]
          : [scoreBadge, const SizedBox(width: 8), txtWidget, const SizedBox(width: 8), logo, const SizedBox(width: 8), inningChip];

      final isDarkRow = Theme.of(context).brightness == Brightness.dark;
      final lineRow = isDarkRow ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: isLast ? null : Border(bottom: BorderSide(color: lineRow, width: 1)),
        ),
        // away: mainAxisAlignment.end로 오른쪽 가장자리부터 cluster 시작
        child: Row(
          mainAxisAlignment: isHome ? MainAxisAlignment.start : MainAxisAlignment.end,
          children: rowChildren,
        ),
      );
    }).toList();

    final isDarkS = Theme.of(context).brightness == Brightness.dark;
    final inkS  = isDarkS ? const Color(0xFFF4F4F5) : const Color(0xFF111113);
    final ink3S = isDarkS ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    final paperS = isDarkS ? const Color(0xFF18181C) : Colors.white;
    final lineS  = isDarkS ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _scoringExpanded = !_scoringExpanded),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
            child: Row(
              children: [
                Text('득점 요약',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: inkS, letterSpacing: -0.2)),
                const Spacer(),
                Icon(
                  _scoringExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 18, color: ink3S,
                ),
              ],
            ),
          ),
        ),
        if (_scoringExpanded)
          Container(
            decoration: BoxDecoration(
              color: paperS,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: lineS, width: 1),
            ),
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
            child: Column(children: halfCards),
          ),
      ],
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
        color: isHeader ? const Color(0xFF111113) : Colors.transparent,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E4))),
      ),
      child: Row(
        children: [
          Container(
            width: teamColWidth,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Color(0xFFE0E0E4))),
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
                      right: BorderSide(color: Color(0xFFEDEDF0))),
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
                            ? const Color(0xFF111113)
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

  Widget _buildLineupTab() {
    return IndexedStack(
      index: _lineupSubIndex,
      children: [
        _buildPreviewTab(),
        _buildRosterTab(),
      ],
    );
  }

  Widget _buildStatsTab(List pitchers, List batters) {
    return IndexedStack(
      index: _statsSubIndex,
      children: [
        _buildPitchersTab(pitchers),
        _buildBattersTab(batters),
        _buildRecordDetailTab(),
      ],
    );
  }

  Widget _buildGameFloatingNav() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final idx = _tabController.index;
    final activeColor = isDark ? const Color(0xFFF4F4F5) : const Color(0xFF111113);
    final inactiveColor = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final pillBg = isDark ? const Color(0xFF18181C) : Colors.white;
    final borderColor = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);

    BoxDecoration pillDeco() => BoxDecoration(
      color: pillBg,
      borderRadius: BorderRadius.circular(28),
      boxShadow: [BoxShadow(
        color: isDark ? Colors.black54 : Colors.black.withValues(alpha: 0.08),
        blurRadius: 16, offset: const Offset(0, 4),
      )],
      border: Border.all(color: borderColor, width: 1),
    );

    List<String>? subLabels;
    int subIdx = 0;
    void Function(int) onSubTap = (_) {};
    if (idx == 1) {
      subLabels = ['키플레이어', '로스터'];
      subIdx = _lineupSubIndex;
      onSubTap = (i) => setState(() => _lineupSubIndex = i);
    } else if (idx == 2) {
      subLabels = ['투수', '타자', '상대'];
      subIdx = _statsSubIndex;
      onSubTap = (i) => setState(() => _statsSubIndex = i);
    }

    const mainLabels = ['중계', '라인업', '기록', '하이라이트'];
    const mainIcons = [
      Icons.live_tv_outlined,
      Icons.people_outline,
      Icons.bar_chart,
      Icons.video_library_outlined,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (subLabels != null) ...[
          Container(
            height: 36,
            decoration: pillDeco(),
            child: Row(
              children: List.generate(subLabels!.length, (i) {
                final sel = i == subIdx;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSubTap(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      decoration: BoxDecoration(
                        color: sel ? activeColor.withOpacity(0.12) : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: Text(
                          subLabels![i],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                            color: sel ? activeColor : inactiveColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Container(
          height: 52,
          decoration: pillDeco(),
          child: Row(
            children: List.generate(mainLabels.length, (i) {
              final sel = i == idx;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _tabController.animateTo(i);
                    setState(() {});
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: sel ? activeColor.withOpacity(0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(mainIcons[i], size: 18, color: sel ? activeColor : inactiveColor),
                        const SizedBox(height: 1),
                        Text(
                          mainLabels[i],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                            color: sel ? activeColor : inactiveColor,
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

  Widget _buildPreviewTab() {
    if (_gameData!['game']['status'] == '예정') {
      return const Center(child: Text('경기 시작 후 확인할 수 있습니다'));
    }
    if (_previewData == null) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF111113), strokeWidth: 2.5));
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
                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0)),
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
                          color: Color(0xFF111113))),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink   = isDark ? const Color(0xFFF4F4F5) : const Color(0xFF111113);
    final ink2  = isDark ? const Color(0xFFC9C9D1) : const Color(0xFF3F3F46);
    final ink3  = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    final sub   = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final paper = isDark ? const Color(0xFF18181C) : Colors.white;
    final paper2= isDark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6);
    final line  = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
    final track = isDark ? const Color(0xFF2C2C33) : const Color(0xFFE8E8EC);

    if (starter == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: paper, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: line, width: 1),
        ),
        child: Text('$teamName 선발 미정',
            style: TextStyle(color: ink3, fontWeight: FontWeight.w600)),
      );
    }

    final season = starter['season_stats'] as Map<String, dynamic>? ?? {};
    final vs = starter['vs_stats'] as Map<String, dynamic>? ?? {};
    final pitchKinds = starter['pitch_kinds'] as List? ?? [];
    final playerId = _getPlayerIdByName(starter['name'] as String?);

    return GestureDetector(
      onTap: playerId != null ? () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: playerId))) : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: paper, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: line, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(teamName, style: TextStyle(fontSize: 11, color: sub, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(starter['name'] ?? '',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: ink, letterSpacing: -0.2)),
            Text(starter['hit_type'] ?? '',
                style: TextStyle(fontSize: 11, color: ink3, fontWeight: FontWeight.w600)),
            Container(height: 1, color: line, margin: const EdgeInsets.symmetric(vertical: 10)),
            Text('시즌 성적',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ink3, letterSpacing: 0.3)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12, runSpacing: 4,
              children: [
                _statChip('평자', '${season['era'] ?? '-'}'),
                _statChip('${season['wins'] ?? 0}승 ${season['losses'] ?? 0}패', ''),
                _statChip('이닝', season['innings'] ?? '-'),
                _statChip('삼진', '${season['kk'] ?? 0}'),
                _statChip('볼넷', '${season['bb'] ?? 0}'),
              ],
            ),
            if (vs['games'] != null && vs['games'] != '0') ...[
              const SizedBox(height: 10),
              Text('상대 성적',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ink3, letterSpacing: 0.3)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12, runSpacing: 4,
                children: [
                  _statChip('평자', '${vs['era'] ?? '-'}'),
                  _statChip('이닝', vs['innings'] ?? '-'),
                  _statChip('삼진', '${vs['kk'] ?? 0}'),
                ],
              ),
            ],
            if (pitchKinds.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('구종 비율',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ink3, letterSpacing: 0.3)),
              const SizedBox(height: 6),
              ...pitchKinds.map((pk) {
                final typeName = _pitchTypeMap[pk['type']] ?? pk['type'] ?? '';
                final ratio = (pk['ratio'] as num?)?.toStringAsFixed(1) ?? '-';
                final speed = pk['speed'] ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 60,
                          child: Text(typeName, style: TextStyle(fontSize: 11, color: ink2, fontWeight: FontWeight.w600))),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: (pk['ratio'] as num? ?? 0) / 100,
                            backgroundColor: track,
                            valueColor: AlwaysStoppedAnimation(ink),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('$ratio% ${speed}km',
                          style: TextStyle(fontSize: 11, color: sub, fontWeight: FontWeight.w600,
                              fontFeatures: const [FontFeature.tabularFigures()])),
                    ],
                  ),
                );
              }),
            ],
            // unused: paper2 (keep for consistency)
            if (paper2 == paper2) const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopPlayerCard(Map<String, dynamic>? top, String teamName) {
    if (top == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink   = isDark ? const Color(0xFFF4F4F5) : const Color(0xFF111113);
    final ink2  = isDark ? const Color(0xFFC9C9D1) : const Color(0xFF3F3F46);
    final ink3  = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    final sub   = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final paper = isDark ? const Color(0xFF18181C) : Colors.white;
    final line  = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);

    final season = top['season_stats'] as Map<String, dynamic>? ?? {};
    final game = top['game_stats'] as Map<String, dynamic>? ?? {};
    final results = (game['result'] as String? ?? '')
        .split('|')
        .where((s) => s.isNotEmpty)
        .toList();
    final playerId = _getPlayerIdByName(top['name'] as String?);

    return GestureDetector(
      onTap: playerId != null ? () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: playerId))) : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: paper, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: line, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(teamName, style: TextStyle(fontSize: 11, color: sub, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(top['name'] ?? '',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: ink, letterSpacing: -0.2)),
            Container(height: 1, color: line, margin: const EdgeInsets.symmetric(vertical: 10)),
            Text('시즌 성적',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ink3, letterSpacing: 0.3)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12, runSpacing: 4,
              children: [
                _statChip('타율', '${season['avg'] ?? '-'}'),
                _statChip('홈런', '${season['hr'] ?? 0}'),
                _statChip('타점', '${season['rbi'] ?? 0}'),
                _statChip('출루율', '${season['obp'] ?? '-'}'),
              ],
            ),
            if (results.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('이번 경기',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ink3, letterSpacing: 0.3)),
              const SizedBox(height: 6),
              Text(
                '${game['ab'] ?? 0}타수 ${game['hit'] ?? 0}안타 ${game['hr'] ?? 0}홈런 ${game['rbi'] ?? 0}타점',
                style: TextStyle(fontSize: 12, color: ink2, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 5, runSpacing: 4,
                children: results
                    .map((r) {
                      final isHit = r.contains('안타') || r.contains('홈런');
                      final isOut = r.contains('삼진') || r.contains('아웃');
                      final c = isHit ? const Color(0xFF16A34A)
                               : isOut ? const Color(0xFFE53935)
                               : ink3;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(r,
                            style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w700)),
                      );
                    })
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  int? _getPlayerIdByName(String? name) {
    if (name == null || _rosterData == null) return null;
    for (final side in ['home', 'away']) {
      for (final type in ['batters', 'pitchers']) {
        final list = (_rosterData![side][type] as List?) ?? [];
        for (final p in list) {
          if ((p as Map)['name'] == name) return p['player_id'] as int?;
        }
      }
    }
    return null;
  }

  Widget _statChip(String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF4F4F5) : const Color(0xFF111113);
    final sub = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: sub, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ink,
            fontFeatures: const [FontFeature.tabularFigures()], letterSpacing: -0.2)),
      ],
    );
  }

  Widget _buildRosterTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF4F4F5) : const Color(0xFF111113);
    final sub = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    if (_rosterData == null) {
      return Center(child: CircularProgressIndicator(color: ink, strokeWidth: 2.5));
    }

    final homeTeam = _gameData!['game']['home_team'];
    final awayTeam = _gameData!['game']['away_team'];

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            indicatorColor: ink,
            indicatorWeight: 2.5,
            labelColor: ink,
            unselectedLabelColor: sub,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: -0.1),
            unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            dividerColor: Colors.transparent,
            tabs: [Tab(text: homeTeam), Tab(text: awayTeam)],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildTeamRoster(
                  _rosterData!['home'],
                  fallbackStarterName: _previewData?['home_starter']?['name'] as String?,
                ),
                _buildTeamRoster(
                  _rosterData!['away'],
                  fallbackStarterName: _previewData?['away_starter']?['name'] as String?,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamRoster(Map<String, dynamic> teamData, {String? fallbackStarterName}) {
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

    Map<String, dynamic> starterPitcher = pitchers.cast<Map<String, dynamic>>().firstWhere(
          (p) => p['is_starter'] == true,
          orElse: () => <String, dynamic>{},
        );

    // is_starter가 null로 클리어된 경우 preview 데이터의 선발투수명으로 fallback
    if (starterPitcher.isEmpty && fallbackStarterName != null) {
      starterPitcher = pitchers.cast<Map<String, dynamic>>().firstWhere(
            (p) => p['name'] == fallbackStarterName,
            orElse: () => <String, dynamic>{},
          );
    }

    // is_starter=null 투수도 불펜에 표시 (라인업 공개 시 null 처리 대응)
    final bullpen = pitchers.where((p) => p['is_starter'] != true).toList();
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

    final vp = MediaQuery.of(context).viewPadding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 120 + vp),
      children: [
        _rosterSectionHeader('선발'),
        const SizedBox(height: 8),
        if (starterPitcher.isNotEmpty)
          InkWell(
            onTap: starterPitcher['player_id'] != null ? () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: starterPitcher['player_id'] as int))) : null,
            child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.05),
              border: Border(bottom: BorderSide(color: Color(0xFFEDEDF0))),
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
                        ? CachedNetworkImageProvider(starterPitcher['profile_image'])
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
                            fontSize: 11,
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
                b['number'],
                playerId: b['player_id'] as int?)),
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
                          p['number'],
                          playerId: p['player_id'] as int?)),
                  ]),
        ],
      ],
    );
  }

  Widget _rosterSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF111113),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
    );
  }

  Widget _rosterStatusBadge(String name) {
    final status = _playerRosterStatus[name];
    if (status == null) return const SizedBox.shrink();
    Color color;
    String label;
    if (status.contains('말소')) {
      color = Colors.orange;
      label = '말소';
    } else if (status.contains('부상')) {
      color = Colors.red;
      label = '부상';
    } else if (status.contains('등록')) {
      color = Colors.blue;
      label = '1군';
    } else {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
    );
  }

  Widget _starterBatterTile(Map<String, dynamic> b) {
    final name = b['name'] as String? ?? '';
    final playerId = b['player_id'] as int?;
    return InkWell(
      onTap: playerId != null ? () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: playerId))) : null,
      child: ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: b['profile_image'] != null
                ? CachedNetworkImageProvider(b['profile_image'])
                : null,
            child: b['profile_image'] == null
                ? const Icon(Icons.person, size: 18)
                : null,
          ),
          const SizedBox(width: 6),
          CircleAvatar(
            radius: 12,
            backgroundColor: const Color(0xFF111113),
            child: Text('${(b['batting_order'] as num).toInt()}',
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      title: Row(
        children: [
          Text('$name (#${b['number'] ?? '-'})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          _rosterStatusBadge(name),
        ],
      ),
      subtitle: Text(b['position'] ?? '',
          style: TextStyle(fontSize: 12, color: Colors.grey[500])),
    ),
    );
  }

  Widget _backupPlayerTile(
      String name, String subtitle, String? profileImage, dynamic number, {int? playerId}) {
    return InkWell(
      onTap: playerId != null ? () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: playerId))) : null,
      child: ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: CircleAvatar(
        radius: 18,
        backgroundImage: profileImage != null ? CachedNetworkImageProvider(profileImage) : null,
        child: profileImage == null ? const Icon(Icons.person, size: 18) : null,
      ),
      title: Row(
        children: [
          Text('$name (#${number ?? '-'})',
              style: const TextStyle(fontSize: 14)),
          _rosterStatusBadge(name),
        ],
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[500]))
          : null,
    ),
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
                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (winPitcher.isNotEmpty)
                    _resultSummary('승', winPitcher['name'], Colors.blue, imageUrl: winPitcher['profile_image'] as String?),
                  if (losePitcher.isNotEmpty)
                    _resultSummary('패', losePitcher['name'], Colors.red, imageUrl: losePitcher['profile_image'] as String?),
                  if (savePitcher.isNotEmpty)
                    _resultSummary('세이브', savePitcher['name'], Colors.green, imageUrl: savePitcher['profile_image'] as String?),
                ],
              ),
            ),
          TabBar(
            indicatorColor: const Color(0xFF111113),
            indicatorWeight: 2.5,
            labelColor: const Color(0xFF111113),
            unselectedLabelColor: Colors.grey,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
            dividerColor: Colors.transparent,
            tabs: [Tab(text: homeTeam), Tab(text: awayTeam)],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildPitcherList(homePitchers),
                _buildPitcherList(awayPitchers),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12 + MediaQuery.of(context).viewPadding.bottom + 116),
            child: OutlinedButton.icon(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                builder: (_) => PitchLocationSheet(
                  gameId: widget.gameId,
                  gameStatus: _gameData?['game']['status'] as String? ?? '종료',
                ),
              ),
              icon: const Icon(Icons.sports_baseball, size: 16),
              label: const Text('투구 위치 보기'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPitcherList(List pitchers) {
    final navBottom = 16.0 + MediaQuery.of(context).viewPadding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, navBottom),
      children: pitchers.map((p) {
        final pm = p as Map<String, dynamic>;
        final playerId = pm['player_id'] as int?;
        if (playerId == null) return _pitcherTile(pm);
        return InkWell(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: playerId))),
          child: _pitcherTile(pm),
        );
      }).toList(),
    );
  }

  Widget _resultSummary(String label, String name, Color color, {String? imageUrl}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        const SizedBox(height: 6),
        CircleAvatar(
          radius: 22,
          backgroundColor: color.withValues(alpha: 0.1),
          backgroundImage: imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
          child: imageUrl == null ? Icon(Icons.person, size: 22, color: color) : null,
        ),
        const SizedBox(height: 4),
        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
        border: Border(bottom: BorderSide(color: Color(0xFFEDEDF0))),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: CircleAvatar(
          radius: 20,
          backgroundImage: profileImage != null ? CachedNetworkImageProvider(profileImage) : null,
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_formatInnings(p['innings_pitched'])}이닝  자책 ${p['earned_runs']}  실점 ${p['runs_allowed'] ?? p['earned_runs']}  삼진 ${p['strikeouts']}  사사구 ${p['walks'] ?? 0}',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            () {
              final strikes = (p['strikes'] as num?)?.toInt() ?? 0;
              final balls = (p['balls'] as num?)?.toInt() ?? 0;
              final total = strikes + balls;
              if (total == 0) return const SizedBox.shrink();
              final strikePct = (strikes / total * 100).round();
              return Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 10,
                        child: Row(
                          children: [
                            Expanded(
                              flex: strikes,
                              child: Container(color: Colors.red[400]),
                            ),
                            Expanded(
                              flex: balls,
                              child: Container(color: Colors.blue[400]),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(width: 7, height: 7,
                            decoration: BoxDecoration(color: Colors.red[400], shape: BoxShape.circle)),
                        const SizedBox(width: 3),
                        Text('스트라이크 $strikePct% ($strikes)',
                            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                        const SizedBox(width: 10),
                        Container(width: 7, height: 7,
                            decoration: BoxDecoration(color: Colors.blue[400], shape: BoxShape.circle)),
                        const SizedBox(width: 3),
                        Text('볼 ${100 - strikePct}% ($balls)',
                            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      ],
                    ),
                  ],
                ),
              );
            }(),
            if (_pitchTypesData != null) ...[
              () {
                final pitcherName = p['name'] as String? ?? '';
                final types = (_pitchTypesData!['pitchers'] as Map<String, dynamic>?)
                    ?[pitcherName] as List?;
                if (types == null || types.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 12,
                          child: Row(
                            children: types.map<Widget>((t) {
                              final typeStr = t['type'] as String? ?? '';
                              final color = _pitchColor(_pitchTypeMap[typeStr] ?? typeStr);
                              return Expanded(
                                flex: t['pct'] as int? ?? 1,
                                child: Container(color: color),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        runSpacing: 3,
                        children: types.map<Widget>((t) {
                          final typeStr = t['type'] as String? ?? '';
                          final korName = _pitchTypeMap[typeStr] ?? typeStr;
                          final color = _pitchColor(korName);
                          final pct = t['pct'] as int? ?? 0;
                          final count = t['count'] as int? ?? 0;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 8, height: 8,
                                  decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                              const SizedBox(width: 3),
                              Text(korName,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 3),
                              Text('$pct% ($count구)',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                            ],
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              }(),
            ],
          ],
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
          TabBar(
            indicatorColor: const Color(0xFF111113),
            indicatorWeight: 2.5,
            labelColor: const Color(0xFF111113),
            unselectedLabelColor: Colors.grey,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
            dividerColor: Colors.transparent,
            tabs: [Tab(text: homeTeam), Tab(text: awayTeam)],
          ),
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

    final bNavBottom = 120.0 + MediaQuery.of(context).viewPadding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bNavBottom),
      children: sortedKeys.expand((order) {
        final players = grouped[order]!;
        return players.asMap().entries.map((entry) {
          final i = entry.key;
          final b = entry.value;
          final isFirst = i == 0;
          final isLast = i == players.length - 1;
          final pos = _convertPosition(b['position']);
          final profileImage = profileImages[b['name']];
          final batterId = b['player_id'] as int?;

          return InkWell(
            onTap: batterId != null ? () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: batterId))) : null,
            child: Container(
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Color(isLast ? 0xFFE0E0E4 : 0xFFEDEDF0),
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
                        profileImage != null ? CachedNetworkImageProvider(profileImage) : null,
                    child: profileImage == null
                        ? const Icon(Icons.person, size: 18)
                        : null,
                  ),
                  const SizedBox(width: 6),
                  isFirst
                      ? CircleAvatar(
                          radius: 12,
                          backgroundColor: const Color(0xFF111113),
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
                                      fontSize: 11, color: Colors.grey[500])),
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
                        color: Color(0xFFEDEDF0),
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
          ),
          );
        }).toList();
      }).toList(),
    );
  }

  Widget _buildRecordDetailTab() {
    if (_recordDetailData == null) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF111113), strokeWidth: 2.5));
    }

    final keyStats = _recordDetailData!['key_stats'] as Map<String, dynamic>? ?? {};
    final teamPitching = _recordDetailData!['team_pitching'] as Map<String, dynamic>? ?? {};
    final etcRecords = _recordDetailData!['etc_records'] as List? ?? [];
    final homeTeam = _gameData!['game']['home_team'];
    final awayTeam = _gameData!['game']['away_team'];

    final rdNavBottom = 120.0 + MediaQuery.of(context).viewPadding.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, rdNavBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rosterSectionHeader('주요 기록'),
          const SizedBox(height: 12),
          Table(
            border: TableBorder.all(color: Color(0xFFE0E0E4)),
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1.5),
              2: FlexColumnWidth(1.5),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFF111113)),
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
            border: TableBorder.all(color: Color(0xFFE0E0E4)),
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1.5),
              2: FlexColumnWidth(1.5),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFF111113)),
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
                      bottom: BorderSide(color: Color(0xFFEDEDF0))),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(type,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFF4F4F5) : const Color(0xFF111113))),
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

  Future<void> _openYouTube(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final isYT = url.contains('youtube.com') || url.contains('youtu.be');
    // 1) YouTube 앱이 https URL을 가로채도록 시도
    if (isYT) {
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
        if (ok) return;
      } catch (_) {}
      // 2) vnd.youtube:VIDEO_ID (콜론만, 슬래시 X)
      final m = RegExp(r'(?:v=|/shorts/|youtu\.be/)([A-Za-z0-9_-]{11})').firstMatch(url);
      final vid = m?.group(1);
      if (vid != null) {
        try {
          final appUri = Uri.parse('vnd.youtube:$vid');
          final ok = await launchUrl(appUri, mode: LaunchMode.externalNonBrowserApplication);
          if (ok) return;
        } catch (_) {}
      }
    }
    // 3) fallback: 외부 브라우저
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Widget _buildHighlightsTab() {
    final isDarkT = Theme.of(context).brightness == Brightness.dark;
    final ink   = isDarkT ? const Color(0xFFF4F4F5) : const Color(0xFF111113);
    final ink3  = isDarkT ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    final sub   = isDarkT ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final paper = isDarkT ? const Color(0xFF18181C) : Colors.white;
    final paper2= isDarkT ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6);
    final line  = isDarkT ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
    if (_highlightsLoading) {
      return Center(child: CircularProgressIndicator(color: ink, strokeWidth: 2.5));
    }
    if (_highlights.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_outlined, size: 48, color: sub),
            const SizedBox(height: 8),
            Text('하이라이트가 없습니다', style: TextStyle(color: ink3, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 16, 16, 90 + MediaQuery.of(context).viewPadding.bottom),
      itemCount: _highlights.length,
      itemBuilder: (context2, idx) {
        final h = _highlights[idx] as Map<String, dynamic>;
        final title = h['title'] as String? ?? '';
        final url = h['url'] as String? ?? '';
        final thumbnail = h['thumbnail'] as String? ?? '';
        final isShorts = url.contains('/shorts/');

        return GestureDetector(
          onTap: () async {
            await _openYouTube(url);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: paper,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: line, width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (thumbnail.isNotEmpty)
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      CachedNetworkImage(
                        imageUrl: thumbnail,
                        width: double.infinity,
                        height: isShorts ? 180 : 140,
                        fit: isShorts ? BoxFit.contain : BoxFit.cover,
                        placeholder: (_, __) => Container(
                          height: isShorts ? 180 : 140,
                          color: paper2,
                        ),
                        errorWidget: (_, __, ___) => Container(
                          height: isShorts ? 180 : 140,
                          color: paper2,
                          child: Icon(Icons.broken_image, color: sub),
                        ),
                      ),
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
                      ),
                      if (isShorts)
                        Positioned(
                          top: 10, right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE53935),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text('Shorts',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                        ),
                    ],
                  )
                else
                  Container(
                    height: 80,
                    color: paper2,
                    child: Center(child: Icon(Icons.play_circle_outline, color: ink3, size: 36)),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink, letterSpacing: -0.1)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}


class _GameShareSheet extends StatefulWidget {
  final Map<String, dynamic> game;
  const _GameShareSheet({required this.game});

  @override
  State<_GameShareSheet> createState() => _GameShareSheetState();
}

class _GameShareSheetState extends State<_GameShareSheet> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  Map<String, dynamic> get g => widget.game;

  Future<void> _captureAndShare() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final homeCode = g['home_team_code'] as String? ?? '';
      final awayCode = g['away_team_code'] as String? ?? '';
      final homeUrl = kTeamLogoUrls[homeCode];
      final awayUrl = kTeamLogoUrls[awayCode];
      final winImgUrl = g['win_pitcher_image'] as String?;
      final loseImgUrl = g['lose_pitcher_image'] as String?;
      // precache all images via CachedNetworkImage so they render in RepaintBoundary
      if (homeUrl != null && mounted) await precacheImage(CachedNetworkImageProvider(homeUrl), context);
      if (awayUrl != null && mounted) await precacheImage(CachedNetworkImageProvider(awayUrl), context);
      if (winImgUrl != null && mounted) await precacheImage(CachedNetworkImageProvider(winImgUrl), context);
      if (loseImgUrl != null && mounted) await precacheImage(CachedNetworkImageProvider(loseImgUrl), context);
      // wait 2 frames so CachedNetworkImage finishes decoding + layout
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/playball_game.png');
      await file.writeAsBytes(bytes);
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(file.path)],
        text: _buildText(),
      );
    } catch (e) {
      _shareText();
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _shareText() {
    // ignore: deprecated_member_use
    Share.share(_buildText());
  }

  String _buildText() {
    final status = g['status'] as String? ?? '';
    final hs = g['home_score'] ?? 0;
    final as_ = g['away_score'] ?? 0;
    final date = (g['game_date'] ?? '').toString();
    if (status == '종료') {
      return '⚾ [KBO 2026] ${g['home_team']} $hs : $as_ ${g['away_team']}\n'
          '📅 $date | ${g['stadium'] ?? ''}\nPlayBall 앱에서 확인하세요';
    } else if (status == '진행') {
      return '⚾ [KBO 진행중] ${g['home_team']} $hs : $as_ ${g['away_team']}\n'
          '${g['current_inning'] ?? ''}회 ${g['inning_half'] ?? ''}\nPlayBall 앱에서 확인하세요';
    }
    return '⚾ [KBO 2026] ${g['home_team']} vs ${g['away_team']}\n'
        '📅 $date ${g['start_time'] ?? ''} | ${g['stadium'] ?? ''}\nPlayBall 앱에서 확인하세요';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          RepaintBoundary(
            key: _cardKey,
            child: _buildCard(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _shareText,
                  icon: const Icon(Icons.text_fields, size: 16),
                  label: const Text('텍스트 공유'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF111113)),
                    foregroundColor: const Color(0xFF111113),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _sharing ? null : _captureAndShare,
                  icon: _sharing
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.image, size: 16),
                  label: const Text('이미지 공유'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111113),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCard() {
    final status = g['status'] as String? ?? '';
    final hs = g['home_score'] as int? ?? 0;
    final as_ = g['away_score'] as int? ?? 0;
    final homeTeam = g['home_team'] as String? ?? '';
    final awayTeam = g['away_team'] as String? ?? '';
    final homeCode = g['home_team_code'] as String? ?? '';
    final awayCode = g['away_team_code'] as String? ?? '';
    final date = (g['game_date'] ?? '').toString();
    final stadium = g['stadium'] as String? ?? '';
    final startTime = g['start_time'] as String? ?? '';
    final winPitcher = g['win_pitcher'] as String?;
    final losePitcher = g['lose_pitcher'] as String?;
    final isDraw = g['is_draw'] == true;

    Color statusColor;
    String statusLabel;
    switch (status) {
      case '종료':   statusColor = Colors.white70; statusLabel = '경기 종료'; break;
      case '진행':   statusColor = Colors.greenAccent; statusLabel = '경기 진행중'; break;
      case '취소':   statusColor = Colors.redAccent; statusLabel = '경기 취소'; break;
      case '라인업': statusColor = Colors.lightGreenAccent; statusLabel = '라인업 확정'; break;
      default:       statusColor = Colors.white70; statusLabel = '경기 예정';
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF111113), Color(0xFF283593)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              const Text('⚾', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              const Text('PlayBall  KBO 2026',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor.withOpacity(0.5)),
                ),
                child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Teams + Score
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: Column(
                  children: [
                    TeamLogo(teamCode: homeCode, size: 48),
                    const SizedBox(height: 6),
                    Text(homeTeam,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center),
                    const Text('홈', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
              Column(
                children: [
                  Text(
                    status == '예정' ? 'VS' : '$hs : $as_',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold,
                        letterSpacing: 2),
                  ),
                  if (status == '예정' && startTime.isNotEmpty)
                    Text(startTime, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
              Expanded(
                child: Column(
                  children: [
                    TeamLogo(teamCode: awayCode, size: 48),
                    const SizedBox(height: 6),
                    Text(awayTeam,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center),
                    const Text('원정', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Date + Stadium
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '📅 $date${stadium.isNotEmpty ? '  •  $stadium' : ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          // Pitcher info (종료)
          if (status == '종료') ...[
            const SizedBox(height: 10),
            if (isDraw)
              const Text('무승부', style: TextStyle(color: Colors.white70, fontSize: 12))
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (winPitcher != null)
                    _pitcherChip('승 $winPitcher', Colors.blue.shade300, imageUrl: g['win_pitcher_image'] as String?),
                  if (winPitcher != null && losePitcher != null)
                    const SizedBox(width: 8),
                  if (losePitcher != null)
                    _pitcherChip('패 $losePitcher', Colors.red.shade300, imageUrl: g['lose_pitcher_image'] as String?),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _pitcherChip(String label, Color color, {String? imageUrl}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: color.withOpacity(0.2),
            backgroundImage: imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
            child: imageUrl == null ? Icon(Icons.person, size: 11, color: color) : null,
          ),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─── Full field view widget ───────────────────────────────────────────────────

class _FullFieldView extends StatelessWidget {
  final bool base1, base2, base3, isDark;
  final Map<String, dynamic>? fieldView;

  const _FullFieldView({
    required this.base1, required this.base2, required this.base3,
    required this.isDark, this.fieldView,
  });

  // Normalized (x,y) coordinates on the field widget (0=left/top, 1=right/bottom)
  static const Map<String, Offset> _posCoords = {
    'CF': Offset(0.50, 0.09),
    'LF': Offset(0.17, 0.22),
    'RF': Offset(0.83, 0.22),
    'SS': Offset(0.36, 0.45),
    '2B': Offset(0.64, 0.45),
    '3B': Offset(0.17, 0.54),
    '1B': Offset(0.83, 0.54),
    'P':  Offset(0.50, 0.60),
    'C':  Offset(0.50, 0.90),  // 포수: 홈플레이트 뒤
    'DH': Offset(0.05, 0.92),
  };
  static const Map<String, Offset> _baseCoords = {
    'base1': Offset(0.79, 0.62),
    'base2': Offset(0.50, 0.42),
    'base3': Offset(0.21, 0.62),
    'batter': Offset(0.65, 0.82),  // 타자: 우타석 위치 (포수 오른쪽)
  };
  static const Map<String, String> _posLabel = {
    'P': '투수', 'C': '포수', '1B': '1루수', '2B': '2루수',
    'SS': '유격수', '3B': '3루수', 'LF': '좌익수', 'CF': '중견수', 'RF': '우익수', 'DH': '지명타자',
  };
  static const Map<String, String> _korToCode = {
    '투수': 'P', '포수': 'C', '1루수': '1B', '2루수': '2B',
    '유격수': 'SS', '3루수': '3B', '좌익수': 'LF', '중견수': 'CF',
    '우익수': 'RF', '지명타자': 'DH',
  };

  @override
  Widget build(BuildContext context) {
    final defense = (fieldView?['defense'] as List?)
        ?.whereType<Map<String, dynamic>>().toList() ?? [];
    final batter  = fieldView?['batter']  as Map<String, dynamic>?;
    final pitcher = fieldView?['pitcher'] as Map<String, dynamic>?;
    final runners = fieldView?['runners'] as Map<String, dynamic>?;
    final runner1 = runners?['base1'] as Map<String, dynamic>?;
    final runner2 = runners?['base2'] as Map<String, dynamic>?;
    final runner3 = runners?['base3'] as Map<String, dynamic>?;

    // Add pitcher to defense if not already included
    final hasPitcher = defense.any((p) => (p['pos_code'] as String?) == 'P' ||
        (p['position'] as String?) == '투수');
    final defenseWithPitcher = [...defense];
    if (!hasPitcher && pitcher != null) {
      defenseWithPitcher.add({...pitcher, 'pos_code': 'P', 'position': '투수'});
    }

    return LayoutBuilder(builder: (ctx, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;

      Widget placed(Offset norm, Widget child, double chipW, double chipH) {
        return Positioned(
          left: (w * norm.dx - chipW / 2).clamp(0, w - chipW),
          top:  (h * norm.dy - chipH / 2).clamp(0, h - chipH),
          child: child,
        );
      }

      final defenseWidgets = <Widget>[];
      for (final p in defenseWithPitcher) {
        final posCode = _korToCode[p['position'] as String? ?? '']
            ?? (p['pos_code'] as String? ?? '');
        final coord = _posCoords[posCode];
        if (coord == null) continue;
        final label = _posLabel[posCode] ?? posCode;
        defenseWidgets.add(placed(
          coord,
          _PlayerDot(
            name: p['name'] as String? ?? '',
            imageUrl: p['image'] as String?,
            label: label,
            isOffense: false,
            isDark: isDark,
            size: 24,
          ),
          68, 40,
        ));
      }

      Widget runnerWidget(Map<String, dynamic>? p, String baseKey, bool isOccupied) {
        final coord = _baseCoords[baseKey]!;
        final runnerName = p?['name'] as String? ?? '';
        return placed(coord,
          _PlayerDot(
            name: runnerName,
            imageUrl: p?['image'] as String?,
            label: '',
            isOffense: true,
            isDark: isDark,
            size: 26,
          ),
          68, 46,
        );
      }

      // 초기 버전: 배경 Positioned.fill + player widgets 같은 Stack 영역 (Padding 없음)
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _FieldBgPainter(
                base1: base1, base2: base2, base3: base3, isDark: isDark,
              ),
            ),
          ),
          ...defenseWidgets,
          if (base1 || runner1 != null) runnerWidget(runner1, 'base1', base1),
          if (base2 || runner2 != null) runnerWidget(runner2, 'base2', base2),
          if (base3 || runner3 != null) runnerWidget(runner3, 'base3', base3),
          if (batter != null)
            placed(
              _baseCoords['batter']!,
              _PlayerDot(
                name: batter['name'] as String? ?? '',
                imageUrl: batter['image'] as String?,
                label: '타자',
                isOffense: true,
                isDark: isDark,
                size: 26,
                isBatter: true,
              ),
              68, 40,
            ),
        ],
      );
    });
  }
}

class _PlayerDot extends StatelessWidget {
  final String name, label;
  final String? imageUrl;
  final bool isOffense, isDark, isBatter;
  final double size;

  const _PlayerDot({
    required this.name, required this.label, this.imageUrl,
    required this.isOffense, required this.isDark,
    required this.size, this.isBatter = false,
  });

  @override
  Widget build(BuildContext context) {
    // 공격=주황계열, 수비=파란계열, 타자=노랑 강조
    final Color dotColor = isBatter
        ? const Color(0xFFE65100).withOpacity(0.90)
        : isOffense
            ? const Color(0xFFBF360C).withOpacity(0.90)
            : const Color(0xFF0D47A1).withOpacity(0.90);
    final Color borderColor = isBatter
        ? Colors.yellow[300]!
        : isOffense ? Colors.orange[300]! : Colors.lightBlue[200]!;
    final Color textColor = isOffense ? Colors.orange[100]! : Colors.lightBlue[100]!;
    final Color labelBg = isOffense
        ? Colors.orange[900]!.withOpacity(0.85)
        : Colors.indigo[900]!.withOpacity(0.85);

    final displayName = name.length > 7 ? name.substring(0, 7) : name;

    return SizedBox(
      width: 68.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 라벨 (포지션 or 주자/타자) — dot 위
          if (label.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 1),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
              decoration: BoxDecoration(
                color: labelBg,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                label,
                style: TextStyle(fontSize: 7, color: textColor, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Container(
            width: size, height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
              border: Border.all(color: borderColor, width: 1.8),
              boxShadow: [BoxShadow(
                color: borderColor.withOpacity(0.5),
                blurRadius: isOffense ? 6 : 4,
                spreadRadius: 0.5,
              )],
            ),
            child: ClipOval(
              child: imageUrl != null && imageUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Icon(Icons.person, size: size * 0.55, color: Colors.white70),
                      placeholder: (_, __) => Container(color: Colors.black26),
                    )
                  : Icon(Icons.person, size: size * 0.55, color: Colors.white70),
            ),
          ),
          // 이름 — dot 아래
          if (displayName.isNotEmpty) ...[
            const SizedBox(height: 1),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.60),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                displayName,
                style: TextStyle(
                  fontSize: 8.5,
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  shadows: const [Shadow(offset: Offset(0, 1), blurRadius: 1, color: Colors.black)],
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FieldBgPainter extends CustomPainter {
  final bool base1, base2, base3, isDark;
  const _FieldBgPainter({required this.base1, required this.base2, required this.base3, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Base positions (matches _FullFieldView._baseCoords)
    final p2B   = Offset(w * 0.50, h * 0.42);
    final p3B   = Offset(w * 0.21, h * 0.62);
    final p1B   = Offset(w * 0.79, h * 0.62);
    final pHome = Offset(w * 0.50, h * 0.82);
    final pMound= Offset(w * 0.50, h * 0.62);

    // ── Outfield grass: radial gradient + 잔디 stripe (실제 mowing pattern) ──
    // 외야수 뒤 여백까지 잔디 덮음 (전체 캔버스 cover after diamond 뒤)
    final arcCenter = Offset(w * 0.50, h * 0.95);
    final arcR = w * 1.10;  // 0.78 → 1.10 (외야수 뒤 여백 cover)
    final ofPath = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    // 캔버스 전체를 잔디로 칠한 뒤 inner diamond 따로 dirt

    // 잔디 base (그라데이션: 가운데 어두운 / 가장자리 밝은)
    final grassBase = Paint()
      ..shader = ui.Gradient.radial(
        arcCenter, arcR,
        [
          const Color(0xFF4A8C3E), // 가운데 진한 잔디
          const Color(0xFF6BB05A), // 중간
          const Color(0xFF7BC068), // 가장자리 밝은
        ],
        const [0.0, 0.6, 1.0],
      );
    canvas.save();
    canvas.clipPath(ofPath);
    canvas.drawPath(ofPath, grassBase);

    // 잔디 stripe (mowing pattern) — fan-shape (홈에서 외야로 방사형)
    final stripePaint = Paint()
      ..color = Colors.black.withOpacity(0.06)
      ..strokeWidth = 1;
    for (double ang = -3.14 * 0.88; ang <= -3.14 * 0.12; ang += 3.14 * 0.04) {
      final p1 = arcCenter;
      final p2 = Offset(
        arcCenter.dx + arcR * 1.2 * math.cos(ang),
        arcCenter.dy + arcR * 1.2 * math.sin(ang),
      );
      final stripe = Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy);
      // 교차 stripe
      final ang2 = ang + 3.14 * 0.02;
      final p3 = Offset(
        arcCenter.dx + arcR * 1.2 * math.cos(ang2),
        arcCenter.dy + arcR * 1.2 * math.sin(ang2),
      );
      final fill = Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..close();
      canvas.drawPath(fill, Paint()..color = Colors.black.withOpacity(0.05));
      canvas.drawPath(stripe, stripePaint);
    }
    canvas.restore();

    // 잔디 외곽 (warning track) — 황토 띠
    final warningPaint = Paint()
      ..color = const Color(0xFFAD7B3F).withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawArc(Rect.fromCircle(center: arcCenter, radius: arcR),
        -3.14 * 0.88, 3.14 * 0.76, false, warningPaint);

    // ── Infield dirt (그라데이션: 가운데 진한, 가장자리 흐림) ──
    final infieldRect = Rect.fromCenter(
      center: Offset(w * 0.50, h * 0.62),
      width: w * 0.7, height: h * 0.45,
    );
    final dirtPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(w * 0.50, h * 0.62), w * 0.34,
        [
          const Color(0xFFA66A2A), // 가운데 진한 황토
          const Color(0xFFC8923A), // 가장자리 밝은
        ],
      );
    final diamondPath = Path()
      ..moveTo(pHome.dx, pHome.dy)
      ..lineTo(p1B.dx,   p1B.dy)
      ..lineTo(p2B.dx,   p2B.dy)
      ..lineTo(p3B.dx,   p3B.dy)
      ..close();
    canvas.drawPath(diamondPath, dirtPaint);

    // 내야 잔디 (다이아몬드 중심 사각 잔디 area)
    final infieldGrass = Paint()
      ..shader = ui.Gradient.radial(
        Offset(w * 0.50, h * 0.62), w * 0.18,
        [const Color(0xFF5FA851), const Color(0xFF4D8E42)],
      );
    final infieldGrassPath = Path()
      ..moveTo(w * 0.50, h * 0.49)
      ..lineTo(w * 0.36, h * 0.62)
      ..lineTo(w * 0.50, h * 0.75)
      ..lineTo(w * 0.64, h * 0.62)
      ..close();
    canvas.drawPath(infieldGrassPath, infieldGrass);

    // 마운드 (작은 흙 원 + 약간 옅은 가장자리)
    final moundPaint = Paint()
      ..shader = ui.Gradient.radial(
        pMound, w * 0.045,
        [const Color(0xFFB8843A), const Color(0xFFA06A2A)],
      );
    canvas.drawCircle(pMound, w * 0.045, moundPaint);
    // pitcher rubber (흰 직사각형)
    final rubberPaint = Paint()
      ..color = Colors.white.withOpacity(0.85);
    canvas.drawRect(
      Rect.fromCenter(center: pMound, width: w * 0.04, height: 2),
      rubberPaint,
    );

    // ── Baselines (흰 줄) ──
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    canvas.drawLine(pHome, p1B, linePaint);
    canvas.drawLine(pHome, p3B, linePaint);

    // ── Foul lines extended ──
    final foulPaint = Paint()
      ..color = Colors.white.withOpacity(0.55)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawLine(pHome, Offset(w * 0.0, h * 0.08), foulPaint);
    canvas.drawLine(pHome, Offset(w * 1.0, h * 0.08), foulPaint);

    // ── Bases (대각선 시점에 맞춰 살짝 누운 마름모: height 0.65x) ──
    void drawBase(Offset pos, bool occupied) {
      final bs = 8.0;
      final bh = bs * 0.65; // 대각선 시점 높이 압축
      // 그림자
      canvas.drawPath(
        Path()
          ..moveTo(pos.dx,           pos.dy - bh + 1.5)
          ..lineTo(pos.dx + bs * 1.1, pos.dy + 1.5)
          ..lineTo(pos.dx,           pos.dy + bh + 1.5)
          ..lineTo(pos.dx - bs * 1.1, pos.dy + 1.5)
          ..close(),
        Paint()..color = Colors.black.withOpacity(0.22)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
      if (occupied) {
        // 주자: 노란 글로우
        canvas.drawPath(
          Path()
            ..moveTo(pos.dx,           pos.dy - bh * 2.6)
            ..lineTo(pos.dx + bs * 2.6, pos.dy)
            ..lineTo(pos.dx,           pos.dy + bh * 2.6)
            ..lineTo(pos.dx - bs * 2.6, pos.dy)
            ..close(),
          Paint()..color = Colors.yellow.withOpacity(0.45)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
      // 베이스 본체 — 누운 마름모
      final bp = Paint()
        ..color = occupied ? const Color(0xFFFFE066) : Colors.white.withOpacity(0.95)
        ..style = PaintingStyle.fill;
      final path = Path()
        ..moveTo(pos.dx,      pos.dy - bh)
        ..lineTo(pos.dx + bs, pos.dy)
        ..lineTo(pos.dx,      pos.dy + bh)
        ..lineTo(pos.dx - bs, pos.dy)
        ..close();
      canvas.drawPath(path, bp);
      // 외곽선
      canvas.drawPath(path, Paint()
        ..color = Colors.black.withOpacity(0.25)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke);
    }
    drawBase(p1B, base1);
    drawBase(p2B, base2);
    drawBase(p3B, base3);

    // ── Home plate (대각선 시점: y 0.65x 압축) ──
    canvas.drawPath(
      Path()
        ..moveTo(pHome.dx,      pHome.dy - 3.25 + 1.5)
        ..lineTo(pHome.dx + 5,  pHome.dy - 1 + 1.5)
        ..lineTo(pHome.dx + 4,  pHome.dy + 3 + 1.5)
        ..lineTo(pHome.dx - 4,  pHome.dy + 3 + 1.5)
        ..lineTo(pHome.dx - 5,  pHome.dy - 1 + 1.5)
        ..close(),
      Paint()..color = Colors.black.withOpacity(0.22)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    final homePath = Path()
      ..moveTo(pHome.dx,      pHome.dy - 3.25)
      ..lineTo(pHome.dx + 5,  pHome.dy - 1)
      ..lineTo(pHome.dx + 4,  pHome.dy + 3)
      ..lineTo(pHome.dx - 4,  pHome.dy + 3)
      ..lineTo(pHome.dx - 5,  pHome.dy - 1)
      ..close();
    canvas.drawPath(homePath, Paint()..color = Colors.white.withOpacity(0.95));
    canvas.drawPath(homePath, Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke);

    // 배터 박스 (홈 양옆 사각형 outline)
    final batterBoxPaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawRect(
      Rect.fromCenter(center: Offset(pHome.dx - 9, pHome.dy + 1), width: 6, height: 12),
      batterBoxPaint,
    );
    canvas.drawRect(
      Rect.fromCenter(center: Offset(pHome.dx + 9, pHome.dy + 1), width: 6, height: 12),
      batterBoxPaint,
    );
  }

  @override
  bool shouldRepaint(_FieldBgPainter old) =>
      old.base1 != base1 || old.base2 != base2 || old.base3 != base3 || old.isDark != isDark;
}

// 잔디 확장 painter — outer slot 전체 grass + stripe (inner painter와 동일 center/radius 좌표 사용)
// 슬롯 padding (16/20) 영역 너머까지 gradient/stripe 자연스럽게 이어짐
class _GrassExtensionPainter extends CustomPainter {
  const _GrassExtensionPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final innerW = w - 32; // padding horizontal 16*2
    // inner painter arcCenter (= inner_w*0.5, inner_h*0.95) absolute로 매핑
    final arcCenter = Offset(w * 0.5, 20 + (h - 40) * 0.95);
    final arcR = innerW * 1.10;

    final fullPath = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    final grassBase = Paint()
      ..shader = ui.Gradient.radial(
        arcCenter, arcR,
        [
          const Color(0xFF4A8C3E),
          const Color(0xFF6BB05A),
          const Color(0xFF7BC068),
        ],
        const [0.0, 0.6, 1.0],
      );
    canvas.save();
    canvas.clipPath(fullPath);
    canvas.drawPath(fullPath, grassBase);

    // stripe (mowing pattern) — inner painter와 동일 (각도/색)
    final stripePaint = Paint()
      ..color = Colors.black.withOpacity(0.06)
      ..strokeWidth = 1;
    for (double ang = -3.14 * 0.88; ang <= -3.14 * 0.12; ang += 3.14 * 0.04) {
      final p1 = arcCenter;
      final p2 = Offset(
        arcCenter.dx + arcR * 1.2 * math.cos(ang),
        arcCenter.dy + arcR * 1.2 * math.sin(ang),
      );
      final ang2 = ang + 3.14 * 0.02;
      final p3 = Offset(
        arcCenter.dx + arcR * 1.2 * math.cos(ang2),
        arcCenter.dy + arcR * 1.2 * math.sin(ang2),
      );
      final fill = Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..close();
      canvas.drawPath(fill, Paint()..color = Colors.black.withOpacity(0.05));
      final stripe = Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy);
      canvas.drawPath(stripe, stripePaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GrassExtensionPainter old) => false;
}

class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double dashLength;
  final double gap;
  _DashedRectPainter({required this.color, required this.radius, this.dashLength = 6, this.gap = 4});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final rect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rect);
    final metrics = path.computeMetrics().toList();
    for (final m in metrics) {
      double dist = 0;
      while (dist < m.length) {
        final next = (dist + dashLength).clamp(0, m.length).toDouble();
        canvas.drawPath(m.extractPath(dist, next), paint);
        dist = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) =>
      old.color != color || old.radius != radius || old.dashLength != dashLength || old.gap != gap;
}