import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../api/api_service.dart';
import '../../utils/local_cache.dart';
import '../../utils/team_theme.dart';
import '../../utils/design_tokens.dart';
import '../../utils/web_safe_area.dart';
import 'pitch_location_chart.dart';
import '../player/player_detail_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/web_image.dart';
import '../../widgets/common_widgets.dart';
import 'package:shimmer/shimmer.dart';
import 'package:fl_chart/fl_chart.dart';

class GameDetailScreen extends StatefulWidget {
  final int gameId;

  const GameDetailScreen({super.key, required this.gameId});

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends State<GameDetailScreen>
    with SingleTickerProviderStateMixin, RestorationMixin {
  @override
  String get restorationId => 'game_detail_${widget.gameId}';

  final RestorableInt _restorableTabIndex = RestorableInt(0);
  final RestorableInt _restorableLineupSub = RestorableInt(0);
  final RestorableInt _restorableStatsSub = RestorableInt(0);

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_restorableTabIndex, 'tab_idx');
    registerForRestoration(_restorableLineupSub, 'lineup_sub');
    registerForRestoration(_restorableStatsSub, 'stats_sub');
    // 복원된 값 적용
    if (_tabController.index != _restorableTabIndex.value) {
      _tabController.index = _restorableTabIndex.value.clamp(0, 3);
    }
    _lineupSubIndex = _restorableLineupSub.value.clamp(0, 1);
    _statsSubIndex = _restorableStatsSub.value.clamp(0, 2);
  }

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
  // 필드뷰 항상 상단 고정 (토글 버튼 제거 — 2026-06-06)
  bool _fieldPinned = false; // 기본 비고정(필드 스크롤) — 핀 시 상단 고정 (06-14 기본값 변경)
  // 다른 경기 스트립 접기/펴기 (영구 기억)
  bool _stripExpanded = true;

  // 필드뷰 = 폭 기준 자연 비율(SVG 300x230) 렌더 (06-14). FittedBox 균일축소 폐기:
  // 그 방식이 다이아몬드+마커+이름+포지션을 통째 줄여 글씨 tiny + 좌우 여백(letterbox) 유발.
  // _FullFieldView 마커/텍스트는 내부 고정크기 → 직접 렌더 시 가독성 유지.
  // 필드는 항상 폭에 맞춰 채움 → crop 없음·여백 없음·iPhone≈Android(폭 비슷)·스트립 펼침과 무관.
  double _fieldH() {
    final w = MediaQuery.of(context).size.width;
    // 필드 박스 폭 = 화면폭 - 바깥패딩(18*2) - 안패딩(16*2) = w-68.
    // 자연높이(폭*230/300)의 0.82 — stretch 렌더라 세로 약간 압축(패널 축소·마커 고정크기 가독 유지).
    return ((w - 68) * 230 / 300 * 0.82).clamp(160.0, 240.0);
  }

  // 패널 = 고정부(스코어보드+패딩+핸들 ~138) + 필드 + 스트립 펼침분(필드는 안 줄어듦).
  double _currentPanelH() {
    const fixed = 138.0;
    final field = _fieldH();
    if (_sameDayGames.isEmpty) return fixed - 20 + field; // 핸들 없음
    return fixed + field + (_stripExpanded ? 70 : 0);
  }

  // 탭 콘텐츠 하단 클리어런스 — 플로팅 nav(+서브탭바)가 마지막 정보를 가리지 않게.
  // 사파리 웹은 viewPadding=0이라 webBottomGuard 동반 (06-13 가림 보고)
  double get _navClearance =>
      200 + MediaQuery.of(context).viewPadding.bottom + webBottomGuard(context);
  // 이닝별 중계 — 선택 이닝 (null = 자동: 라이브 현재 이닝 / 종료 1회)
  int? _selectedRelayInning;
  final ScrollController _inningChipCtrl = ScrollController();
  int? _lastAutoScrolledInning; // 칩 자동 스크롤 dedup (이닝 바뀔 때만 이동)

  // 불펜 피로도 (팀별 최근 7일 등판 신호등) — 로스터 카드 첫 빌드 시 lazy 로드
  final Map<int, Map<String, String>> _bullpenStatus = {}; // teamId -> {투수명: status}
  bool _bullpenLoading = false;

  void _loadBullpenStatus() {
    if (_bullpenLoading || _bullpenStatus.isNotEmpty) return;
    final hid = _gameData?['game']?['home_team_id'] as int?;
    final aid = _gameData?['game']?['away_team_id'] as int?;
    if (hid == null || aid == null) return;
    _bullpenLoading = true;
    () async {
      try {
        final res = await Future.wait(
            [ApiService.getBullpenStatus(hid), ApiService.getBullpenStatus(aid)]);
        if (!mounted) return;
        setState(() {
          for (var i = 0; i < 2; i++) {
            final d = res[i];
            if (d == null) continue;
            final m = <String, String>{};
            for (final p in (d['pitchers'] as List? ?? [])) {
              m[p['name'] as String? ?? ''] = p['status'] as String? ?? 'green';
            }
            _bullpenStatus[i == 0 ? hid : aid] = m;
          }
        });
      } catch (e) {
        debugPrint('game_detail bullpen: $e');
      } finally {
        _bullpenLoading = false;
      }
    }();
  }

  // 승리확률 시계열 (인게임 모델) — 중계 탭 첫 빌드 시 lazy 로드, 라이브 30s 갱신
  Map<String, dynamic>? _winProbData;
  bool _winProbLoading = false;

  void _loadWinProb() {
    if (_winProbLoading) return;
    final status = _gameData?['game']?['status'] as String? ?? '';
    if (status != '진행' && status != '종료') return;
    _winProbLoading = true;
    () async {
      try {
        final d = await ApiService.getWinProbSeries(widget.gameId);
        if (mounted && d != null) setState(() => _winProbData = d);
      } catch (e) {
        debugPrint('game_detail winprob: $e');
      } finally {
        _winProbLoading = false;
      }
    }();
  }

  Widget _buildWinProbCard() {
    final d = _winProbData;
    if (d == null) {
      _loadWinProb(); // lazy 시작 (비동기 — 빌드 안전)
      return const SizedBox.shrink();
    }
    final series = (d['series'] as List? ?? []).whereType<Map>().toList();
    if (series.length < 5) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _WinProbChart(
        series: series,
        finalProb: (d['final_prob'] as num?)?.toDouble(),
        homeColor: teamColor(_gameData?['game']?['home_team_code'] as String? ?? ''),
        homeName: _gameData?['game']?['home_team'] as String? ?? '홈',
        awayName: _gameData?['game']?['away_team'] as String? ?? '원정',
        isLive: (_gameData?['game']?['status'] as String? ?? '') == '진행',
        isDark: Theme.of(context).brightness == Brightness.dark,
      ),
    );
  }

  // 현재 타석 맞대결 통산 (plate_appearances 기반) — 타자·투수 조합 바뀔 때만 fetch
  Map<String, dynamic>? _matchupData;
  String _matchupKey = '';

  void _maybeLoadMatchup(Map<String, dynamic>? fieldView) {
    final b = fieldView?['batter'] as Map<String, dynamic>?;
    final p = fieldView?['pitcher'] as Map<String, dynamic>?;
    final bid = b?['player_id'] as int?;
    final pid = p?['player_id'] as int?;
    if (bid == null || pid == null) return;
    final key = '$bid:$pid';
    if (key == _matchupKey) return;
    _matchupKey = key;
    _matchupData = null;
    () async {
      try {
        final d = await ApiService.getMatchupStats(bid, pid);
        if (mounted && _matchupKey == key) setState(() => _matchupData = d);
      } catch (e) {
        debugPrint('game_detail matchup: $e');
      }
    }();
  }

  String? get _matchupLine {
    final d = _matchupData;
    if (d == null) return null;
    final pa = d['pa'] as int? ?? 0;
    if (pa == 0) return '첫 맞대결';
    final ab = d['at_bats'] ?? 0;
    final h = d['hits'] ?? 0;
    final hr = d['home_runs'] ?? 0;
    final bb = d['walks'] ?? 0;
    final k = d['strikeouts'] ?? 0;
    final parts = <String>['$ab타수 $h안타'];
    if (hr > 0) parts.add('홈런$hr');
    if (bb > 0) parts.add('볼넷$bb');
    if (k > 0) parts.add('삼진$k');
    return parts.join(' · ');
  }
  int _relaySwipeDir = 1; // 슬라이드 방향 (1=다음: 우→좌, -1=이전: 좌→우)
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
    LocalCache.getStale('other_strip_expanded').then((v) {
      if (mounted && v is bool && v != _stripExpanded) setState(() => _stripExpanded = v);
    });
    LocalCache.getStale('field_pinned').then((v) {
      if (mounted && v is bool && v != _fieldPinned) setState(() => _fieldPinned = v);
    });
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      _restorableTabIndex.value = _tabController.index;
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
    _inningChipCtrl.dispose();
    _restorableTabIndex.dispose();
    _restorableLineupSub.dispose();
    _restorableStatsSub.dispose();
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
      // relay_state는 진행중일 때만 복원 — 종료 후 stale 라이브 필드뷰 고정 방지 (06-06 한화-롯데 오재원 타석 멈춤)
      if (cachedRelayState != null &&
          (cachedDetail?['game']?['status'] as String? ?? '') == '진행') {
        _relayData = Map<String, dynamic>.from(cachedRelayState);
      }
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
      setState(() {
        _gameData = gameData;
        _isLoading = false;
        // 비진행 경기에 stale 라이브 relay 잔존 시 무효화 → 정적 라인업 필드뷰 경로
        if ((gameData['game']?['status'] as String? ?? '') != '진행' && _relayData != null) {
          _relayData = null;
        }
      });
      if ((gameData['game']?['status'] as String? ?? '') != '진행') {
        LocalCache.remove(_ck('relay_state'));
      }

      // 1회성 hint — 진행중 게임 처음 진입 시 베이스 탭 안내 (핀 힌트 제거 — 필드뷰 항상 고정)
      final status = gameData['game']?['status'] as String? ?? '';
      if (status == '진행' && mounted) {
        final baseShown = await LocalCache.hasFlag('base_hint_shown');
        if (!baseShown && mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('💡 베이스(1·2·3루)를 탭하면 주자 정보를 볼 수 있어요'),
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            backgroundColor: SemColor.panelDark,
            action: SnackBarAction(
              label: '확인',
              textColor: SemColor.warning,
              onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
            ),
          ));
          await LocalCache.setFlag('base_hint_shown');
        }
      }

      // LIVE 게임 포함 항상 캐시 — 다음 진입 시 stale-while-revalidate
      await LocalCache.set(_ck('detail'), gameData);

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
              } catch (e) { debugPrint('game_detail: $e'); }
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
        _loadWinProb();
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
      // getGameDetail + getGameRelayAll 독립 → 병렬 (직렬 2 RT → 1 RT)
      final results = await Future.wait([
        ApiService.getGameDetail(widget.gameId),
        ApiService.getGameRelayAll(widget.gameId),
      ]);
      if (!mounted) return;
      final gameData = results[0];
      setState(() {
        _gameData = gameData;
        _relayAllData = results[1];
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
      highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
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

    // breadcrumb: 팀 vs 팀 + 현재 탭 + (sub-tab)
    const mainTabs = ['중계', '라인업', '기록', '하이라이트'];
    final tabIdx = _tabController.index.clamp(0, mainTabs.length - 1);
    final currentTab = mainTabs[tabIdx];
    String? subTab;
    if (tabIdx == 1) {
      subTab = ['키플레이어', '로스터'][_lineupSubIndex];
    } else if (tabIdx == 2) {
      subTab = ['투수', '타자', '상대'][_statsSubIndex];
    }

    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${game['home_team']} vs ${game['away_team']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 1),
            Text(
              subTab != null ? '$currentTab · $subTab' : currentTab,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFC9C9D1)
                    : const Color(0xFF6B6B73),
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '경기 공유',
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
                    // panel-spacer: transparent → panel rounded 끝점 보이게 (paper 노출 X)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      height: _currentPanelH(),
                    ),
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
            bottom: 16 + MediaQuery.of(context).viewPadding.bottom + webBottomGuard(context),
            child: _buildGameFloatingNav(),
          ),
        ],
      ),
    );
  }

  Widget _buildSameDayStrip() {
    // mockup MiniGames — 2-col grid
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink   = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
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
          // 1x4 한 줄 배치 (5경기 - 현재경기 = 4) — '다른 경기' 라벨 제거 (2026-06-06)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 6, crossAxisSpacing: 6,
              // 비율(1.4) → 고정 높이: 화면폭 무관 스트립 높이 결정론화 (패널 고정높이 정합)
              mainAxisExtent: 62,
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

              final aScore = (awayScore as int?) ?? 0;
              final hScore = (homeScore as int?) ?? 0;
              final awayWin = isDone && aScore > hScore;
              final homeWin = isDone && hScore > aScore;
              final aColor = teamColor(awayCode);
              final hColor = teamColor(homeCode);

              // 스코어/시간 위젯 — 종료: 승팀 강조 / 라이브: 빨강 / 예정: 시간
              Widget scoreWidget;
              if (isDone || isLive) {
                Color cA = isLive ? live : (awayWin ? ink : sub);
                Color cH = isLive ? live : (homeWin ? ink : sub);
                scoreWidget = Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLive) ...[
                      Container(width: 4, height: 4,
                          decoration: const BoxDecoration(color: live, shape: BoxShape.circle)),
                      const SizedBox(width: 3),
                    ],
                    Text('$aScore',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cA,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                    Text(' : ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: sub)),
                    Text('$hScore',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cH,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                  ],
                );
              } else {
                scoreWidget = Text(g['start_time'] as String? ?? '-',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: sub,
                        fontFeatures: const [FontFeature.tabularFigures()]));
              }

              return GestureDetector(
                onTap: isCurrent ? null
                    : () => Navigator.pushReplacement(context,
                        MaterialPageRoute(builder: (_) => GameDetailScreen(gameId: g['id'] as int))),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: isCurrent ? paper2 : paper,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isLive ? live.withValues(alpha: 0.55) : (isCurrent ? ink : line),
                      width: (isLive || isCurrent) ? 1.3 : 1,
                    ),
                    boxShadow: isCurrent ? null : [
                      BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.05),
                          blurRadius: 3, offset: const Offset(0, 1)),
                    ],
                  ),
                  child: Column(
                    children: [
                      // 팀컬러 듀얼 띠 (away → home)
                      SizedBox(
                        height: 3,
                        child: Row(children: [
                          Expanded(child: ColoredBox(color: aColor.withValues(alpha: 0.85))),
                          Expanded(child: ColoredBox(color: hColor.withValues(alpha: 0.85))),
                        ]),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Opacity(opacity: homeWin ? 0.45 : 1.0, child: TeamLogo(teamCode: awayCode, size: 16)),
                                const SizedBox(width: 3),
                                Text('vs', style: TextStyle(fontSize: 9, color: sub, fontWeight: FontWeight.w600)),
                                const SizedBox(width: 3),
                                Opacity(opacity: awayWin ? 0.45 : 1.0, child: TeamLogo(teamCode: homeCode, size: 16)),
                              ],
                            ),
                            const SizedBox(height: 3),
                            scoreWidget,
                          ],
                        ),
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
        _maybeLoadMatchup(fieldView);
        fieldWidget = _FullFieldView(
          base1: relayState['base1'] == true,
          base2: relayState['base2'] == true,
          base3: relayState['base3'] == true,
          fieldView: fieldView,
          isDark: isDark,
          matchupLine: _matchupLine,
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
    final ink    = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
    final ink3   = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    final sub    = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final paper  = isDark ? const Color(0xFF18181C) : Colors.white;
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
                            style: TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0)),
                        if (homeRank != null && homeRank > 0)
                          Text('$homeRank위', style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.w600)),
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
                      Semantics(
                        label: '$homeTeam $homeScore점 대 $awayScore점 $awayTeam',
                        child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            transitionBuilder: (c, anim) {
                              return SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.4),
                                  end: Offset.zero,
                                ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                                child: FadeTransition(opacity: anim, child: c),
                              );
                            },
                            child: Builder(builder: (_) {
                              final isLoser = (isDone || isLive) && homeScore < awayScore;
                              return Text('$homeScore',
                                  key: ValueKey(homeScore),
                                  style: TextStyle(
                                    color: isLoser ? ink.withValues(alpha: 0.45) : ink,
                                    fontSize: isLoser ? 30 : 34,
                                    fontWeight: FontWeight.w800, letterSpacing: 0,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ));
                            }),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(':',
                                style: TextStyle(color: line2, fontSize: 24, fontWeight: FontWeight.w400)),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            transitionBuilder: (c, anim) {
                              return SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.4),
                                  end: Offset.zero,
                                ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                                child: FadeTransition(opacity: anim, child: c),
                              );
                            },
                            child: Builder(builder: (_) {
                              final isLoser = (isDone || isLive) && awayScore < homeScore;
                              return Text('$awayScore',
                                  key: ValueKey(awayScore),
                                  style: TextStyle(
                                    color: isLoser ? ink.withValues(alpha: 0.45) : ink,
                                    fontSize: isLoser ? 30 : 34,
                                    fontWeight: FontWeight.w800, letterSpacing: 0,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ));
                            }),
                          ),
                        ],
                      ),
                      ),
                      const SizedBox(height: 6),
                      if (isLive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: live.withValues(alpha: isDark ? 0.20 : 0.10),
                            borderRadius: BorderRadius.circular(Radii.pill),
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
                            style: TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0)),
                        if (awayRank != null && awayRank > 0)
                          Text('$awayRank위', style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.w600)),
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
                          padding: const EdgeInsets.fromLTRB(16, 35, 16, 20),
                          // C안: 좌표 자체 bilinear quad mapping (Matrix4 제거)
                          // 축소 시 FittedBox = 비율 유지 전체 축소 (painter가 max-fit이라
                          // 높이만 줄이면 외야/홈이 위아래로 잘림 — 06-12)
                          child: SizedBox(
                            height: _fieldH(),
                            width: double.infinity,
                            child: fieldWidget,
                          ),
                        ),
                        // BSO overlay — 항상 표시 (비라이브 시 0/0/0)
                        Positioned(
                            top: 4, left: 0, right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(Radii.pill),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        // 진행중 빨강, 그 외 회색
                                        color: isLive ? live : const Color(0xFF9A9AA3),
                                        borderRadius: BorderRadius.circular(Radii.pill),
                                      ),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        Container(width: 4, height: 4,
                                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                                        const SizedBox(width: 3),
                                        const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                                      ]),
                                    ),
                                    const SizedBox(width: 8),
                                    _bsoOverlayGroup('B', ((_relayData?['current_state']?['ball'] as int?) ?? 0).clamp(0, 3), 3, const Color(0xFF22C55E)),
                                    const SizedBox(width: 6),
                                    _bsoOverlayGroup('S', ((_relayData?['current_state']?['strike'] as int?) ?? 0).clamp(0, 2), 2, live),
                                    const SizedBox(width: 6),
                                    _bsoOverlayGroup('O', ((_relayData?['current_state']?['out'] as int?) ?? 0).clamp(0, 2), 2, const Color(0xFFFFA000)),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 16, height: 16,
                                      child: _isRelayRefreshing
                                          ? const CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                                          : GestureDetector(
                                              onTap: _refreshRelayAll,
                                              child: const Icon(Icons.refresh, size: 16, color: Colors.white),
                                            ),
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
            // 필드 고정/해제 토글 (스트립 아래 — 핀 모드 하단 컨트롤행과 위치 통일)
            if (includeField)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(child: _fieldPinHandle(isDark)),
              ),

            const SizedBox(height: 14),
            Container(height: 1, color: line),
          ],
        ),
      ),
    );
  }

  // BSO overlay (검은 반투명 배경 위 흰 텍스트 + 컬러 dot)
  Widget _bsoOverlayGroup(String lbl, int count, int max, Color c) {
    // #19 색맹 대응: dot + 라벨 + 숫자 (색만 의존 X)
    final korLabel = lbl == 'B' ? '볼' : lbl == 'S' ? '스트라이크' : '아웃';
    return Semantics(
      label: '$korLabel $count개 / $max개',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(lbl,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(width: 3),
          ...List.generate(max, (i) => Container(
            width: 7, height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < count ? c : Colors.white.withValues(alpha: 0.25),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 0.5),
            ),
          )),
        ],
      ),
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
        borderRadius: BorderRadius.circular(Radii.pill),
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

  // 그날 기록 lookup — pitchers list에서 name 매칭 → "5이닝 2실점 7K"
  String _pitcherDayStats(String name) {
    final pitchers = (_gameData?['pitchers'] as List?) ?? [];
    for (final p in pitchers) {
      if ((p['name'] as String? ?? '') != name) continue;
      final ip = p['innings_pitched'];
      final r = p['runs_allowed'];
      final so = p['strikeouts'];
      final parts = <String>[];
      if (ip != null && ip != 0) parts.add('$ip이닝');
      if (r != null) parts.add('$r실점');
      if (so != null && so > 0) parts.add('${so}K');
      return parts.join(' ');
    }
    return '';
  }

  Widget _pitcherBadge(String name, Color color, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
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
    final ink   = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
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
      if (temp != null) '$temp°C',
      if (feelsLike != null) '체감 $feelsLike°',
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
        _maybeLoadMatchup(fieldView);
        fieldWidget = _FullFieldView(
          base1: relayState['base1'] == true,
          base2: relayState['base2'] == true,
          base3: relayState['base3'] == true,
          fieldView: fieldView,
          isDark: isDark,
          matchupLine: _matchupLine,
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
    final homeCode = game['home_team_code'] as String? ?? '';
    final awayCode = game['away_team_code'] as String? ?? '';
    final homeTeam = game['home_team'] as String? ?? '';
    final awayTeam = game['away_team'] as String? ?? '';
    final homeScore = _liveScore(game, 'home_score');
    final awayScore = _liveScore(game, 'away_score');
    final ink = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      // 스트립 토글: 펼침 498 / 접힘 428 (실기 11px overflow 보정 +12). 스트립 없으면 408
      // 짧은 뷰포트는 _panelH가 필드 축소분만큼 감산
      height: _currentPanelH(),
      decoration: BoxDecoration(
        color: paper,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          // ── mini-scoreboard: 홈로고 | 스코어 | 원정로고 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TeamLogo(teamCode: homeCode, size: 28),
                    const SizedBox(width: 6),
                    Flexible(child: Text(homeTeam,
                        style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0),
                        overflow: TextOverflow.ellipsis, maxLines: 1)),
                  ],
                )),
                Text('$homeScore : $awayScore',
                    style: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                Expanded(child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(child: Text(awayTeam,
                        textAlign: TextAlign.end,
                        style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0),
                        overflow: TextOverflow.ellipsis, maxLines: 1)),
                    const SizedBox(width: 6),
                    TeamLogo(teamCode: awayCode, size: 28),
                  ],
                )),
              ],
            ),
          ),
          const SizedBox(height: 8),
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
                      padding: const EdgeInsets.fromLTRB(16, 35, 16, 12),
                      // 축소 시 FittedBox = 비율 유지 전체 축소 (높이만 줄이면 위아래 잘림)
                      child: SizedBox(
                        height: _fieldH(),
                        width: double.infinity,
                        child: fieldWidget,
                      ),
                    ),
                    // BSO overlay — 항상 표시 (비라이브 시 0/0/0)
                    Positioned(
                        top: 4, left: 0, right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(Radii.pill),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isLive ? live : const Color(0xFF9A9AA3),
                                    borderRadius: BorderRadius.circular(Radii.pill),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                                    const SizedBox(width: 3),
                                    const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                                  ]),
                                ),
                                const SizedBox(width: 8),
                                _bsoOverlayGroup('B', ((_relayData?['current_state']?['ball'] as int?) ?? 0).clamp(0, 3), 3, const Color(0xFF22C55E)),
                                const SizedBox(width: 6),
                                _bsoOverlayGroup('S', ((_relayData?['current_state']?['strike'] as int?) ?? 0).clamp(0, 2), 2, live),
                                const SizedBox(width: 6),
                                _bsoOverlayGroup('O', ((_relayData?['current_state']?['out'] as int?) ?? 0).clamp(0, 2), 2, const Color(0xFFFFA000)),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 16, height: 16,
                                  child: _isRelayRefreshing
                                      ? const CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                                      : GestureDetector(
                                          onTap: _refreshRelayAll,
                                          child: const Icon(Icons.refresh, size: 16, color: Colors.white),
                                        ),
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
          // Spacer — 핸들 블록을 패널 바닥 정착 (하단 잉여 여백 제거)
          const Spacer(),
          // 상시 마운트 AnimatedSize — 스트립 토글이 패널 높이 애니메이션(200ms)과 동기화.
          // ⚠️ 핸들은 ClipRect 밖 (06-13): 작은 화면서 공간 부족 시 스트립만 잘리고
          // 핸들은 항상 보이게 — 핸들까지 클립되면 접기/펼치기 자체가 불가
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: (_sameDayGames.isEmpty || !_stripExpanded)
                  ? const SizedBox(width: double.infinity, height: 0)
                  : _buildSameDayStrip(),
            ),
          ),
          // ── 하단 컨트롤 행: 필드 고정 토글(항상) + 다른구장 스트립 핸들(있을 때) ──
          // top = 스트립↔버튼 여백(펼침), bottom = 버튼↔패널하단 여백(접힘). Spacer(필드↔스트립)가 그만큼 자동 축소.
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _fieldPinHandle(isDark),
              if (_sameDayGames.isNotEmpty) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _stripExpanded = !_stripExpanded);
                    LocalCache.set('other_strip_expanded', _stripExpanded);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (!_stripExpanded) ...[
                        Text('다른 구장 경기',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                color: isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73))),
                        const SizedBox(width: 4),
                      ],
                      Icon(_stripExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          size: 16,
                          color: isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73)),
                    ]),
                  ),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  // 필드 고정/해제 토글 핸들 (하단 컨트롤 행 + 비핀 gameHeader 공용)
  Widget _fieldPinHandle(bool isDark) {
    final fg = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _fieldPinned = !_fieldPinned);
        LocalCache.set('field_pinned', _fieldPinned);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_fieldPinned ? Icons.push_pin : Icons.push_pin_outlined, size: 13, color: fg),
          const SizedBox(width: 3),
          Text(_fieldPinned ? '필드 고정' : '고정 해제',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
        ]),
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
        color: on ? c : Colors.white.withValues(alpha: 0.18),
        boxShadow: on ? [BoxShadow(color: c.withValues(alpha: 0.65), blurRadius: 5, spreadRadius: 1)] : null,
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
                matchupLine: _matchupLine,
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

    // navBottom: 핀/탭 sub-label 모드에서 floating nav 가림 방지 (sub bar 시 더 큼)
    final hasSubBar = _tabController.index == 1 || _tabController.index == 2;
    final navBottom = _navClearance;
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
          // 득점요약 카드 (라인스코어는 상단 스코어보드와 중복이라 제거 — 06-14)
          if (innings.isNotEmpty && _relayAllData != null) ...[
            Builder(builder: (ctx) {
              final isDarkC = Theme.of(ctx).brightness == Brightness.dark;
              return Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDarkC ? const Color(0xFF18181C) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: isDarkC ? const Color(0xFF26262C) : const Color(0xFFEDEDF0),
                      width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildScoringSection(innings, awayTeam, homeTeam),
              );
            }),
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
              final ink   = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
              final ink3  = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
              final paper = isDark ? const Color(0xFF18181C) : Colors.white;
              final line  = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 12, left: 2),
                    child: Text('이닝별 중계',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: ink, letterSpacing: 0)),
                  ),
                  // ── 디자인 B: 이닝 칩 가로 네비 + 선택 이닝 단일 표시 (2026-06-07) ──
                  Builder(builder: (_) {
                    final isLiveGame = (_gameData?['game']['status'] as String? ?? '') == '진행';
                    final curInning = _gameData?['game']['current_inning'] as int?;
                    final scoringInnings = <int>{
                      for (final inn in innings)
                        if (((inn['away_runs'] as int?) ?? 0) + ((inn['home_runs'] as int?) ?? 0) > 0)
                          (inn['inning'] as int? ?? 0),
                    };
                    int selected = _selectedRelayInning ??
                        (isLiveGame && curInning != null && grouped.containsKey(curInning)
                            ? curInning
                            : (sortedInnings.isNotEmpty ? sortedInnings.first : 1));
                    if (!grouped.containsKey(selected) && sortedInnings.isNotEmpty) {
                      selected = sortedInnings.last;
                    }
                    // 선택 이닝 칩 자동 스크롤 (연장전 등 화면 밖 이닝 — 이닝 변경 시 1회)
                    if (_lastAutoScrolledInning != selected) {
                      _lastAutoScrolledInning = selected;
                      final idx = sortedInnings.indexOf(selected);
                      if (idx >= 0) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted || !_inningChipCtrl.hasClients) return;
                          final off = (idx * 48.0 - 120.0)
                              .clamp(0.0, _inningChipCtrl.position.maxScrollExtent);
                          _inningChipCtrl.animateTo(off,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut);
                        });
                      }
                    }
                    final items = grouped[selected] ?? [];
                    final topItems = items.where((r) => (r['inning_half']?.toString() ?? '0') == '0').toList();
                    final botItems = items.where((r) => (r['inning_half']?.toString() ?? '0') == '1').toList();

                    Widget chip(int n) {
                      final isSel = n == selected;
                      final hasRun = scoringInnings.contains(n);
                      final isCur = isLiveGame && n == curInning;
                      return GestureDetector(
                        onTap: () => setState(() {
                          _relaySwipeDir = n >= selected ? 1 : -1;
                          _selectedRelayInning = n;
                        }),
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                          decoration: BoxDecoration(
                            color: isSel ? ink : paper,
                            borderRadius: BorderRadius.circular(Radii.pill),
                            border: Border.all(
                                color: isSel ? ink : (isCur ? const Color(0xFFE53935) : line),
                                width: isCur && !isSel ? 1.3 : 1),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('$n',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                                    color: isSel ? (isDark ? Colors.black : Colors.white) : ink,
                                    fontFeatures: const [FontFeature.tabularFigures()])),
                            // 득점 이닝 dot (amber)
                            if (hasRun) ...[
                              const SizedBox(width: 4),
                              Container(width: 5, height: 5,
                                  decoration: BoxDecoration(
                                      color: isSel ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                                      shape: BoxShape.circle)),
                            ],
                            // 라이브 현재 이닝 dot (red)
                            if (isCur) ...[
                              const SizedBox(width: 4),
                              Container(width: 5, height: 5,
                                  decoration: const BoxDecoration(
                                      color: Color(0xFFE53935), shape: BoxShape.circle)),
                            ],
                          ]),
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── 승리확률 그래프 (타석별 시계열 — 인게임 모델) ──
                        _buildWinProbCard(),
                        LayoutBuilder(builder: (ctx, c) => HScrollFade(child: SingleChildScrollView(
                          controller: _inningChipCtrl,
                          scrollDirection: Axis.horizontal,
                          // 맞으면 가운데 정렬(minWidth=뷰포트), 넘치면 스크롤
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: c.maxWidth),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center,
                                children: [for (final n in sortedInnings) chip(n)]),
                          ),
                        ))),
                        const SizedBox(height: 10),
                        // 좌우 스와이프 = 이전/다음 이닝 (칩 = 점프, 스와이프 = 순차)
                        GestureDetector(
                          onHorizontalDragEnd: (d) {
                            final v = d.primaryVelocity ?? 0;
                            if (v.abs() < 150) return;
                            final idx = sortedInnings.indexOf(selected);
                            final next = v < 0 ? idx + 1 : idx - 1; // 좌 스와이프 = 다음
                            if (next < 0 || next >= sortedInnings.length) return;
                            setState(() {
                              _relaySwipeDir = v < 0 ? 1 : -1;
                              _selectedRelayInning = sortedInnings[next];
                            });
                          },
                          child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          // 방향성 슬라이드: 다음 = 우→좌 진입, 이전 = 좌→우 진입
                          transitionBuilder: (child, anim) {
                            final isIncoming = child.key == ValueKey(selected);
                            final beginX = isIncoming ? 0.22 * _relaySwipeDir : -0.22 * _relaySwipeDir;
                            return FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: Offset(beginX, 0), end: Offset.zero,
                                ).animate(anim),
                                child: child,
                              ),
                            );
                          },
                          child: Container(
                          key: ValueKey(selected),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: paper,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: line, width: 1),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (topItems.isEmpty && botItems.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text('기록이 없습니다',
                                      style: TextStyle(fontSize: 12, color: ink3, fontWeight: FontWeight.w600)),
                                ),
                              if (topItems.isNotEmpty) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(15, 12, 15, 6),
                                  child: Text('$selected회초 $awayTeam 공격',
                                      style: const TextStyle(
                                          fontSize: 12, fontWeight: FontWeight.w700,
                                          color: Color(0xFF1976D2))),
                                ),
                                ...groupByBatter(topItems).map((e) => _buildBatterRelayTile(e)),
                              ],
                              if (botItems.isNotEmpty) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(15, 12, 15, 6),
                                  decoration: topItems.isNotEmpty
                                      ? BoxDecoration(border: Border(top: BorderSide(color: line, width: 1)))
                                      : null,
                                  child: Text('$selected회말 $homeTeam 공격',
                                      style: const TextStyle(
                                          fontSize: 12, fontWeight: FontWeight.w700,
                                          color: Color(0xFFC62828))),
                                ),
                                ...groupByBatter(botItems).map((e) => _buildBatterRelayTile(e)),
                              ],
                            ],
                          ),
                          ),
                          ),
                        ),
                      ],
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
    final ink   = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
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
    var result = resultTitle.contains(' : ')
        ? resultTitle.split(' : ').sublist(1).join(' : ').trim()
        : resultTitle;
    // 괄호 보조설명 제거 (송구 경로/홈런거리 등) — 고정 컬럼에서 잘림 방지, 핵심 상황만
    result = result
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

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
          // 타석 헤더 2행 구조 (디자인 ①, 2026-06-07):
          // 1행 [타자 vs 투수 ──── ⊕투구위치(우측 고정)] / 2행 결과 chip 풀 (잘림 0)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 단일 Expanded — 투구위치 chip 우측 끝 고정 (Flexible+Spacer flex 분배 슬랙 방지)
              Expanded(
                child: Row(children: [
                  Flexible(
                    child: Text(batterName,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ink, letterSpacing: 0)),
                  ),
                  if (pitcherName != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('vs $pitcherName',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: sub)),
                    ),
                  ],
                ]),
              ),
              const SizedBox(width: 6),
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
                      color: paper2, borderRadius: BorderRadius.circular(Radii.pill),
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
          // 2행: 결과 chip — 긴 문장은 자동 스크롤 회전 (가장자리 잘림 방지)
          if (result.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: resultBg, borderRadius: BorderRadius.circular(Radii.pill)),
                child: _MarqueeText(
                  text: result,
                  style: TextStyle(fontSize: 11, color: resultFg, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
          // 이벤트 (도루/홈인/교체/방문 등)
          if (events.isNotEmpty) const SizedBox(height: 6),
          ...events.map((r) {
            final rtype = r['type'] as int?;
            final title = r['title'] as String? ?? '';
            Color color = ink3;
            if (rtype == 14 || rtype == 31) {
              color = const Color(0xFFD97706);
            } else if (rtype == 2 || rtype == 20) {
              color = const Color(0xFF7C3AED);
            } else if (rtype == 7 || rtype == 21) {
              color = const Color(0xFF0D9488);
            } else if (rtype == 22) {
              color = const Color(0xFF4F46E5);
            } else if (rtype == 23) {
              color = const Color(0xFFCA8A04);
            } else if (rtype == 24) {
              color = const Color(0xFF475569);
            } else if (rtype == 25) {
              color = const Color(0xFFE53935);
            }
            return Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(children: [
                Text('↔ ', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
                Expanded(
                  child: _MarqueeText(
                    text: title,
                    style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
                  ),
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

            // pitch dot — tonal 스타일 (vivid solid → 저채도 tint bg + 600톤 fg, 결과 chip과 동일 언어)
            Color dotFg;
            switch (pitchResult) {
              case 'B': dotFg = const Color(0xFF16A34A); break;
              case 'T': case 'S': dotFg = const Color(0xFFE11D48); break;
              case 'F': dotFg = const Color(0xFFEA580C); break;
              case 'H': case 'X': dotFg = const Color(0xFF2563EB); break;
              default: dotFg = ink3;
            }
            final dotBg = pitchResult == null
                ? (isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0))
                : dotFg.withValues(alpha: isDark ? 0.20 : 0.12);

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
                  // 62: '스트라이크'(5자)가 한 줄에 들어가는 폭 — 50이면 '스트라이/크' 중간개행
                  width: 62,
                  child: Text(pitchResultText,
                      maxLines: 1, overflow: TextOverflow.visible, softWrap: false,
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

    // Group relay events by inning + half (+ 연속 중복 relay dedup — archive 이중 저장 케이스)
    final Map<String, List> byHalf = {};
    for (final r in relays) {
      final ing = r['inning'] as int? ?? 0;
      final half = r['inning_half']?.toString() ?? '0';
      final list = byHalf.putIfAbsent('$ing:$half', () => []);
      // 최근 4개 윈도우 내 동일 이벤트 skip (비인접 중복: [타석][홈인][타석][홈인] 패턴)
      bool dup = false;
      for (int k = list.length - 1; k >= 0 && k >= list.length - 4; k--) {
        final prev = list[k];
        if (prev['type'] == r['type'] &&
            (prev['title'] ?? '') == (r['title'] ?? '') &&
            (prev['text'] ?? '') == (r['text'] ?? '')) {
          dup = true;
          break;
        }
      }
      if (dup) continue;
      list.add(r);
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
          if (isAway) {
            cumAway += totalRuns;
          } else {
            cumHome += totalRuns;
          }
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
          if (isAway) {
            cumAway += runs;
          } else {
            cumHome += runs;
          }
          items.add({'inning': num, 'half': half, 'team': team, 'teamCode': tCode,
            'cumAway': cumAway, 'cumHome': cumHome,
            'relays': scoringGroups[i], 'runs': runs});
        }
      }

      splitHalf(awayR, 'top',    awayTeam, awayCode, true);
      splitHalf(homeR, 'bottom', homeTeam, homeCode, false);
    }
    if (items.isEmpty) return const SizedBox.shrink();

    ({String batter, String result}) parsePlay(String raw) {
      if (raw.contains(' : ')) {
        final idx = raw.indexOf(' : ');
        return (batter: raw.substring(0, idx).trim(), result: raw.substring(idx + 3).trim());
      }
      return (batter: '', result: raw);
    }

    // 구조화 추출 (2026-06-06 재설계): Naver title에 (N타점) 표기 없음 →
    // 타점 = 해당 타석 뒤따르는 '홈인' 이벤트 수 + (홈런이면 타자 본인 1)
    List<({String batter, String desc, int rbi, bool isHR})> extractPlays(List halfRelays) {
      final out = <({String batter, String desc, int rbi, bool isHR})>[];
      String? curBatter;
      String curDesc = '';
      bool curHR = false;
      int curHomeins = 0;

      void flush() {
        if (curBatter == null) return;
        final rbi = curHomeins + (curHR ? 1 : 0);
        if (rbi > 0) {
          out.add((batter: curBatter!, desc: curDesc, rbi: rbi, isHR: curHR));
        }
        curBatter = null;
        curDesc = '';
        curHR = false;
        curHomeins = 0;
      }

      for (final r in halfRelays) {
        final rtype = r['type'] as int?;
        final raw = (r['title'] as String? ?? r['text'] as String? ?? '').trim();
        if (rtype == 13 || rtype == 23) {
          flush();
          if (raw.isEmpty) continue;
          final parsed = parsePlay(raw);
          curBatter = parsed.batter.replaceFirst(RegExp(r'^\d+번타자\s*'), '').trim();
          curHR = parsed.result.contains('홈런');
          // desc — 괄호 보조설명/홈런거리 제거
          curDesc = parsed.result
              .replaceAll(RegExp(r'\(.*?\)'), '')
              .replaceAll(RegExp(r'\s{2,}'), ' ')
              .trim();
          if (curDesc.isEmpty) curDesc = curHR ? '홈런' : '안타';
        } else if (rtype == 14 || rtype == 24 || rtype == 31) {
          if (!raw.contains('홈인')) continue;
          if (curBatter != null) {
            curHomeins++;
          } else {
            // standalone 홈인 (폭투/보크 등 — 타석 외 득점)
            final nm = RegExp(r'([가-힣]{2,4})\s*:?\s*홈인').firstMatch(raw);
            out.add((
              batter: nm?.group(1) ?? '',
              desc: nm != null ? '홈인 (타석 외)' : raw,
              rbi: 0,
              isHR: false,
            ));
          }
        }
      }
      flush();
      return out;
    }

    final halfCards = items.asMap().entries.map((entry) {
      final idx = entry.key;
      final item = entry.value;
      final isLast = idx == items.length - 1;
      final ing = item['inning'] as int;
      final half = item['half'] as String;
      final teamCode = item['teamCode'] as String;
      final halfRelays = item['relays'] as List;
      final halfLabel = half == 'top' ? '초' : '말';

      final isDarkS = Theme.of(context).brightness == Brightness.dark;
      final inkS  = isDarkS ? const Color(0xFFF4F4F5) : SemColor.panelDark;
      final ink2S = isDarkS ? const Color(0xFFC9C9D1) : const Color(0xFF3F3F46);
      final ink3S = isDarkS ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
      final paper2S = isDarkS ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6);
      final lineRow = isDarkS ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);

      final inningChip = Container(
        width: 28, height: 22,
        decoration: BoxDecoration(color: paper2S, borderRadius: BorderRadius.circular(5)),
        alignment: Alignment.center,
        child: Text('$ing$halfLabel',
            style: TextStyle(fontSize: 10, color: ink3S, fontWeight: FontWeight.w700)),
      );

      final logo = TeamLogo(teamCode: teamCode, size: 20);

      // ── 홈=좌측 / 원정=우측 미러 정렬, 이름 natural width (여백 축소) ──
      final isHome = half == 'bottom';
      final plays = extractPlays(halfRelays);

      Widget rbiBadge(int rbi, bool isHR) => Container(
        width: 48,
        padding: const EdgeInsets.symmetric(vertical: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isHR ? const Color(0xFFD97706).withValues(alpha: 0.14) : paper2S,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(rbi > 0 ? '$rbi타점' : '득점',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                color: isHR ? const Color(0xFFD97706) : inkS,
                fontFeatures: const [FontFeature.tabularFigures()])),
      );

      // 중앙: 로고-선수-타구 가운데 정렬 / 사이드: 홈=좌 [이닝][타점], 어웨이=우 [타점][이닝]
      Widget playRow(({String batter, String desc, int rbi, bool isHR}) p, bool first) {
        final chipBox = first ? inningChip : const SizedBox(width: 28);
        final badge = rbiBadge(p.rbi, p.isHR);
        final sideCluster = Row(
          mainAxisSize: MainAxisSize.min,
          children: isHome
              ? [chipBox, const SizedBox(width: 4), badge]
              : [badge, const SizedBox(width: 4), chipBox],
        );
        return Padding(
          padding: EdgeInsets.only(top: first ? 0 : 6),
          // 높이 24 보장 — 중앙 텍스트(~17px)보다 타점 배지(~23px)가 커서
          // Stack 기본 클립에 배지 하단이 잘리던 것 (06-13 웹 보고)
          child: SizedBox(
            height: 24,
            child: Stack(
              children: [
                // 중앙 클러스터 — 양쪽 사이드 폭(84)만큼 패딩 후 center
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 84),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (first) logo else const SizedBox(width: 20),
                      const SizedBox(width: 6),
                      Text(p.batter, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: inkS)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(p.desc, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ink2S)),
                      ),
                    ],
                  ),
                ),
                // 사이드 클러스터 (홈=좌 / 어웨이=우)
                Positioned(
                  left: isHome ? 0 : null,
                  right: isHome ? null : 0,
                  top: 0, bottom: 0,
                  child: Center(child: sideCluster),
                ),
              ],
            ),
          ),
        );
      }

      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: isLast ? null : Border(bottom: BorderSide(color: lineRow, width: 1)),
        ),
        child: plays.isEmpty
            ? Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 84),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        logo,
                        const SizedBox(width: 6),
                        Text('득점', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ink2S)),
                      ],
                    ),
                  ),
                  Positioned(
                    left: isHome ? 0 : null,
                    right: isHome ? null : 0,
                    top: 0, bottom: 0,
                    child: Center(child: inningChip),
                  ),
                ],
              )
            : Column(children: [
                for (int i = 0; i < plays.length; i++) playRow(plays[i], i == 0),
              ]),
      );
    }).toList();

    final isDarkS = Theme.of(context).brightness == Brightness.dark;
    final lineS  = isDarkS ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);

    // 통합 카드 내부 콘텐츠 (06-13 병합) — 토글 헤더 제거(심미 보고), 구분선+rows 상시
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: lineS),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          child: Column(children: halfCards),
        ),
      ],
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
    final activeColor = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
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
      onSubTap = (i) => setState(() {
        _lineupSubIndex = i;
        _restorableLineupSub.value = i;
      });
    } else if (idx == 2) {
      subLabels = ['투수', '타자', '상대'];
      subIdx = _statsSubIndex;
      onSubTap = (i) => setState(() {
        _statsSubIndex = i;
        _restorableStatsSub.value = i;
      });
    }

    const mainLabels = ['중계', '라인업', '기록', '하이라이트'];
    const mainIcons = [
      Icons.live_tv_outlined,
      Icons.people_outline,
      Icons.bar_chart,
      Icons.video_library_outlined,
    ];

    // 플로팅 바 좌우 스와이프 → 인접 탭 이동 (2026-06-07)
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() < 150) return;
        final next = _tabController.index + (v < 0 ? 1 : -1);
        if (next < 0 || next >= _tabController.length) return;
        _tabController.animateTo(next);
      },
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (subLabels != null) ...[
          Container(
            height: 44,
            decoration: pillDeco(),
            child: LayoutBuilder(builder: (ctx, c) {
              final sl = subLabels!;
              final slotW = c.maxWidth / sl.length;
              return Stack(children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  left: subIdx * slotW + 4,
                  top: 4, bottom: 4, width: slotW - 8,
                  child: Container(decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20))),
                ),
                Row(children: List.generate(sl.length, (i) {
                  final sel = i == subIdx;
                  return Expanded(child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSubTap(i),
                    child: Center(child: Text(sl[i],
                      style: TextStyle(fontSize: 12,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                        color: sel ? activeColor : inactiveColor))),
                  ));
                })),
              ]);
            }),
          ),
          const SizedBox(height: 8),
        ],
        Container(
          height: 52,
          decoration: pillDeco(),
          child: LayoutBuilder(builder: (ctx, c) {
            final slotW = c.maxWidth / mainLabels.length;
            return Stack(children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: idx * slotW + 4,
                top: 4, bottom: 4, width: slotW - 8,
                child: Container(decoration: BoxDecoration(
                  color: activeColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(22))),
              ),
              Row(children: List.generate(mainLabels.length, (i) {
                final sel = i == idx;
                return Expanded(child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () { _tabController.animateTo(i); setState(() {}); },
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(mainIcons[i], size: 18, color: sel ? activeColor : inactiveColor),
                    const SizedBox(height: 1),
                    Text(mainLabels[i], style: TextStyle(fontSize: 11,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                      color: sel ? activeColor : inactiveColor, fontFamily: 'Pretendard')),
                  ]),
                ));
              })),
            ]);
          }),
        ),
      ],
      ),
    );
  }

  Widget _buildPreviewTab() {
    if (_gameData!['game']['status'] == '예정') {
      return const Center(child: Text('경기 시작 후 확인할 수 있습니다'));
    }
    if (_previewData == null) {
      return Center(child: CircularProgressIndicator(color: SemColor.brand(context), strokeWidth: 2.5));
    }

    final homeTeam = _gameData!['game']['home_team'];
    final awayTeam = _gameData!['game']['away_team'];
    final homeStarter = _previewData!['home_starter'];
    final awayStarter = _previewData!['away_starter'];
    final homeTop = _previewData!['home_top_player'];
    final awayTop = _previewData!['away_top_player'];
    // seasonVs 사용 안 함 (상대전적 섹션 삭제 — 2026-06-07)

    return SingleChildScrollView(
      // 하단 플로팅 탭(nav)에 가림 방지 — bottom 여유 패딩
      padding: EdgeInsets.fromLTRB(16, 16, 16, _navClearance),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // (시즌 상대전적 섹션 삭제 — 2026-06-07 요청)
          _rosterSectionHeader('선발 맞대결'),
          const SizedBox(height: 12),
          Stack(
            alignment: Alignment.center,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildStarterCard(homeStarter, homeTeam)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildStarterCard(awayStarter, awayTeam)),
                ],
              ),
              // 중앙 VS 칩 (맞대결 구도)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF26262C) : Colors.white,
                  borderRadius: BorderRadius.circular(Radii.pill),
                  border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF33333A) : const Color(0xFFE0E0E4)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)],
                ),
                child: Text('VS',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFFF4F4F5) : SemColor.panelDark)),
              ),
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
    final ink   = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
    final ink2  = isDark ? const Color(0xFFC9C9D1) : const Color(0xFF3F3F46);
    final ink3  = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    final sub   = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final paper = isDark ? const Color(0xFF18181C) : Colors.white;
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
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: ink, letterSpacing: 0)),
            Text(starter['hit_type'] ?? '',
                style: TextStyle(fontSize: 11, color: ink3, fontWeight: FontWeight.w600)),
            Container(height: 1, color: line, margin: const EdgeInsets.symmetric(vertical: 10)),
            Text('시즌 성적',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ink3, letterSpacing: 0.3)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  _statChip('평자', '${season['era'] ?? '-'}'),
                  const SizedBox(width: 13),
                  _statChip('승패', '${season['wins'] ?? 0}-${season['losses'] ?? 0}'),
                  const SizedBox(width: 13),
                  _statChip('이닝', season['innings'] ?? '-'),
                  const SizedBox(width: 13),
                  _statChip('삼진', '${season['kk'] ?? 0}'),
                  const SizedBox(width: 13),
                  _statChip('볼넷', '${season['bb'] ?? 0}'),
                ],
              ),
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
                          borderRadius: BorderRadius.circular(Radii.pill),
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
          ],
        ),
      ),
    );
  }

  Widget _buildTopPlayerCard(Map<String, dynamic>? top, String teamName) {
    if (top == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink   = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
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
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: ink, letterSpacing: 0)),
            Container(height: 1, color: line, margin: const EdgeInsets.symmetric(vertical: 10)),
            Text('시즌 성적',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ink3, letterSpacing: 0.3)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  _statChip('타율', '${season['avg'] ?? '-'}'),
                  const SizedBox(width: 13),
                  _statChip('홈런', '${season['hr'] ?? 0}'),
                  const SizedBox(width: 13),
                  _statChip('타점', '${season['rbi'] ?? 0}'),
                  const SizedBox(width: 13),
                  _statChip('출루율', '${season['obp'] ?? '-'}'),
                ],
              ),
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
                          borderRadius: BorderRadius.circular(Radii.pill),
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
    final ink = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
    final sub = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: sub, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ink,
            fontFeatures: const [FontFeature.tabularFigures()], letterSpacing: 0)),
      ],
    );
  }

  // 간소화 로스터 (2026-06-07): 팀 서브탭 제거 — 한 화면 좌우 2열, 이미지 없이 타순+이름+포지션
  Widget _buildRosterTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
    final ink3 = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    final sub = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final paper = isDark ? const Color(0xFF18181C) : Colors.white;
    final line = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
    if (_rosterData == null) {
      return Center(child: CircularProgressIndicator(color: ink, strokeWidth: 2.5));
    }

    final game = _gameData!['game'];

    Widget teamCol(String side) {
      final teamData = _rosterData![side] as Map<String, dynamic>;
      final code = game['${side}_team_code'] as String? ?? '';
      final name = game['${side}_team'] as String? ?? '';
      final batters = (teamData['batters'] as List? ?? []).cast<Map<String, dynamic>>();
      final pitchers = (teamData['pitchers'] as List? ?? []).cast<Map<String, dynamic>>();
      final starters = batters
          .where((b) => b['is_starter'] == true && (b['batting_order'] ?? 0) != 0)
          .toList()
        ..sort((a, b) => ((a['batting_order'] as num)).compareTo(b['batting_order'] as num));
      // 후보 야수 (선발 라인업 외)
      final benchNames = starters.map((b) => b['name']).toSet();
      final bench = batters
          .where((b) => b['is_starter'] != true && !benchNames.contains(b['name']))
          .toList();
      final sp = pitchers.where((p) => p['is_starter'] == true).toList();
      final spName = sp.isNotEmpty
          ? sp.first['name'] as String? ?? ''
          : (_previewData?['${side}_starter']?['name'] as String? ?? '');
      // 불펜 — 좌완/우완/언더·사이드 분류 (pitching_style 기반)
      final bullpen = pitchers.where((p) => p['is_starter'] != true && p['name'] != spName).toList();
      String bpClass(Map p) {
        final st = (p['pitching_style'] as String? ?? '');
        if (st.contains('언더') || st.contains('사이드')) return '언더·사이드';
        if (st.contains('좌')) return '좌완';
        if (st.contains('우')) return '우완';
        return '기타';
      }
      final bpGroups = <String, List<String>>{};
      for (final p in bullpen) {
        bpGroups.putIfAbsent(bpClass(p), () => []).add(p['name'] as String? ?? '');
      }
      if (bullpen.isNotEmpty) _loadBullpenStatus(); // 피로도 lazy 로드 (1회)

      Widget secLabel(String t) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Row(children: [
          Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sub, letterSpacing: 0.5)),
          const SizedBox(width: 6),
          Expanded(child: Container(height: 1, color: line)),
        ]),
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            TeamLogo(teamCode: code, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ink)),
            ),
          ]),
          // 선발투수 — 최상단 (등록 상태이므로 '선발' 라벨)
          if (spName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1976D2).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('선발',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF1976D2))),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(spName,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink)),
                ),
              ]),
            ),
          const SizedBox(height: 8),
          for (final b in starters)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(children: [
                SizedBox(
                  width: 16,
                  child: Text('${b['batting_order']}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: sub,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(b['name'] as String? ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ink)),
                ),
                Text(b['position'] as String? ?? '',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ink3)),
              ]),
            ),
          // 후보 야수
          if (bench.isNotEmpty) ...[
            secLabel('후보'),
            Text(bench.map((b) => b['name']).join(', '),
                style: TextStyle(fontSize: 11.5, height: 1.5, fontWeight: FontWeight.w500, color: ink3)),
          ],
          // 불펜 (좌완/우완/언더·사이드 — 피로도 신호등: 빨강=연투·과부하/주황=어제 등판)
          if (bpGroups.isNotEmpty) ...[
            secLabel('불펜'),
            Builder(builder: (_) {
              final teamId = _gameData?['game']?['${side}_team_id'] as int?;
              final fatigue = teamId != null ? _bullpenStatus[teamId] : null;
              final yellowC = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
              const redC = Color(0xFFE53935);
              bool anyMark = false;
              final groupWidgets = <Widget>[];
              for (final k in ['좌완', '우완', '언더·사이드', '기타']) {
                final names = bpGroups[k];
                if (names == null || names.isEmpty) continue;
                final spans = <TextSpan>[TextSpan(text: '$k) ')];
                for (var i = 0; i < names.length; i++) {
                  final st = fatigue?[names[i]];
                  final marked = st == 'red' || st == 'yellow';
                  if (marked) anyMark = true;
                  spans.add(TextSpan(
                      text: names[i],
                      style: TextStyle(
                          color: st == 'red' ? redC : (st == 'yellow' ? yellowC : ink3),
                          fontWeight: marked ? FontWeight.w700 : FontWeight.w500)));
                  if (i < names.length - 1) spans.add(const TextSpan(text: ', '));
                }
                groupWidgets.add(Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text.rich(TextSpan(
                      style: TextStyle(fontSize: 11.5, height: 1.5, fontWeight: FontWeight.w500, color: ink3),
                      children: spans)),
                ));
              }
              if (anyMark) {
                groupWidgets.add(Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text.rich(TextSpan(
                    style: TextStyle(fontSize: 9, color: sub),
                    children: [
                      const TextSpan(text: '●', style: TextStyle(color: redC)),
                      const TextSpan(text: ' 연투·과부하   '),
                      TextSpan(text: '●', style: TextStyle(color: yellowC)),
                      const TextSpan(text: ' 어제 등판'),
                    ],
                  )),
                ));
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: groupWidgets);
            }),
          ],
        ],
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, _navClearance),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: line, width: 1),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: teamCol('home')),
              Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 12), color: line),
              Expanded(child: teamCol('away')),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
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

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, _navClearance),
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
              color: Colors.orange.withValues(alpha: 0.05),
              border: Border(bottom: BorderSide(color: Color(0xFFEDEDF0))),
            ),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  netCircleAvatar(
                    radius: 18,
                    url: starterPitcher['profile_image'] as String?,
                    child: const Icon(Icons.person, size: 18),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
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
        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1F1F24) : SemColor.panelDark,
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
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.6)),
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
          netCircleAvatar(
            radius: 18,
            url: b['profile_image'] as String?,
            child: const Icon(Icons.person, size: 18),
          ),
          const SizedBox(width: 6),
          CircleAvatar(
            radius: 12,
            backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1F1F24) : SemColor.panelDark,
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
      leading: netCircleAvatar(
        radius: 18,
        url: profileImage,
        child: const Icon(Icons.person, size: 18),
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
    final homeTeam = _gameData!['game']['home_team'];
    final awayTeam = _gameData!['game']['away_team'];

    // 상단 fixed 승/패/세이브 패널 제거 (2026-06-07) — 행 인라인 결과 칩으로 충분,
    // 고정 영역이 리스트를 압박해 기록 열람 불편
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            indicatorColor: SemColor.brand(context),
            indicatorWeight: 2.5,
            labelColor: SemColor.brand(context),
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
        ],
      ),
    );
  }

  Widget _buildPitcherList(List pitchers) {
    // 투구위치 버튼: fixed 하단 → 리스트 마지막 항목 (스크롤 동행, 리스트 풀 높이 확보)
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, _navClearance),
      children: [
        ...pitchers.map((p) {
          final pm = p as Map<String, dynamic>;
          final playerId = pm['player_id'] as int?;
          if (playerId == null) return _pitcherTile(pm);
          return InkWell(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: playerId))),
            child: _pitcherTile(pm),
          );
        }),
        Padding(
          padding: const EdgeInsets.only(top: 12),
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
        leading: netCircleAvatar(
          radius: 20,
          url: profileImage,
          child: const Icon(Icons.person, size: 20),
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
                  color: resultColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: resultColor.withValues(alpha: 0.5)),
                ),
                child: Text(result,
                    style: TextStyle(
                        fontSize: 11,
                        color: resultColor,
                        fontWeight: FontWeight.bold)),
              ),
            if (pitchCount > 0) ...[
              const SizedBox(width: 6),
              Text('$pitchCount구',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
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
            indicatorColor: SemColor.brand(context),
            indicatorWeight: 2.5,
            labelColor: SemColor.brand(context),
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

    final bNavBottom = _navClearance;
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
                  netCircleAvatar(
                    radius: 18,
                    url: profileImage,
                    child: const Icon(Icons.person, size: 18),
                  ),
                  const SizedBox(width: 6),
                  isFirst
                      ? CircleAvatar(
                          radius: 12,
                          backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1F1F24) : SemColor.panelDark,
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
      return Center(child: CircularProgressIndicator(color: SemColor.brand(context), strokeWidth: 2.5));
    }

    final keyStats = _recordDetailData!['key_stats'] as Map<String, dynamic>? ?? {};
    final teamPitching = _recordDetailData!['team_pitching'] as Map<String, dynamic>? ?? {};
    final etcRecords = _recordDetailData!['etc_records'] as List? ?? [];
    final homeTeam = _gameData!['game']['home_team'];
    final awayTeam = _gameData!['game']['away_team'];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rdNavBottom = _navClearance;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, rdNavBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rosterSectionHeader('주요 기록'),
          const SizedBox(height: 12),
          Table(
            border: TableBorder.all(color: isDark ? const Color(0xFF26262C) : const Color(0xFFE0E0E4)),
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1.5),
              2: FlexColumnWidth(1.5),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(color: isDark ? const Color(0xFF1F1F24) : SemColor.panelDark),
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
            border: TableBorder.all(color: isDark ? const Color(0xFF26262C) : const Color(0xFFE0E0E4)),
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1.5),
              2: FlexColumnWidth(1.5),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(color: isDark ? const Color(0xFF1F1F24) : SemColor.panelDark),
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
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                      child: Text(type,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFF4F4F5) : SemColor.panelDark)),
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
      } catch (e) { debugPrint('game_detail: $e'); }
      // 2) vnd.youtube:VIDEO_ID (콜론만, 슬래시 X)
      final m = RegExp(r'(?:v=|/shorts/|youtu\.be/)([A-Za-z0-9_-]{11})').firstMatch(url);
      final vid = m?.group(1);
      if (vid != null) {
        try {
          final appUri = Uri.parse('vnd.youtube:$vid');
          final ok = await launchUrl(appUri, mode: LaunchMode.externalNonBrowserApplication);
          if (ok) return;
        } catch (e) { debugPrint('game_detail: $e'); }
      }
    }
    // 3) fallback: 외부 브라우저
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) { debugPrint('game_detail: $e'); }
  }

  Widget _buildHighlightsTab() {
    final isDarkT = Theme.of(context).brightness == Brightness.dark;
    final ink   = isDarkT ? const Color(0xFFF4F4F5) : SemColor.panelDark;
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
        final source = h['source'] as String? ?? '';
        final published = h['published_at']?.toString() ?? '';
        final isShorts = url.contains('/shorts/');
        final isYT = url.contains('youtu');

        String relTime() {
          try {
            final dt = DateTime.parse(published).toLocal();
            final diff = DateTime.now().difference(dt);
            if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
            if (diff.inHours < 24) return '${diff.inHours}시간 전';
            return '${diff.inDays}일 전';
          } catch (_) {
            return '';
          }
        }

        Widget sourceChip() => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isYT ? const Color(0xFFE53935).withValues(alpha: 0.12) : paper2,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(isYT ? Icons.play_circle_fill : Icons.article_outlined,
                size: 10, color: isYT ? const Color(0xFFE53935) : ink3),
            const SizedBox(width: 3),
            Text(isYT ? 'YouTube' : (source.isNotEmpty ? source : '뉴스'),
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700,
                    color: isYT ? const Color(0xFFE53935) : ink3)),
          ]),
        );

        Widget metaRow() => Row(children: [
          sourceChip(),
          const Spacer(),
          Text(relTime(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: sub)),
        ]);

        // ── 첫 항목: 히어로 카드 (대형 썸네일) ──
        if (idx == 0) {
          return GestureDetector(
            onTap: () => _openYouTube(url),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: paper,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: line, width: 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      thumbnail.isNotEmpty
                          ? netImage(
                              thumbnail,
                              width: double.infinity,
                              height: isShorts ? 180 : 160,
                              fit: isShorts ? BoxFit.contain : BoxFit.cover,
                              placeholder: () => Container(height: isShorts ? 180 : 160, color: paper2),
                              error: () => Container(
                                height: isShorts ? 180 : 160, color: paper2,
                                child: Icon(Icons.broken_image, color: sub),
                              ),
                            )
                          : Container(
                              height: 120, width: double.infinity, color: paper2,
                              child: Center(child: Icon(Icons.play_circle_outline, color: ink3, size: 36)),
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
                              borderRadius: BorderRadius.circular(Radii.pill),
                            ),
                            child: const Text('Shorts',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: ink, letterSpacing: 0, height: 1.3)),
                        const SizedBox(height: 8),
                        metaRow(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // ── 나머지: 컴팩트 가로 행 (좌측 썸네일 110x62) ──
        return GestureDetector(
          onTap: () => _openYouTube(url),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: paper,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: line, width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                SizedBox(
                  width: 110, height: 66,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      thumbnail.isNotEmpty
                          ? netImage(
                              thumbnail,
                              width: 110, height: 66, fit: BoxFit.cover,
                              placeholder: () => Container(color: paper2),
                              error: () => Container(color: paper2,
                                  child: Icon(Icons.broken_image, size: 18, color: sub)),
                            )
                          : Container(color: paper2,
                              child: Icon(Icons.play_circle_outline, color: ink3, size: 24)),
                      Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 15),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink, letterSpacing: 0, height: 1.3)),
                        const SizedBox(height: 5),
                        metaRow(),
                      ],
                    ),
                  ),
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
      if (homeUrl != null && mounted) await precacheImage(netImageProvider(homeUrl), context);
      if (awayUrl != null && mounted) await precacheImage(netImageProvider(awayUrl), context);
      if (winImgUrl != null && mounted) await precacheImage(netImageProvider(winImgUrl), context);
      if (loseImgUrl != null && mounted) await precacheImage(netImageProvider(loseImgUrl), context);
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
                    side: BorderSide(color: SemColor.brand(context)),
                    foregroundColor: SemColor.brand(context),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _sharing ? null : _captureAndShare,
                  icon: _sharing
                      ? SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? SemColor.panelDark : Colors.white))
                      : const Icon(Icons.image, size: 16),
                  label: const Text('이미지 공유'),
                  // bg/fg는 글로벌 theme-aware 버튼 상속 (다크 윤곽소실 방지)
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
          colors: [SemColor.panelDark, Color(0xFF283593)],
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
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor.withValues(alpha: 0.5)),
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
              color: Colors.white.withValues(alpha: 0.08),
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
                    _pitcherChip('승 $winPitcher', Colors.blue.shade300, imageUrl: webSafeImageUrl(g['win_pitcher_image'] as String?)),
                  if (winPitcher != null && losePitcher != null)
                    const SizedBox(width: 8),
                  if (losePitcher != null)
                    _pitcherChip('패 $losePitcher', Colors.red.shade300, imageUrl: webSafeImageUrl(g['lose_pitcher_image'] as String?)),
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
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          netCircleAvatar(
            radius: 10,
            backgroundColor: color.withValues(alpha: 0.2),
            url: imageUrl,
            child: Icon(Icons.person, size: 11, color: color),
          ),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─── 자동 스크롤 텍스트 (한 줄 초과 시 좌로 무한 회전 — 중계 긴 문장용) ────────
