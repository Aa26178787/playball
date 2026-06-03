import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
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
    final homeColor = const Color(0xFF1A237E);
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
                getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 9, color: Colors.grey)),
              )),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            extraLinesData: ExtraLinesData(horizontalLines: [
              HorizontalLine(y: 50, color: Colors.grey.withOpacity(0.4), strokeWidth: 1,
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
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Expanded(child: Column(children: [
          Text(homeTeam, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${home.toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
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
          NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverToBoxAdapter(child: _buildGameHeader(game, roundedBottom: _sameDayGames.isEmpty)),
              if (_sameDayGames.isNotEmpty)
                SliverToBoxAdapter(child: _buildSameDayStrip()),
            ],
            body: TabBarView(
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradientColors = isDark
        ? [const Color(0xFF0D2818), const Color(0xFF1B3A22)]
        : [const Color(0xFF1B4332), const Color(0xFF2D6A4F)];

    return LayoutBuilder(builder: (context, constraints) {
      final screenW = constraints.maxWidth > 0
          ? constraints.maxWidth
          : MediaQuery.of(context).size.width;
      final cardW = screenW / 4;

      return ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: gradientColors,
            ),
          ),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
                onTap: isCurrent
                    ? null
                    : () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GameDetailScreen(gameId: g['id'] as int),
                          ),
                        ),
                child: Container(
                  width: cardW - 8,
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCurrent
                          ? Colors.white.withValues(alpha: 0.7)
                          : Colors.white.withValues(alpha: 0.2),
                      width: isCurrent ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TeamLogo(teamCode: awayCode, size: 22),
                          const SizedBox(width: 6),
                          TeamLogo(teamCode: homeCode, size: 22),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(scoreText,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isLive ? const Color(0xFFFF6B6B) : Colors.white,
                              )),
                          if (isLive) ...[
                            const SizedBox(width: 2),
                            Container(
                              width: 5, height: 5,
                              decoration: const BoxDecoration(color: Color(0xFFFF6B6B), shape: BoxShape.circle),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    });
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

  Widget _buildGameHeader(Map<String, dynamic> game, {bool roundedBottom = true}) {
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

    // BSO dots helper (for live bottom bar)
    Widget bsoDot(bool on, Color c) => Container(
      width: 9, height: 9,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? c : Colors.white.withValues(alpha: 0.2),
        boxShadow: on ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 4, spreadRadius: 0.5)] : null,
      ),
    );
    Widget bsoGroup(String lbl, int count, int max, Color c) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(lbl, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white60)),
        const SizedBox(width: 3),
        ...List.generate(max, (i) => bsoDot(i < count, c)),
      ],
    );

    final gradientColors = isDark
        ? [const Color(0xFF0D2818), const Color(0xFF1B3A22)]
        : [const Color(0xFF1B4332), const Color(0xFF2D6A4F)];

    String shortName(String n) => n.length > 3 ? n.substring(0, 3) : n;

    return ClipRRect(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(roundedBottom ? 16 : 0)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: gradientColors,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 스코어보드 (최상단) ──────────────────────────
            if (innings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: _buildFieldScoreOverlay(innings, game),
                ),
              ),

            // ── 스코어 바 ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 홈팀
                  Expanded(
                    child: Column(
                      children: [
                        TeamLogo(teamCode: homeCode, size: 40),
                        const SizedBox(height: 3),
                        Text(shortName(homeTeam), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        if (homeRank != null && homeRank > 0)
                          Text('${homeRank}위', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                        if (homeWinRate != null) ...[
                          const SizedBox(height: 3),
                          _buildWinRatePill(homeWinRate),
                        ],
                        if (homeRecent.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          _buildRecentBar(homeRecent, true),
                        ],
                      ],
                    ),
                  ),
                  // 스코어 중앙
                  Column(
                    children: [
                      Text(
                        isDone || isLive ? '$homeScore : $awayScore' : 'VS',
                        style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        isLive
                            ? '${game['current_inning']}회 ${game['inning_half'] ?? ''}'
                            : isDone ? '종료'
                            : status == '예정' || status == '라인업' ? (game['start_time'] as String? ?? '예정') : status,
                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                    ],
                  ),
                  // 원정팀
                  Expanded(
                    child: Column(
                      children: [
                        TeamLogo(teamCode: awayCode, size: 40),
                        const SizedBox(height: 3),
                        Text(shortName(awayTeam), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        if (awayRank != null && awayRank > 0)
                          Text('${awayRank}위', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                        if (awayWinRate != null) ...[
                          const SizedBox(height: 3),
                          _buildWinRatePill(awayWinRate),
                        ],
                        if (awayRecent.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          _buildRecentBar(awayRecent, false),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── 필드뷰 ──────────────────────────────────────
            if (fieldWidget != null)
              SizedBox(height: 190, child: fieldWidget),

            // ── 하단 바 ─────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Row(
                children: [
                  if (isLive && _relayData?['current_state'] != null) ...[
                    // LIVE 뱃지
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green[600],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 10),
                    // BSO
                    bsoGroup('B', (_relayData!['current_state']['ball'] as int? ?? 0).clamp(0, 3), 3, Colors.green[300]!),
                    const SizedBox(width: 8),
                    bsoGroup('S', (_relayData!['current_state']['strike'] as int? ?? 0).clamp(0, 2), 2, Colors.red[300]!),
                    const SizedBox(width: 8),
                    bsoGroup('O', (_relayData!['current_state']['out'] as int? ?? 0).clamp(0, 2), 2, Colors.orange[300]!),
                    const Spacer(),
                    // 새로고침
                    _isRelayRefreshing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white60))
                        : GestureDetector(
                            onTap: _refreshRelayAll,
                            child: const Icon(Icons.refresh, size: 20, color: Colors.white60),
                          ),
                  ] else if (isDone && (game['win_pitcher'] != null || game['lose_pitcher'] != null)) ...[
                    // 승투/패투
                    const Spacer(),
                    if (game['win_pitcher'] != null)
                      _pitcherBadge(game['win_pitcher'] as String, game['win_pitcher_image'] as String?, Colors.lightBlueAccent, '승'),
                    if (game['win_pitcher'] != null && game['lose_pitcher'] != null) const SizedBox(width: 20),
                    if (game['lose_pitcher'] != null)
                      _pitcherBadge(game['lose_pitcher'] as String, game['lose_pitcher_image'] as String?, Colors.redAccent, '패'),
                    const Spacer(),
                  ] else if (_weatherData != null) ...[
                    Expanded(child: Center(child: _buildWeatherRow(_weatherData!))),
                  ] else
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWinRatePill(double rate) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('승리확률 ', style: TextStyle(color: Colors.white38, fontSize: 8)),
          Text('${rate.toStringAsFixed(0)}%',
              style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildFieldScoreOverlay(List innings, Map<String, dynamic> game) {
    final awayCode = game['away_team_code'] as String? ?? '';
    final homeCode = game['home_team_code'] as String? ?? '';
    final awayShort = teamDisplayName(awayCode);
    final homeShort = teamDisplayName(homeCode);

    const hdrStyle  = TextStyle(color: Colors.white38, fontSize: 7.5, fontWeight: FontWeight.bold);
    const teamStyle = TextStyle(color: Colors.white60, fontSize: 8, fontWeight: FontWeight.w600);
    const valStyle  = TextStyle(color: Colors.white, fontSize: 9);
    final  rStyle   = const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold);
    const scoreStyle = TextStyle(color: Colors.orangeAccent, fontSize: 9, fontWeight: FontWeight.bold);

    // teamColW: fixed left column; rhbeW: fixed right section
    const teamColW = 26.0;

    Widget cell(Widget child) => Expanded(child: Center(child: child));

    Widget textCell(String t, TextStyle s) => cell(Text(t, style: s, textAlign: TextAlign.center));

    // 이닝 데이터 row builder
    Widget dataRow(String teamLabel, List<int> inningRuns, int r, int h, int b, int e) {
      return Row(children: [
        SizedBox(width: teamColW,
          child: Text(teamLabel, style: teamStyle, overflow: TextOverflow.ellipsis)),
        ...inningRuns.map((v) => cell(
          Text('$v', textAlign: TextAlign.center,
              style: v > 0 ? scoreStyle : const TextStyle(color: Colors.white38, fontSize: 9)),
        )),
        // separator
        Container(width: 1, height: 14, color: Colors.white.withValues(alpha: 0.18),
            margin: const EdgeInsets.symmetric(horizontal: 3)),
        SizedBox(width: 18, child: Center(child: Text('$r', style: rStyle, textAlign: TextAlign.center))),
        SizedBox(width: 16, child: Center(child: Text('$h', style: valStyle, textAlign: TextAlign.center))),
        SizedBox(width: 16, child: Center(child: Text('$b', style: valStyle, textAlign: TextAlign.center))),
        SizedBox(width: 16, child: Center(child: Text('$e', style: valStyle, textAlign: TextAlign.center))),
      ]);
    }

    final awayRuns = innings.map((i) => (i as Map)['away_runs'] as int? ?? 0).toList();
    final homeRuns = innings.map((i) => (i as Map)['home_runs'] as int? ?? 0).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 헤더 행
          Row(children: [
            SizedBox(width: teamColW), // 팀명 자리
            ...innings.map((i) => textCell('${(i as Map)['inning']}', hdrStyle)),
            Container(width: 1, height: 10, color: Colors.white.withValues(alpha: 0.18),
                margin: const EdgeInsets.symmetric(horizontal: 3)),
            SizedBox(width: 18, child: Center(child: const Text('R', style: hdrStyle))),
            SizedBox(width: 16, child: Center(child: const Text('H', style: hdrStyle))),
            SizedBox(width: 16, child: Center(child: const Text('B', style: hdrStyle))),
            SizedBox(width: 16, child: Center(child: const Text('E', style: hdrStyle))),
          ]),
          const SizedBox(height: 3),
          // 원정팀 행
          dataRow(awayShort, awayRuns,
            _liveScore(game, 'away_score'),
            game['away_hits']  as int? ?? 0,
            game['away_walks'] as int? ?? 0,
            game['away_errors'] as int? ?? 0,
          ),
          const SizedBox(height: 2),
          // 홈팀 행
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
      color: const Color(0xFF1A237E),
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
                  _pitcherBadge(game['win_pitcher'] as String, game['win_pitcher_image'] as String?, Colors.lightBlueAccent, '승'),
                  if (game['lose_pitcher'] != null) const SizedBox(width: 16),
                ],
                if (game['lose_pitcher'] != null)
                  _pitcherBadge(game['lose_pitcher'] as String, game['lose_pitcher_image'] as String?, Colors.redAccent, '패'),
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

  Widget _pitcherBadge(String name, String? imageUrl, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: color.withValues(alpha: 0.25),
          backgroundImage: imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
          child: imageUrl == null ? Icon(Icons.person, size: 14, color: color) : null,
        ),
        const SizedBox(width: 5),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
            Text(name, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _buildRecentBar(List<String> recent, bool isHome) {
    if (recent.isEmpty) return const SizedBox.shrink();
    final displayed = isHome ? recent.reversed.toList() : recent;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: displayed.asMap().entries.map((e) {
        final idx = e.key;
        final r = e.value;
        final isLatest = isHome ? idx == displayed.length - 1 : idx == 0;
        final c = r == 'W' ? Colors.blue : r == 'L' ? Colors.red : r == 'C' ? Colors.orange : Colors.grey;
        return Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: c.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: c.withOpacity(0.7), width: 0.8),
                ),
                alignment: Alignment.center,
                child: Text(r, style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              if (isLatest)
                const Positioned(
                  top: -3,
                  right: -1,
                  child: CircleAvatar(radius: 2.5, backgroundColor: Colors.red),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildWeatherRow(Map<String, dynamic> w) {
    if (w['indoor'] == true) {
      return const Text('실내 구장', style: TextStyle(color: Colors.white54, fontSize: 12));
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
    return Text(
      parts.join('  '),
      style: const TextStyle(color: Colors.white60, fontSize: 12),
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
      padding: EdgeInsets.fromLTRB(16, 16, 16, navBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (innings.isNotEmpty && _relayAllData != null) ...[
            _buildScoringSection(innings, awayTeam, homeTeam),
            const SizedBox(height: 8),
          ],

          if (_relayAllData == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: _buildRelayShimmer(),
            )
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

              return Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: Card(
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(batterName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            overflow: TextOverflow.ellipsis, maxLines: 1),
                      ),
                      if (pitcherName != null) ...[
                        Text(' vs ', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                        Flexible(
                          child: Text(pitcherName,
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              overflow: TextOverflow.ellipsis, maxLines: 1),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (result.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: resultColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: resultColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(result,
                        style: TextStyle(
                            fontSize: 11, color: resultColor, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis, maxLines: 1),
                  ),
                if (pitches.isNotEmpty) ...[
                  const SizedBox(width: 6),
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A237E).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF1A237E).withValues(alpha: 0.2)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.grid_on, size: 11, color: Color(0xFF1A237E)),
                          SizedBox(width: 2),
                          Text('투구위치', style: TextStyle(fontSize: 10, color: Color(0xFF1A237E))),
                        ],
                      ),
                    ),
                  ),
                ],
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

          ...pitches.asMap().entries.map((entry) {
            final r = entry.value;
            final pitchResult = r['pitch_result'] as String?;
            final speed = _speedToString(r['speed']);
            final stuff = r['stuff'] as String?;
            final pitchNum = entry.key + 1;  // 타석 내 1구부터 (누적 pitch_num 사용 안 함)
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
                    child: Text('${pitchNum}구',
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

  Widget _buildScoringSection(List innings, String awayTeam, String homeTeam) {
    final relays = _relayAllData?['relays'] as List? ?? [];
    if (relays.isEmpty) return const SizedBox.shrink();

    // Group relay events by inning + half
    final Map<String, List> byHalf = {};
    for (final r in relays) {
      final ing = r['inning'] as int? ?? 0;
      final half = r['inning_half']?.toString() ?? '0';
      byHalf.putIfAbsent('$ing:$half', () => []).add(r);
    }

    // Collect scoring half-innings
    final items = <Map<String, dynamic>>[];
    for (final inn in innings) {
      final num = inn['inning'] as int? ?? 0;
      final awayR = inn['away_runs'] as int? ?? 0;
      final homeR = inn['home_runs'] as int? ?? 0;
      if (awayR > 0) {
        items.add({'inning': num, 'half': 'top', 'runs': awayR, 'team': awayTeam,
          'relays': byHalf['$num:0'] ?? []});
      }
      if (homeR > 0) {
        items.add({'inning': num, 'half': 'bottom', 'runs': homeR, 'team': homeTeam,
          'relays': byHalf['$num:1'] ?? []});
      }
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

    final halfCards = items.map((item) {
      final ing = item['inning'] as int;
      final half = item['half'] as String;
      final runs = item['runs'] as int;
      final team = item['team'] as String;
      final halfRelays = item['relays'] as List;
      final halfLabel = half == 'top' ? '초' : '말';
      final halfColor = half == 'top' ? Colors.blue : Colors.red;

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
                            style: TextStyle(fontSize: 10, color: onSurface.withOpacity(0.48)),
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

      // Timeline row for this half-inning
      final onSurface2 = Theme.of(context).colorScheme.onSurface;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left: inning label
              SizedBox(
                width: 36,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 32,
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      decoration: BoxDecoration(
                        color: halfColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$ing회\n$halfLabel',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              // Center: vertical line
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Container(width: 1.5, color: halfColor.withValues(alpha: 0.3)),
              ),
              // Right: events
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // team + runs badge
                    Row(children: [
                      Text(team,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: onSurface2)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('+$runs점',
                            style: const TextStyle(color: Colors.deepOrange, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    if (playWidgets.isNotEmpty)
                      ...playWidgets
                    else
                      Text('상세 정보 없음', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _scoringExpanded = !_scoringExpanded),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                const Text('득점 요약', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                Icon(
                  _scoringExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 20, color: Colors.grey[600],
                ),
              ],
            ),
          ),
        ),
        if (_scoringExpanded) ...[
          const SizedBox(height: 8),
          ...halfCards,
        ],
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
    final activeColor = isDark ? const Color(0xFF7B8FFF) : AppColors.primary;
    final inactiveColor = isDark ? Colors.white38 : AppColors.textTertiary;
    final pillBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderDark : AppColors.borderLight;

    BoxDecoration pillDeco() => BoxDecoration(
      color: pillBg,
      borderRadius: BorderRadius.circular(28),
      boxShadow: [BoxShadow(
        color: isDark ? Colors.black45 : Colors.black.withOpacity(0.12),
        blurRadius: 16, offset: const Offset(0, 4),
      )],
      border: Border.all(color: borderColor, width: 0.8),
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
                            fontSize: 10,
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
      return const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E), strokeWidth: 2.5));
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
    final playerId = _getPlayerIdByName(starter['name'] as String?);

    return GestureDetector(
      onTap: playerId != null ? () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: playerId))) : null,
      child: Card(
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
                  _statChip('평자', '${season['era'] ?? '-'}'),
                  _statChip('${season['wins'] ?? 0}승 ${season['losses'] ?? 0}패', ''),
                  _statChip('이닝', season['innings'] ?? '-'),
                  _statChip('삼진', '${season['kk'] ?? 0}'),
                  _statChip('볼넷', '${season['bb'] ?? 0}'),
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
                    _statChip('평자', '${vs['era'] ?? '-'}'),
                    _statChip('이닝', vs['innings'] ?? '-'),
                    _statChip('삼진', '${vs['kk'] ?? 0}'),
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
    final playerId = _getPlayerIdByName(top['name'] as String?);

    return GestureDetector(
      onTap: playerId != null ? () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: playerId))) : null,
      child: Card(
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
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildRosterTab() {
    if (_rosterData == null) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E), strokeWidth: 2.5));
    }

    final homeTeam = _gameData!['game']['home_team'];
    final awayTeam = _gameData!['game']['away_team'];

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            indicatorColor: const Color(0xFF1A237E),
            indicatorWeight: 2.5,
            labelColor: const Color(0xFF1A237E),
            unselectedLabelColor: Colors.grey,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
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
        color: const Color(0xFF1A237E),
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
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
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
            backgroundColor: const Color(0xFF1A237E),
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
                color: const Color(0xFF1A237E).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1A237E).withOpacity(0.2)),
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
            indicatorColor: const Color(0xFF1A237E),
            indicatorWeight: 2.5,
            labelColor: const Color(0xFF1A237E),
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
        border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
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
                            style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                        const SizedBox(width: 10),
                        Container(width: 7, height: 7,
                            decoration: BoxDecoration(color: Colors.blue[400], shape: BoxShape.circle)),
                        const SizedBox(width: 3),
                        Text('볼 ${100 - strikePct}% ($balls)',
                            style: TextStyle(fontSize: 10, color: Colors.grey[500])),
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
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 3),
                              Text('$pct% ($count구)',
                                  style: TextStyle(fontSize: 10, color: Colors.grey[500])),
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
            indicatorColor: const Color(0xFF1A237E),
            indicatorWeight: 2.5,
            labelColor: const Color(0xFF1A237E),
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
                        profileImage != null ? CachedNetworkImageProvider(profileImage) : null,
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
          ),
          );
        }).toList();
      }).toList(),
    );
  }

  Widget _buildRecordDetailTab() {
    if (_recordDetailData == null) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E), strokeWidth: 2.5));
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

  Future<void> _openYouTube(String url) async {
    if (url.isEmpty) return;
    final isYT = url.contains('youtube.com') || url.contains('youtu.be');
    // 1) YouTube 앱 직접 호출 (vnd.youtube scheme)
    if (isYT) {
      final m = RegExp(r'(?:v=|/shorts/|youtu\.be/)([A-Za-z0-9_-]{11})').firstMatch(url);
      final vid = m?.group(1);
      if (vid != null) {
        final appUri = Uri.parse('vnd.youtube://$vid');
        try {
          if (await canLaunchUrl(appUri)) {
            final ok = await launchUrl(appUri, mode: LaunchMode.externalNonBrowserApplication);
            if (ok) return;
          }
        } catch (_) {}
      }
    }
    // 2) fallback: 외부 브라우저 / 시스템 default
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Widget _buildHighlightsTab() {
    if (_highlightsLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E), strokeWidth: 2.5));
    }
    if (_highlights.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('하이라이트가 없습니다', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(12, 12, 12, 80 + MediaQuery.of(context).viewPadding.bottom),
      itemCount: _highlights.length,
      itemBuilder: (context2, idx) {
        final h = _highlights[idx] as Map<String, dynamic>;
        final title = h['title'] as String? ?? '';
        final url = h['url'] as String? ?? '';
        final thumbnail = h['thumbnail'] as String? ?? '';
        final isShorts = url.contains('/shorts/');
        final isDark = Theme.of(context2).brightness == Brightness.dark;

        return GestureDetector(
          onTap: () async {
            await _openYouTube(url);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[850] : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (thumbnail.isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CachedNetworkImage(
                          imageUrl: thumbnail,
                          width: double.infinity,
                          height: isShorts ? 180 : 140,
                          fit: isShorts ? BoxFit.contain : BoxFit.cover,
                          placeholder: (_, __) => Container(
                            height: isShorts ? 180 : 140,
                            color: isDark ? Colors.grey[800] : Colors.grey[200],
                          ),
                          errorWidget: (_, __, ___) => Container(
                            height: isShorts ? 180 : 140,
                            color: isDark ? Colors.grey[800] : Colors.grey[200],
                            child: const Icon(Icons.broken_image, color: Colors.grey),
                          ),
                        ),
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow, color: Colors.white, size: 30),
                        ),
                        if (isShorts)
                          Positioned(
                            top: 8, right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('Shorts', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ),
                      ],
                    ),
                  )
                else
                  Container(
                    height: 80,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.grey[100],
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                    ),
                    child: const Center(child: Icon(Icons.play_circle_outline, color: Color(0xFF003087), size: 40)),
                  ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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
                    side: const BorderSide(color: Color(0xFF1A237E)),
                    foregroundColor: const Color(0xFF1A237E),
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
                    backgroundColor: const Color(0xFF1A237E),
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
          colors: [Color(0xFF1A237E), Color(0xFF283593)],
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

    // Outfield grass (green arc — lighter zone over dark background)
    final ofPaint = Paint()
      ..color = Colors.green[500]!.withOpacity(0.38)
      ..style = PaintingStyle.fill;
    final arcCenter = Offset(w * 0.50, h * 0.95);
    final arcR = w * 0.78;
    final ofPath = Path()
      ..addArc(Rect.fromCircle(center: arcCenter, radius: arcR),
               -3.14 * 0.88, -3.14 * 1.24)
      ..lineTo(w * 0.15, h * 0.05)
      ..lineTo(w * 0.85, h * 0.05)
      ..close();
    canvas.drawPath(ofPath, ofPaint);

    // Infield dirt (diamond)
    final dirtPaint = Paint()
      ..color = const Color(0xFFC8923A).withOpacity(0.78)
      ..style = PaintingStyle.fill;
    final diamondPath = Path()
      ..moveTo(pHome.dx, pHome.dy)
      ..lineTo(p1B.dx,   p1B.dy)
      ..lineTo(p2B.dx,   p2B.dy)
      ..lineTo(p3B.dx,   p3B.dy)
      ..close();
    canvas.drawPath(diamondPath, dirtPaint);

    // Mound circle
    final moundPaint = Paint()
      ..color = const Color(0xFFC8923A).withOpacity(0.92)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pMound, w * 0.035, moundPaint);

    // Baselines
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.55)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(pHome, p1B, linePaint);
    canvas.drawLine(pHome, p3B, linePaint);
    canvas.drawLine(p1B,   p2B, linePaint);
    canvas.drawLine(p3B,   p2B, linePaint);

    // Foul lines extended
    final foulPaint = Paint()
      ..color = Colors.white.withOpacity(0.32)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(pHome, Offset(w * 0.0, h * 0.08), foulPaint);
    canvas.drawLine(pHome, Offset(w * 1.0, h * 0.08), foulPaint);

    // Bases
    void drawBase(Offset pos, bool occupied) {
      if (occupied) {
        final glow = Paint()
          ..color = Colors.yellow.withOpacity(0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
        canvas.drawRect(
          Rect.fromCenter(center: pos, width: 12, height: 12),
          glow,
        );
      }
      final bp = Paint()
        ..color = occupied ? Colors.yellow[500]! : (isDark ? Colors.grey[500]! : Colors.grey[300]!)
        ..style = PaintingStyle.fill;
      final bs = 7.0;
      final path = Path()
        ..moveTo(pos.dx,      pos.dy - bs)
        ..lineTo(pos.dx + bs, pos.dy)
        ..lineTo(pos.dx,      pos.dy + bs)
        ..lineTo(pos.dx - bs, pos.dy)
        ..close();
      canvas.drawPath(path, bp);
    }

    drawBase(p1B,   base1);
    drawBase(p2B,   base2);
    drawBase(p3B,   base3);

    // Home plate (white pentagon)
    final hp = Paint()..color = Colors.white.withOpacity(0.8)..style = PaintingStyle.fill;
    final homePath = Path()
      ..moveTo(pHome.dx,      pHome.dy - 5)
      ..lineTo(pHome.dx + 4.5, pHome.dy - 1.5)
      ..lineTo(pHome.dx + 3.5, pHome.dy + 4)
      ..lineTo(pHome.dx - 3.5, pHome.dy + 4)
      ..lineTo(pHome.dx - 4.5, pHome.dy - 1.5)
      ..close();
    canvas.drawPath(homePath, hp);
  }

  @override
  bool shouldRepaint(_FieldBgPainter old) =>
      old.base1 != base1 || old.base2 != base2 || old.base3 != base3 || old.isDark != isDark;
}