class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _MarqueeText({required this.text, required this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      final textW = painter.width;
      if (!c.hasBoundedWidth || textW <= c.maxWidth) {
        _ctrl?.stop();
        return Text(widget.text,
            maxLines: 1, softWrap: false, overflow: TextOverflow.clip,
            style: widget.style);
      }
      const gap = 42.0;
      final span = textW + gap;
      // 속도 ~28px/s — 길이 비례 주기
      final dur = Duration(milliseconds: (span / 28 * 1000).round());
      _ctrl ??= AnimationController(vsync: this);
      if (_ctrl!.duration != dur) {
        _ctrl!
          ..duration = dur
          ..repeat();
      } else if (!_ctrl!.isAnimating) {
        _ctrl!.repeat();
      }
      return ClipRect(
        child: SizedBox(
          width: c.maxWidth,
          height: painter.height,
          child: AnimatedBuilder(
            animation: _ctrl!,
            builder: (_, __) => Transform.translate(
              offset: Offset(-span * _ctrl!.value, 0),
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(widget.text,
                      maxLines: 1, softWrap: false, style: widget.style),
                  const SizedBox(width: gap),
                  Text(widget.text,
                      maxLines: 1, softWrap: false, style: widget.style),
                  const SizedBox(width: gap),
                ]),
              ),
            ),
          ),
        ),
      );
    });
  }
}

// ─── Full field view widget ───────────────────────────────────────────────────

class _FullFieldView extends StatelessWidget {
  final bool base1, base2, base3, isDark;
  final Map<String, dynamic>? fieldView;
  final String? matchupLine; // 현재 타석 맞대결 통산 (좌하단 오버레이)

  const _FullFieldView({
    required this.base1, required this.base2, required this.base3,
    required this.isDark, this.fieldView, this.matchupLine,
  });

  static const _baseLabel = {
    'base1': '1루',
    'base2': '2루',
    'base3': '3루',
    'batter': '타석',
  };

  void _showBaseSheet(BuildContext ctx, String baseKey, Map<String, dynamic>? p, bool isOccupied) {
    final baseName = _baseLabel[baseKey] ?? baseKey;
    final hasRunner = p != null && (p['name'] as String? ?? '').isNotEmpty;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: isDark ? const Color(0xFF18181C) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(ctx).viewPadding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 32, height: 4,
              margin: const EdgeInsets.only(bottom: 12, left: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isOccupied ? const Color(0xFFFCD34D) : (isDark ? Colors.white12 : Colors.black12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(baseName,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                        color: isOccupied ? Colors.black87 : (isDark ? Colors.white70 : Colors.black54))),
              ),
              const SizedBox(width: 8),
              Text(isOccupied ? '주자 점거' : '비어있음',
                  style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black54)),
            ]),
            const SizedBox(height: 12),
            if (hasRunner) ...[
              Row(children: [
                _PlayerDot(
                  name: '',
                  imageUrl: webSafeImageUrl(p['image'] as String?),
                  label: '',
                  isOffense: true, isDark: isDark, size: 44,
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p['name'] as String? ?? '',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : Colors.black87)),
                    if ((p['position'] as String? ?? '').isNotEmpty)
                      Text(p['position'] as String,
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54)),
                  ],
                )),
              ]),
            ] else ...[
              Text(isOccupied ? '주자 정보 없음' : '점거된 주자가 없습니다',
                  style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54)),
            ],
          ],
        ),
      ),
    );
  }

  // Normalized (x,y) coordinates on the field widget (0=left/top, 1=right/bottom)
  // SVG 300x310 좌표계 (mockup과 동일) — placed() 에서 painter transform 적용
  static const Map<String, Offset> _posCoords = {
    'P':  Offset(150, 208),   // 투수 (마운드)
    'C':  Offset(150, 283),   // 포수
    '1B': Offset(220, 186),   // 1루수 (위로 10)
    '2B': Offset(183, 153),   // 2루수
    'SS': Offset(117, 153),   // 유격수
    '3B': Offset(80,  186),   // 3루수
    'LF': Offset(64,  118),   // 좌익수 (밑으로 8)
    'CF': Offset(150, 92),    // 중견수 (BSO 오버레이 겹침 회피로 살짝 내림)
    'RF': Offset(236, 118),   // 우익수
    'DH': Offset(30,  280),   // 지명타자 (벤치)
  };
  static const Map<String, Offset> _baseCoords = {
    // 주자 dot = painter 베이스 중심 (_kMB1/2/3) 정확히 일치
    'base1':  Offset(208, 208),   // 1루 주자
    'base2':  Offset(150, 150),   // 2루 주자
    'base3':  Offset(92,  208),   // 3루 주자
    'batter': Offset(132, 262),   // 타자 우타석 (좌타는 build에서 x mirror → 168)
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
    final nextBatter = fieldView?['next_batter'] as Map<String, dynamic>?;
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

      // painter transform 동일 적용 (SVG 300x310 → canvas)
      const svgVisTop = 66.0;
      const svgVisH = 230.0;
      const svgW = 300.0;
      // painter와 동일 stretch(sx/sy) — 마커가 다이아몬드와 정합. 고정 size라 가독 유지.
      final sx = w / svgW;
      final sy = h / svgVisH;

      Widget placed(Offset svgPos, Widget child, double chipW, double chipH) {
        final cx = svgPos.dx * sx;
        final cy = (svgPos.dy - svgVisTop) * sy;
        return Positioned(
          left: (cx - chipW / 2).clamp(0, w - chipW),
          top:  (cy - chipH / 2).clamp(0, h - chipH),
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
            imageUrl: webSafeImageUrl(p['image'] as String?),
            label: label,
            isOffense: false,
            isDark: isDark,
            size: 24,
          ),
          68, 50,
        ));
      }

      Widget runnerWidget(Map<String, dynamic>? p, String baseKey, bool isOccupied) {
        final coord = _baseCoords[baseKey]!;
        final runnerName = p?['name'] as String? ?? '';
        return placed(coord,
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showBaseSheet(ctx, baseKey, p, isOccupied),
            child: _PlayerDot(
              name: runnerName,
              imageUrl: webSafeImageUrl(p?['image'] as String?),
              label: '',
              isOffense: true,
              isDark: isDark,
              size: 26,
            ),
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
              // 좌타/양타 → 좌타석(168) mirror, 우타 → 우타석(132). 홈플레이트 x=150 대칭
              ((batter['bats'] as String? ?? '').startsWith('좌') ||
                      (batter['bats'] as String? ?? '').startsWith('양'))
                  ? const Offset(168, 262)
                  : _baseCoords['batter']!,
              _PlayerDot(
                name: batter['name'] as String? ?? '',
                imageUrl: webSafeImageUrl(batter['image'] as String?),
                label: '타자',
                isOffense: true,
                isDark: isDark,
                size: 26,
                isBatter: true,
              ),
              68, 40,
            ),
          // ── 맞대결 통산 오버레이 (좌상단 — 좌하단은 지명타자(DH 벤치 30,280) 자리라 가림) ──
          if (matchupLine != null && batter != null && pitcher != null)
            Positioned(
              left: 4, top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('맞대결 통산',
                        style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 1),
                    Text(
                      matchupLine!,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          // ── 다음 타석 오버레이 (우하단, 2층 텍스트) ──
          if (nextBatter != null)
            Positioned(
              right: 4, bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('다음타석',
                        style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 1),
                    Text(
                      '${nextBatter['order'] != null ? '${nextBatter['order']}번 타자 ' : ''}${nextBatter['name'] ?? ''}',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
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
        ? const Color(0xFFE65100).withValues(alpha: 0.90)
        : isOffense
            ? const Color(0xFFBF360C).withValues(alpha: 0.90)
            : const Color(0xFF0D47A1).withValues(alpha: 0.90);
    final Color borderColor = isBatter
        ? Colors.yellow[300]!
        : isOffense ? Colors.orange[300]! : Colors.lightBlue[200]!;
    final Color textColor = isOffense ? Colors.orange[100]! : Colors.lightBlue[100]!;
    final Color labelBg = isOffense
        ? Colors.orange[900]!.withValues(alpha: 0.85)
        : Colors.indigo[900]!.withValues(alpha: 0.85);

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
                style: TextStyle(fontSize: 8, color: textColor, fontWeight: FontWeight.bold),
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
                color: borderColor.withValues(alpha: 0.5),
                blurRadius: isOffense ? 6 : 4,
                spreadRadius: 0.5,
              )],
            ),
            child: ClipOval(
              child: imageUrl != null && imageUrl!.isNotEmpty
                  ? netImage(
                      imageUrl!,
                      fit: BoxFit.cover,
                      error: () => Icon(Icons.person, size: size * 0.55, color: Colors.white70),
                      placeholder: () => Container(color: Colors.black26),
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
                  fontSize: 9,
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

// 좌표 상수 (SVG 300x310 viewBox)
const double _kFieldW    = 300, _kFieldH    = 310;
const double _kHX        = 150, _kHY        = 278;   // 파울라인 원점
const double _kHVX       = 150, _kHVY       = 266;   // 베이스패스 홈 꼭짓점
const double _kMB1X      = 208, _kMB1Y      = 208;   // 1루
const double _kMB2X      = 150, _kMB2Y      = 150;   // 2루
const double _kMB3X      = 92,  _kMB3Y      = 208;   // 3루
const double _kPMX       = 150, _kPMY       = 208;   // 투수판
const double _kROut     = 212;
const double _kRDirt    = 132;
const double _kRHome    = 30;
const double _kRBase    = 17;
const double _kRMound   = 18;

class _FieldBgPainter extends CustomPainter {
  final bool base1, base2, base3, isDark;
  const _FieldBgPainter({required this.base1, required this.base2, required this.base3, required this.isDark});

  Offset _pt(double deg, double r) {
    final a = deg * math.pi / 180;
    return Offset(_kHX + r * math.sin(a), _kHY - r * math.cos(a));
  }

  Path _sector(double d1, double d2, double r) {
    final p1 = _pt(d1, r);
    final p2 = _pt(d2, r);
    final big = (d2 - d1).abs() > 180;
    return Path()
      ..moveTo(_kHX, _kHY)
      ..lineTo(p1.dx, p1.dy)
      ..arcToPoint(p2, radius: Radius.circular(r), clockwise: true, largeArc: big)
      ..close();
  }

  Path get _fairClip => Path()
    ..moveTo(_kHX, _kHY)
    ..lineTo(0, _kHY - _kHX)
    ..lineTo(0, 0)
    ..lineTo(_kFieldW, 0)
    ..lineTo(_kFieldW, _kHY - _kHX)
    ..close();

  Paint _dirtPaint(Rect rect) => Paint()
    ..shader = const RadialGradient(
      center: Alignment(0, -0.2),
      radius: 0.72,
      colors: [Color(0xFFD2B083), Color(0xFFBD9763)],
    ).createShader(rect);

  Path _rotated45(Path path, double cx, double cy) {
    final m = Matrix4.identity()
      ..translateByDouble(cx, cy, 0.0, 1.0)
      ..rotateZ(math.pi / 4)
      ..translateByDouble(-cx, -cy, 0.0, 1.0);
    return path.transform(m.storage);
  }

  void _drawBase(Canvas canvas, double bx, double by, bool on) {
    if (on) {
      final hlPath = _rotated45(
        Path()..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(bx, by), width: 26, height: 26),
            const Radius.circular(3),
          ),
        ),
        bx, by,
      );
      canvas.drawPath(hlPath, Paint()..color = const Color(0xFFF59E0B).withValues(alpha: 0.4));
    }
    final basePath = _rotated45(
      Path()..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(bx, by), width: 12, height: 12),
          const Radius.circular(2),
        ),
      ),
      bx, by,
    );
    canvas.drawPath(basePath, Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
    canvas.drawPath(
      basePath,
      Paint()..color = on ? const Color(0xFFFCD34D) : Colors.white,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // visible content 영역만 fit (외야 stripe top y=66 ~ 홈베이스 dirt bottom y=296)
    // 위/아래 배경 dead space 제거 → field 자체 확장
    const svgVisTop = 66.0;
    const svgVisH   = 230.0;  // 296 - 66
    // stretch(비균일 sx/sy) — 박스를 꽉 채움(세로 약간 압축 허용). crop/좌우여백 제거 (06-14).
    final sx = size.width / _kFieldW;
    final sy = size.height / svgVisH;
    canvas.save();
    canvas.translate(0, -svgVisTop * sy);
    canvas.scale(sx, sy);

    // 1. 배경 (파울 지역 어두운 잔디)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, _kFieldW, _kFieldH),
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, 0.1),
          radius: 0.75,
          colors: [Color(0xFF356030), Color(0xFF264821)],
        ).createShader(Rect.fromLTWH(0, 0, _kFieldW, _kFieldH)),
    );

    // 2. 외야 잔디 mowing stripe
    const stripeColors = [Color(0xFF54944A), Color(0xFF4C8A42)];
    for (int i = 0; i < 9; i++) {
      canvas.drawPath(
        _sector(-45 + i * 10.0, -45 + (i + 1) * 10.0, _kROut),
        Paint()..color = stripeColors[i % 2],
      );
    }

    // 3. 내야 흙 부채꼴
    final dirtRect = Rect.fromCenter(
      center: Offset(_kHX, _kHY),
      width: _kRDirt * 2, height: _kRDirt * 2,
    );
    canvas.drawPath(_sector(-45, 45, _kRDirt), _dirtPaint(dirtRect));

    // 4. 내야 잔디 다이아몬드 (정사각)
    canvas.drawPath(
      Path()
        ..moveTo(150, 162)
        ..lineTo(196, 208)
        ..lineTo(150, 254)
        ..lineTo(104, 208)
        ..close(),
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, 0.2),
          radius: 0.68,
          colors: [Color(0xFF57994C), Color(0xFF4A8741)],
        ).createShader(Rect.fromLTWH(104, 162, 92, 92)),
    );

    // 5. 베이스패스 + 1·3루 흙 서클 (페어 클리핑)
    canvas.save();
    canvas.clipPath(_fairClip);

    canvas.drawPath(
      Path()
        ..moveTo(_kHVX, _kHVY)
        ..lineTo(_kMB1X, _kMB1Y)
        ..lineTo(_kMB2X, _kMB2Y)
        ..lineTo(_kMB3X, _kMB3Y)
        ..close(),
      Paint()
        ..color = const Color(0xFFBD9763)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(Offset(_kMB1X, _kMB1Y), _kRBase,
        Paint()..color = const Color(0xFFBD9763));
    canvas.drawCircle(Offset(_kMB3X, _kMB3Y), _kRBase,
        Paint()..color = const Color(0xFFBD9763));
    canvas.restore();

    // 6. 2루 흙 서클 (내야 흙 부채꼴 클리핑)
    canvas.save();
    canvas.clipPath(_sector(-45, 45, _kRDirt));
    canvas.drawCircle(Offset(_kMB2X, _kMB2Y), _kRBase,
        Paint()..color = const Color(0xFFBD9763));
    canvas.restore();

    // 7. 투수 마운드 + rubber
    canvas.drawCircle(Offset(_kPMX, _kPMY), _kRMound,
        Paint()..color = const Color(0xFFBD9763));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(_kPMX - 8, _kPMY - 2.5, 16, 5),
        const Radius.circular(1.5),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );

    // 8. 파울라인
    final foulPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(_kHX, _kHY), Offset(0, _kHY - _kHX), foulPaint);
    canvas.drawLine(Offset(_kHX, _kHY), Offset(_kFieldW, _kHY - _kHX), foulPaint);

    // 9. 베이스 (2루 먼저 → 1, 3루 위로 overlay 방지)
    _drawBase(canvas, _kMB2X, _kMB2Y, base2);
    _drawBase(canvas, _kMB1X, _kMB1Y, base1);
    _drawBase(canvas, _kMB3X, _kMB3Y, base3);

    // 10. 홈 흙 서클
    canvas.drawCircle(Offset(_kHVX, _kHVY), _kRHome,
        Paint()..color = const Color(0xFFBD9763));

    // 11. 홈플레이트 오각형
    canvas.drawPath(
      Path()
        ..moveTo(_kHVX,      _kHVY + 8)
        ..lineTo(_kHVX + 8,  _kHVY + 1)
        ..lineTo(_kHVX + 8,  _kHVY - 7)
        ..lineTo(_kHVX - 8,  _kHVY - 7)
        ..lineTo(_kHVX - 8,  _kHVY + 1)
        ..close(),
      Paint()..color = Colors.white,
    );

    // 12. 타자석
    final batterPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(_kHVX - 24, _kHVY - 11, 12, 18),
        const Radius.circular(1.5),
      ),
      batterPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(_kHVX + 12, _kHVY - 11, 12, 18),
        const Radius.circular(1.5),
      ),
      batterPaint,
    );

    canvas.restore();
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
    final fullPath = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    // mockup inner painter와 동일 색상 (분리 보이지 않게)
    final grassBase = Paint()
      ..shader = ui.Gradient.radial(
        Offset(w * 0.5, h * 0.55), w * 0.75,
        [const Color(0xFF356030), const Color(0xFF264821)],
      );
    canvas.save();
    canvas.clipPath(fullPath);
    canvas.drawPath(fullPath, grassBase);
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

// ─── 승리확률 그래프 (타석별 시계열 — 인게임 모델/Naver 승률) ──────────────────
class _WinProbChart extends StatelessWidget {
  final List<Map> series;
  final double? finalProb;
  final Color homeColor;
  final String homeName, awayName;
  final bool isLive, isDark;

  const _WinProbChart({
    required this.series, required this.finalProb,
    required this.homeColor, required this.homeName, required this.awayName,
    required this.isLive, required this.isDark,
  });

  static const Map<String, String> _resultKo = {
    'single': '안타', 'double': '2루타', 'triple': '3루타', 'hr': '홈런',
    'bb': '볼넷', 'ibb': '고의4구', 'hbp': '사구', 'so': '삼진',
    'out': '아웃', 'sac_bunt': '희생번트', 'sac_fly': '희생플라이',
    'error': '실책', 'fc': '야수선택', 'reach_other': '출루',
  };

  @override
  Widget build(BuildContext context) {
    final paper = isDark ? const Color(0xFF18181C) : Colors.white;
    final line = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
    final ink = isDark ? const Color(0xFFF4F4F5) : const Color(0xFF111113);
    final sub = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final hc = isDark ? Color.lerp(homeColor, Colors.white, 0.25)! : homeColor;

    final spots = <FlSpot>[];
    for (var i = 0; i < series.length; i++) {
      final p = (series[i]['prob'] as num?)?.toDouble();
      if (p != null) spots.add(FlSpot(i.toDouble(), p));
    }
    if (finalProb != null && spots.isNotEmpty) {
      spots.add(FlSpot(spots.length.toDouble(), finalProb!));
    }
    if (spots.length < 5) return const SizedBox.shrink();

    // 이닝 경계 x 위치 → 하단 라벨
    final inningTicks = <int, int>{};
    int? prevInning;
    for (var i = 0; i < series.length; i++) {
      final inn = series[i]['inning'] as int?;
      if (inn != null && inn != prevInning) {
        inningTicks[i] = inn;
        prevInning = inn;
      }
    }

    final lastProb = spots.last.y;
    final homeLeading = lastProb >= 50;
    final headLabel = isLive
        ? '$homeName ${lastProb.toStringAsFixed(0)}%'
        : (finalProb != null
            ? '${finalProb! >= 50 ? homeName : awayName} 승리'
            : '$homeName ${lastProb.toStringAsFixed(0)}%');

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('승리 확률',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ink)),
              const SizedBox(width: 6),
              Text('타석별 · $awayName vs $homeName',
                  style: TextStyle(fontSize: 9.5, color: sub)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (homeLeading ? hc : sub).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(headLabel,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                        color: homeLeading ? hc : ink)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 104, // 승률그래프 — 130서 하향 (정보밀도 대비 과점유 피드백)
            child: LineChart(
              LineChartData(
                minY: 0, maxY: 100,
                minX: 0, maxX: (spots.length - 1).toDouble(),
                clipData: const FlClipData.all(),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                extraLinesData: ExtraLinesData(horizontalLines: [
                  HorizontalLine(
                    y: 50,
                    color: sub.withValues(alpha: 0.35),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ]),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 16,
                      interval: 1,
                      getTitlesWidget: (v, meta) {
                        final inn = inningTicks[v.toInt()];
                        if (inn == null) return const SizedBox.shrink();
                        return Text('$inn',
                            style: TextStyle(fontSize: 8.5, color: sub, fontWeight: FontWeight.w600));
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) =>
                        isDark ? const Color(0xFF26262C) : const Color(0xFF111113),
                    getTooltipItems: (touched) => touched.map((t) {
                      final i = t.x.toInt();
                      if (i >= series.length) {
                        return LineTooltipItem('최종',
                            const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700));
                      }
                      final s = series[i];
                      final half = (s['half']?.toString() ?? '0') == '0' ? '초' : '말';
                      final res = _resultKo[s['result']] ?? '';
                      return LineTooltipItem(
                        '${s['inning']}회$half ${s['batter'] ?? ''} $res\n$homeName ${t.y.toStringAsFixed(1)}%',
                        const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: false,
                    barWidth: 2,
                    color: hc,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [hc.withValues(alpha: 0.18), hc.withValues(alpha: 0.02)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Text('↑ $homeName', style: TextStyle(fontSize: 8.5, color: hc, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text('↓ $awayName', style: TextStyle(fontSize: 8.5, color: sub)),
              const Spacer(),
              Text('숫자 = 이닝', style: TextStyle(fontSize: 8.5, color: sub)),
            ],
          ),
        ],
      ),
    );
  }
}
