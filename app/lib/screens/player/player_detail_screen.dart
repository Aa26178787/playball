import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../utils/design_tokens.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shimmer/shimmer.dart';
import '../../api/api_service.dart';
import '../../utils/local_cache.dart';
import 'player_compare_screen.dart';
import '../../utils/team_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/common_widgets.dart';

class PlayerDetailScreen extends StatefulWidget {
  final int playerId;
  /// 리스트에서 넘어온 기본 데이터 (name, team, profile_image, player_type, position, number)
  /// 제공 시 헤더 즉시 표시, 스탯은 백그라운드 로드
  final Map<String, dynamic>? initialData;
  const PlayerDetailScreen({super.key, required this.playerId, this.initialData});

  @override
  State<PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends State<PlayerDetailScreen> {
  Map<String, dynamic>? _playerData;
  List<dynamic> _dailyStats = [];
  Map<String, dynamic>? _pitchStats;
  // 피칭 디자인 (구종별 5x5 존 분포)
  Map<String, dynamic>? _pitchDesign;
  String _pdStance = ''; // '' 전체 / 'R' vs우타 / 'L' vs좌타
  String? _pdType;       // 선택 구종 (null = 최다 구종)

  Future<void> _loadPitchDesign() async {
    try {
      final d = await ApiService.getPitchDesign(widget.playerId, stance: _pdStance);
      if (mounted) setState(() => _pitchDesign = d);
    } catch (e) { debugPrint('player_detail: $e'); }
  }

  // 타자 존 히트맵
  Map<String, dynamic>? _batterZones;
  String _bzThrows = '';      // '' 전체 / 'R' vs우투 / 'L' vs좌투
  String _bzMetric = 'dist';  // dist(피투구) / whiff(헛스윙률) / avg(타율)

  Future<void> _loadBatterZones() async {
    try {
      final d = await ApiService.getBatterZones(widget.playerId, throws: _bzThrows);
      if (mounted) setState(() => _batterZones = d);
    } catch (e) { debugPrint('player_detail: $e'); }
  }

  // 투수 존 히트맵 (피투구 분포 / 피안타율)
  Map<String, dynamic>? _pitcherZones;
  String _pzStance = '';     // '' 전체 / 'R' vs우타 / 'L' vs좌타
  String _pzMetric = 'dist'; // dist(피투구 분포) / avg(피안타율)

  Future<void> _loadPitcherZones() async {
    try {
      final d = await ApiService.getPitcherZones(widget.playerId, stance: _pzStance);
      if (mounted) setState(() => _pitcherZones = d);
    } catch (e) { debugPrint('player_detail: $e'); }
  }

  Future<void> _loadDaily() async {
    try {
      final dailyData = await ApiService.getPlayerDaily(widget.playerId, season: 2026);
      LocalCache.set(_dailyCacheKey, dailyData).catchError((_) {});
      if (mounted) setState(() => _dailyStats = dailyData['daily'] ?? []);
    } catch (e) { debugPrint('player_detail: $e'); }
  }

  Future<void> _loadPitchStats() async {
    try {
      final ps = await ApiService.getPlayerPitchStats(widget.playerId);
      if (mounted) setState(() => _pitchStats = ps);
    } catch (e) { debugPrint('player_detail: $e'); }
  }
  bool _isLoading = true;   // 전체 shimmer (initialData 없을 때)
  bool _bodyLoading = false; // 바디 shimmer (initialData 있어서 헤더만 먼저 표시할 때)
  bool _isFav = false;
  bool _favLoading = false;
  bool _voted = false;       // 인기투표 (하트)
  int _voteCount = 0;
  String _hitterTrendStat = 'avg';
  String _pitcherTrendStat = 'era';

  @override
  void initState() {
    super.initState();
    // initialData 있으면 헤더만 즉시 표시, 바디는 shimmer 유지
    if (widget.initialData != null) {
      final d = widget.initialData!;
      _playerData = <String, dynamic>{
        ...d,
        if (!d.containsKey('team'))
          'team': d['team_name'] ?? d['team_code'] ?? '',
      };
      _isLoading = false;
      _bodyLoading = true; // 바디(스탯/기본정보)는 API 완료 후 표시
    }
    _loadPlayer();
    _loadFavStatus();
    _loadVoteStatus();
    _loadCoreKeys();
  }

  Future<void> _loadVoteStatus() async {
    try {
      final s = await ApiService.getPlayerVoteStatus(widget.playerId);
      if (mounted) {
        setState(() {
          _voted = s['voted'] as bool? ?? false;
          _voteCount = s['vote_count'] as int? ?? 0;
        });
      }
    } catch (e) { debugPrint('player_detail: $e'); }
  }

  Future<void> _toggleVote() async {
    try {
      final res = await ApiService.votePlayer(widget.playerId);
      if (mounted) {
        setState(() {
          _voted = res['voted'] as bool? ?? _voted;
          _voteCount = res['vote_count'] as int? ?? _voteCount;
        });
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final code = e.response?.statusCode;
      final msg = (code == 401 || code == 403)
          ? '로그인 후 투표할 수 있습니다'
          : (code == 429)
              ? '잠시 후 다시 시도해주세요'
              : '투표 중 오류가 발생했습니다';
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('투표 중 오류가 발생했습니다')));
    }
  }

  Future<void> _loadFavStatus() async {
    final cached = await LocalCache.get('favorite_players') as List?;
    if (cached != null && mounted) {
      setState(() => _isFav = cached.any((p) => (p as Map)['id'] == widget.playerId));
    }
    try {
      final data = await ApiService.getFavoritePlayers();
      final players = data['players'] as List? ?? [];
      await LocalCache.set('favorite_players', players);
      if (mounted) setState(() => _isFav = players.any((p) => p['id'] == widget.playerId));
    } catch (e) { debugPrint('player_detail: $e'); }
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
    } catch (e) { debugPrint('player_detail: $e'); }
    if (mounted) setState(() => _favLoading = false);
  }

  Widget _buildShimmer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final hi = isDark ? Colors.grey[700]! : Colors.grey[100]!;
    box(double w, double h) => Container(
          width: w, height: h,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
        );
    return Scaffold(
      appBar: AppBar(),
      body: Shimmer.fromColors(
        baseColor: base, highlightColor: hi,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(radius: 36, backgroundColor: Colors.white),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  box(120, 20), const SizedBox(height: 8), box(80, 14),
                  const SizedBox(height: 6), box(100, 14),
                ]),
              ]),
              const SizedBox(height: 24),
              box(double.infinity, 100),
              const SizedBox(height: 16),
              box(double.infinity, 180),
              const SizedBox(height: 16),
              box(double.infinity, 120),
            ],
          ),
        ),
      ),
    );
  }

  String get _cacheKey => 'player_${widget.playerId}';
  String get _dailyCacheKey => 'player_daily_${widget.playerId}';

  Future<void> _loadPlayer() async {
    // 1순위: 세션 메모리 캐시 (동기, 즉시)
    final memCached = ApiService.getPlayerDetailMem(widget.playerId);
    if (memCached != null && mounted) {
      setState(() { _playerData = memCached; _isLoading = false; _bodyLoading = false; });
    }

    // 2순위: SharedPreferences stale 캐시 (비동기, 빠름) — 메모리 캐시 없을 때만
    if (memCached == null) {
      final cacheResults = await Future.wait([
        LocalCache.getStale(_cacheKey),
        LocalCache.getStale(_dailyCacheKey),
      ]);
      final cached = cacheResults[0] as Map?;
      final cachedDaily = cacheResults[1] as Map?;
      if (cached != null && mounted) {
        setState(() {
          _playerData = Map<String, dynamic>.from(cached);
          if (cachedDaily != null) _dailyStats = cachedDaily['daily'] as List? ?? [];
          _isLoading = false;
          _bodyLoading = false;
        });
      }
    }

    // 3순위: API — getPlayerDetail / getPlayerDaily 독립 처리 (한 쪽 실패해도 다른 쪽 표시)
    try {
      // daily(최근5) 병렬 시작
      _loadDaily();
      // 하위섹션(구종분포/로케이션/히트맵)을 player_type 알면 프로필 대기 없이 즉시 병렬 발화
      // (리스트→상세는 initialData, 재방문은 memCached에 type 존재) → '한박자' 지연 제거
      final earlyType = (memCached?['player_type'] ?? widget.initialData?['player_type']) as String?;
      bool subsFired = false;
      if (earlyType != null) { _fireSubsections(earlyType); subsFired = true; }

      final playerData = await ApiService.getPlayerDetail(widget.playerId);
      ApiService.setPlayerDetailMem(widget.playerId, playerData);
      if (mounted) setState(() { _playerData = playerData; _isLoading = false; _bodyLoading = false; });
      LocalCache.set(_cacheKey, playerData).catchError((_) {});

      // type 미확보였으면 프로필 받은 뒤 발화 (fallback)
      if (!subsFired) _fireSubsections(playerData['player_type'] as String? ?? '');
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _bodyLoading = false; });
    }
  }

  void _fireSubsections(String type) {
    if (type == '투수') {
      _loadPitchStats();
      _loadPitchDesign();
      _loadPitcherZones();
    } else {
      _loadBatterZones();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildShimmer();
    if (_playerData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('선수 상세')),
        body: RefreshIndicator(
          onRefresh: () async {
            setState(() => _isLoading = true);
            await _loadPlayer();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 180),
              Center(
                child: Text('데이터를 불러오는 중...\n아래로 당겨서 새로고침',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      );
    }

    final player = _playerData!;
    return Scaffold(
      appBar: AppBar(
        title: Text((player['full_name'] as String?)?.isNotEmpty == true
            ? player['full_name'] as String : (player['name'] ?? '')),
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        // initialData로 헤더 표시 중, 바디 로딩 진행 표시
        bottom: _bodyLoading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator())
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.compare_arrows),
            tooltip: '선수 비교',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PlayerCompareScreen())),
          ),
          _favLoading
              ? Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: SemColor.brand(context))))
              : IconButton(
                  icon: Icon(_isFav ? Icons.star : Icons.star_border, color: Colors.amber),
                  tooltip: _isFav ? '즐겨찾기 해제' : '즐겨찾기 추가',
                  onPressed: _toggleFav,
                ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        tooltip: '상대전적 조회',
        onPressed: () => _showMatchupSheet(player),
        child: const Icon(Icons.compare_arrows),
      ),
      body: _bodyLoading
          ? _buildBodyShimmer()
          : SingleChildScrollView(
              child: Column(
                children: [
                  // 배치: 헤더 → 핵심 2x2 → 최근5 → 세부/고급 → 트렌드 → 구종 → 시즌별 (빈도순)
                  _buildHeader(player),
                  _buildCoreStatsGrid(player),
                  if (_dailyStats.isNotEmpty) _buildRecent5Games(player),
                  _buildDetailStatsGrids(player),
                  if (_dailyStats.isNotEmpty) _buildTrendCard(player),
                  if (_pitchStats != null) _buildPitchStatsCard(),
                  if (_pitchDesign != null && (_pitchDesign!['total'] as int? ?? 0) > 0)
                    _buildPitchDesignCard(player),
                  if (_pitcherZones != null && (_pitcherZones!['total'] as int? ?? 0) > 0)
                    _buildPitcherZonesCard(player),
                  if (_batterZones != null && (_batterZones!['total'] as int? ?? 0) > 0)
                    _buildBatterZonesCard(player),
                  // PlayerStatsSection(시즌별 표) 제거 — 3열 그리드로 대체 (2026-06-07)
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildBodyShimmer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final hi = isDark ? Colors.grey[700]! : Colors.grey[100]!;
    box(double w, double h) => Container(
          width: w, height: h,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
        );
    return Shimmer.fromColors(
      baseColor: base, highlightColor: hi,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(_playerData!),
            const SizedBox(height: 12),
            box(double.infinity, 100),
            const SizedBox(height: 12),
            box(double.infinity, 180),
            const SizedBox(height: 12),
            box(double.infinity, 120),
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
                        tooltip: '검색',
                        onPressed: () => doSearch(searchCtrl.text),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onSubmitted: doSearch,
                  ),
                  const SizedBox(height: 8),
                  if (searching)
                    Expanded(child: Center(child: CircularProgressIndicator(color: SemColor.brand(context), strokeWidth: 2.5)))
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
          color: isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark)),
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
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          reason.isNotEmpty ? '$type · $reason' : type,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
        ),
      ),
    ]);
  }

  // 히어로 헤더 (mockup 디자인, 2026-06-07): 팀컬러 그라디언트 + 등번호 워터마크 + 팀로고 오버레이
  Widget _buildHeader(Map<String, dynamic> player) {
    // 외국인은 선수상세 한정 풀네임 표시 (full_name), 국내는 name
    final name = (player['full_name'] as String?)?.isNotEmpty == true
        ? player['full_name'] as String : (player['name'] ?? '');
    final team = player['team'] ?? '';
    final posOrType = (player['position'] != null && player['position'].toString().isNotEmpty)
        ? player['position'] : (player['player_type'] ?? '');
    final number = player['number'] ?? '-';
    final code = player['team_code'] as String? ?? '';
    final tc = teamColor(code);
    return Semantics(
      label: '$team $name 선수, 등번호 $number, $posOrType',
      header: true,
      child: Container(
        height: 216,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [tc, tc.withValues(alpha: 0.72), const Color(0xFF1A1A22)],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(children: [
          // 등번호 워터마크 (우상단)
          Positioned(
            right: -14, top: -18,
            child: Opacity(
              opacity: 0.07,
              child: Text('$number',
                  style: const TextStyle(fontSize: 150, fontWeight: FontWeight.w900,
                      color: Colors.white, height: 1)),
            ),
          ),
          // 팀 로고 오버레이 — 대형 가운데 정렬
          Positioned.fill(
            child: Center(
              child: Opacity(opacity: 0.13, child: TeamLogo(teamCode: code, size: 280)),
            ),
          ),
          // 블렌드 radial
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.8, 1.1), radius: 0.6,
                colors: [Colors.black.withValues(alpha: 0.38), Colors.transparent],
              ),
            ),
          ),
          // 본문: 프로필 + 이름/팀/포지션
          Positioned(
            left: 18, right: 18, bottom: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Hero(
                  tag: 'player_${widget.playerId}',
                  // SizedBox.square 강제 — Hero flight/레이아웃에서 가로 stretch 방지
                  child: Container(
                    width: 88, height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2.5),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: PlayerAvatar(
                      imageUrl: player['profile_image'] as String?,
                      teamCode: code,
                      size: 83,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
                              color: Colors.white, letterSpacing: 0, height: 1.15)),
                      const SizedBox(height: 6),
                      Row(children: [
                        Flexible(
                          child: Text('$team · $posOrType · #$number',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.82))),
                        ),
                        // 등록말소/부상자명단 배지 — 백넘버 옆
                        if (player['roster_status'] != null) ...[
                          const SizedBox(width: 8),
                          Flexible(child: _buildRosterBadge(player['roster_status'])),
                        ],
                      ]),
                      // 기본 정보 (InfoCard → 헤더 통합)
                      Builder(builder: (_) {
                        final parts = <String>[
                          if (player['height'] != null || player['weight'] != null)
                            '${player['height'] ?? '-'}cm ${player['weight'] ?? '-'}kg',
                          if (player['throws'] != null || player['bats'] != null)
                            '${player['throws'] ?? ''}${player['bats'] ?? ''}',
                          if (player['birth_date'] != null)
                            (player['birth_date'] as String).replaceAll('-', '.'),
                        ];
                        if (parts.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(parts.join(' · '),
                              style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.62))),
                        );
                      }),
                      const SizedBox(height: 8),
                      Wrap(spacing: 7, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        // 인기투표 하트 (모든 선수 — 탭하여 투표)
                        GestureDetector(
                          onTap: _toggleVote,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                              color: _voted ? const Color(0xFFFF5A5F).withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _voted ? const Color(0xFFFF5A5F).withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.28)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(_voted ? Icons.favorite : Icons.favorite_border,
                                  size: 12, color: _voted ? const Color(0xFFFF5A5F) : Colors.white),
                              const SizedBox(width: 4),
                              Text('$_voteCount',
                                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                            ]),
                          ),
                        ),
                          // 인스타 버튼 (insta_handle 등록된 선수만)
                          if (player['insta_handle'] != null)
                            GestureDetector(
                              onTap: () async {
                                final url = Uri.parse('https://instagram.com/${player['insta_handle']}');
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(url, mode: LaunchMode.externalApplication);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  ShaderMask(
                                    shaderCallback: (b) => const LinearGradient(
                                      begin: Alignment.bottomLeft, end: Alignment.topRight,
                                      colors: [Color(0xFFF09433), Color(0xFFDC2743), Color(0xFFBC1888)],
                                    ).createShader(b),
                                    child: const Icon(Icons.camera_alt_outlined, size: 12, color: Colors.white),
                                  ),
                                  const SizedBox(width: 4),
                                  Text('@${player['insta_handle']}',
                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                                          color: Colors.white.withValues(alpha: 0.92))),
                                ]),
                              ),
                            ),
                        ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── 시즌 스탯 그리드 공용 (mockup 카드 스타일) ──
  Map? _latestSeason(Map<String, dynamic> player) {
    final stats = (player['stats'] as List?) ?? [];
    if (stats.isEmpty) return null;
    Map cur = stats.first as Map;
    for (final s in stats) {
      if (((s as Map)['season'] as num? ?? 0) > (cur['season'] as num? ?? 0)) cur = s;
    }
    return cur;
  }


  static const Set<String> _rateStats = {
    'avg', 'obp', 'slg', 'ops', 'woba', 'wrc_plus', 'babip', 'iso', 'risp', 'bb_pct', 'k_pct', 'gpa', 'bb_k', 'fpct',
    'era', 'whip', 'k_per_9', 'bb_per_9', 'fip', 'avg_against', 'k_bb_pct',
  };

  // 세부/고급/수비 그리드 — 셀마다 리그순위 / 규정미달 표시
  Widget _seasonGridSection(String title, List<(String, String, String)> items) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
    final sub = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final paper = isDark ? const Color(0xFF18181C) : Colors.white;
    final line = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);

    Widget statCard((String, String, String) s) {
      return Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: line),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.05), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.$1, style: TextStyle(fontSize: 9, color: sub)),
          const SizedBox(height: 6),
          Text(s.$2, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink,
              fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sub, letterSpacing: 0.5)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3, shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8, crossAxisSpacing: 8,
          childAspectRatio: 1.1,
          children: [for (final it in items) statCard(it)],
        ),
      ]),
    );
  }

  // ── 핵심 스탯 피커 ──────────────────────────────
  static const Map<String, String> _statLabels = {
    // 타자
    'avg': '타율', 'obp': '출루율', 'slg': '장타율', 'ops': 'OPS',
    'woba': 'wOBA', 'wrc_plus': 'wRC+', 'babip': 'BABIP', 'iso': 'ISO', 'risp': '득점권',
    'gpa': 'GPA', 'bb_k': 'BB/K', 'fpct': '수비율',
    'home_runs': '홈런', 'rbis': '타점', 'hits': '안타', 'stolen_bases': '도루',
    'walks': '볼넷', 'strikeouts': '삼진', 'tb': '루타', 'xbh': '장타', 'war': 'WAR',
    'runs': '득점', 'errors': '실책', 'po': '풋아웃', 'assists': '어시스트', 'dp': '병살', 'pb': '포일',
    // 투수
    'era': 'ERA', 'whip': 'WHIP', 'k_per_9': 'K/9', 'bb_per_9': 'BB/9', 'fip': 'FIP',
    'avg_against': '피안타율', 'k_pct': 'K%', 'bb_pct': 'BB%', 'k_bb_pct': 'K-BB%',
    'wins': '승', 'losses': '패', 'saves': '세이브', 'holds': '홀드', 'qs': 'QS',
    'blown_saves': '블론', 'innings_pitched': '이닝',
  };
  // 핵심 기록 = 어떤 스탯이든 선택 가능 (rate 스탯은 규정 충족 시 순위, 미달 시 값만)
  static const List<String> _batterMenu = [
    'avg', 'obp', 'slg', 'ops', 'woba', 'wrc_plus', 'babip', 'iso', 'risp', 'gpa', 'bb_k',
    'home_runs', 'rbis', 'hits', 'runs', 'stolen_bases', 'walks', 'strikeouts', 'tb', 'xbh', 'war',
    'bb_pct', 'k_pct', 'fpct', 'errors', 'po', 'assists', 'dp', 'pb',
  ];
  static const List<String> _pitcherMenu = [
    'era', 'whip', 'fip', 'k_per_9', 'bb_per_9', 'babip', 'avg_against', 'k_pct', 'bb_pct', 'k_bb_pct',
    'strikeouts', 'wins', 'losses', 'saves', 'holds', 'qs', 'blown_saves', 'innings_pitched', 'war',
  ];
  List<String> _coreBatterKeys = const ['avg', 'home_runs', 'rbis', 'ops'];
  List<String> _corePitcherKeys = const ['era', 'strikeouts', 'wins', 'whip'];

  String _statLabel(String k, bool isPitcher) {
    if (k == 'strikeouts') return isPitcher ? '탈삼진' : '삼진';
    return _statLabels[k] ?? k;
  }

  static const Set<String> _fmt3 = {'avg', 'obp', 'slg', 'ops', 'woba', 'babip', 'iso', 'risp', 'gpa', 'avg_against', 'fpct'};
  static const Set<String> _fmt2 = {'era', 'whip', 'k_per_9', 'bb_per_9', 'fip', 'bb_k'};
  static const Set<String> _fmt1 = {'war', 'wrc_plus'};
  static const Set<String> _fmtPctStat = {'bb_pct', 'k_pct', 'k_bb_pct'};

  Future<void> _loadCoreKeys() async {
    // 선수별 저장 (전역 통일 X)
    final id = widget.playerId;
    final b = await LocalCache.get('core_keys_b_$id');
    final p = await LocalCache.get('core_keys_p_$id');
    if (!mounted) return;
    setState(() {
      if (b is List && b.length == 4) _coreBatterKeys = b.cast<String>();
      if (p is List && p.length == 4) _corePitcherKeys = p.cast<String>();
    });
  }

  String _fmtStat(String key, dynamic v) {
    if (v == null) return '-';
    if (key == 'innings_pitched') return v.toString();
    final n = v as num?;
    if (n == null) return '-';
    if (_fmt3.contains(key)) return n.toStringAsFixed(3);
    if (_fmt2.contains(key)) return n.toStringAsFixed(2);
    if (_fmt1.contains(key)) return n.toStringAsFixed(1);
    if (_fmtPctStat.contains(key)) return '${n.toStringAsFixed(1)}%';
    return n.toInt().toString();
  }

  void _openCorePicker(bool isPitcher) {
    final menu = isPitcher ? _pitcherMenu : _batterMenu;
    // 4 고정 슬롯 — 해제 시 자리 비우고, 새 선택은 빈 자리에 채움 (위치 보존)
    final slots = List<String?>.from(isPitcher ? _corePitcherKeys : _coreBatterKeys);
    while (slots.length < 4) { slots.add(null); }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF18181C) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final ink = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
        final sub = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(ctx).viewPadding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('핵심 스탯 4개 선택', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
            const SizedBox(height: 4),
            Text('${slots.where((e) => e != null).length}/4 · 순서대로 표시 (첫 항목 강조)', style: TextStyle(fontSize: 12, color: sub)),
            const SizedBox(height: 14),
            Flexible(child: SingleChildScrollView(
              child: Wrap(spacing: 8, runSpacing: 8, children: menu.map((k) {
                final on = slots.contains(k);
                return GestureDetector(
                  onTap: () => setSheet(() {
                    final idx = slots.indexOf(k);
                    if (idx >= 0) { slots[idx] = null; }      // 해제 → 자리 비움
                    else {
                      final empty = slots.indexOf(null);
                      if (empty >= 0) slots[empty] = k;        // 빈 자리 채움 (위치 유지)
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: on ? SemColor.brand(context) : (isDark ? const Color(0xFF26262C) : const Color(0xFFF1F1F4)),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(_statLabel(k, isPitcher), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: on ? (isDark ? SemColor.panelDark : Colors.white) : ink)),
                  ),
                );
              }).toList()),
            )),
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: !slots.contains(null) ? () {
                final sel = slots.cast<String>();
                setState(() {
                  if (isPitcher) { _corePitcherKeys = sel; } else { _coreBatterKeys = sel; }
                });
                LocalCache.set('core_keys_${isPitcher ? 'p' : 'b'}_${widget.playerId}', sel).catchError((_) {});
                Navigator.pop(ctx);
              } : null,
              child: const Text('적용'),
            )),
          ]),
        );
      }),
    );
  }

  // 핵심 2x2 — 리그 평균 대비 + 순위 바 (스탯 커스텀)
  Widget _buildCoreStatsGrid(Map<String, dynamic> player) {
    final cur = _latestSeason(player);
    if (cur == null) return const SizedBox.shrink();
    final isPitcher = (player['player_type'] as String? ?? '') == '투수';
    final rawTc = teamColor(player['team_code'] as String? ?? '');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = isDark ? Color.lerp(rawTc, Colors.white, 0.25)! : rawTc;
    final cmp = (player['core_compare'] as Map?) ?? const {};
    final qualified = player['qualified'] as bool? ?? true;
    final ink = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
    final sub = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final paper = isDark ? const Color(0xFF18181C) : Colors.white;
    final line = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);

    final keys = isPitcher ? _corePitcherKeys : _coreBatterKeys;
    final items = [for (final k in keys) (_statLabel(k, isPitcher), _fmtStat(k, cur[k]), k)];

    Widget card((String, String, String) it, bool highlight) {
      final c = cmp[it.$3] as Map?;
      final rank = (c?['rank'] as num?)?.toInt();
      final total = (c?['total'] as num?)?.toInt();
      // 1위 = 만땅, 꼴찌 = 거의 빔. fill = (total-rank+1)/total
      final fill = (rank != null && total != null && total > 0)
          ? ((total - rank + 1) / total).clamp(0.0, 1.0) : 0.0;
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: highlight ? tc.withValues(alpha: 0.4) : line),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.05),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: Text(it.$1, style: TextStyle(fontSize: 13, color: sub))),
            Text(it.$2, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
                color: highlight ? tc : ink, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          if (c != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Text('리그 ${c['rank']}위',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tc)),
              if (c['dom_rank'] != null)
                Text('  ·  국내 ${c['dom_rank']}위',
                    style: TextStyle(fontSize: 12, color: sub)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(height: 6, child: Stack(children: [
                Container(width: double.infinity, color: line),
                FractionallySizedBox(widthFactor: fill, child: Container(color: tc)),
                // 리그 평균 마커 (중앙 ≈ 평균 순위)
                Align(alignment: Alignment.center,
                    child: Container(width: 2, color: ink.withValues(alpha: 0.55))),
              ])),
            ),
            const SizedBox(height: 4),
            SizedBox(width: double.infinity, child: Text(
                '▲ 리그 평균 ${_fmtStat(it.$3, (c['lg'] as num?) ?? 0)}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 9, color: sub))),
          ] else if (_rateStats.contains(it.$3) && !qualified) ...[
            const SizedBox(height: 8),
            Text(isPitcher ? '규정이닝 미달' : '규정타석 미달',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sub)),
          ],
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${cur['season'] ?? ''} 시즌 핵심 기록',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sub, letterSpacing: 0.5))),
          GestureDetector(
            onTap: () => _openCorePicker(isPitcher),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.tune, size: 13, color: sub),
              const SizedBox(width: 3),
              Text('편집', style: TextStyle(fontSize: 11, color: sub, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10, crossAxisSpacing: 10,
          childAspectRatio: 1.4,
          children: [for (int i = 0; i < items.length; i++) card(items[i], i == 0)],
        ),
      ]),
    );
  }

  // 세부/고급/수비 그리드 — 핵심 4개에 든 스탯은 제외 (중복·누락 방지, 핵심 변경 시 자동 반영)
  static const List<String> _gBatterDetail = [
    'avg', 'obp', 'slg', 'ops', 'hits', 'home_runs', 'rbis', 'runs', 'stolen_bases', 'walks', 'strikeouts', 'tb', 'xbh', 'bb_k',
  ];
  static const List<String> _gBatterAdv = ['woba', 'wrc_plus', 'war', 'babip', 'iso', 'risp', 'gpa', 'bb_pct', 'k_pct'];
  static const List<String> _gBatterDef = ['fpct', 'errors', 'po', 'assists', 'dp', 'pb'];
  static const List<String> _gPitcherDetail = [
    'era', 'whip', 'wins', 'losses', 'saves', 'holds', 'qs', 'innings_pitched', 'strikeouts', 'avg_against', 'blown_saves',
  ];
  static const List<String> _gPitcherAdv = ['fip', 'k_per_9', 'bb_per_9', 'war', 'babip', 'k_pct', 'bb_pct', 'k_bb_pct'];

  Widget _buildDetailStatsGrids(Map<String, dynamic> player) {
    final cur = _latestSeason(player);
    if (cur == null) return const SizedBox.shrink();
    final isPitcher = (player['player_type'] as String? ?? '') == '투수';
    final core = (isPitcher ? _corePitcherKeys : _coreBatterKeys).toSet();
    List<(String, String, String)> build(List<String> keys) => [
          for (final k in keys)
            if (!core.contains(k)) (_statLabel(k, isPitcher), _fmtStat(k, cur[k]), k),
        ];
    final detail = build(isPitcher ? _gPitcherDetail : _gBatterDetail);
    final advanced = build(isPitcher ? _gPitcherAdv : _gBatterAdv);
    final defense = isPitcher ? <(String, String, String)>[] : build(_gBatterDef);
    final hasDefense = defense.any((e) => e.$2 != '-' && e.$2 != '0');

    return Column(children: [
      if (detail.isNotEmpty) _seasonGridSection('세부 기록', detail),
      if (advanced.isNotEmpty) _seasonGridSection('고급 지표', advanced),
      if (hasDefense) _seasonGridSection('수비', defense),
    ]);
  }

  // ── 피칭 디자인 카드 — 구종별 로케이션 5x5 히트맵 (2026-06-07) ──
  Widget _buildPitchDesignCard(Map<String, dynamic> player) {
    final d = _pitchDesign!;
    final types = (d['pitch_types'] as List? ?? []).cast<Map>();
    if (types.isEmpty) return const SizedBox.shrink();
    final selType = _pdType ?? types.first['type'] as String;
    final sel = types.firstWhere((t) => t['type'] == selType, orElse: () => types.first);
    final zones = (sel['zones'] as List? ?? List.filled(25, 0)).cast<num>();
    final total = (d['total'] as num?)?.toInt() ?? 0;
    final selCount = (sel['count'] as num?)?.toInt() ?? 0;
    final maxZ = zones.fold<num>(1, (m, v) => v > m ? v : m);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
    final ink3 = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    final sub = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final paper = isDark ? const Color(0xFF18181C) : Colors.white;
    final line = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
    final rawTc = teamColor(player['team_code'] as String? ?? '');
    final tc = isDark ? Color.lerp(rawTc, Colors.white, 0.2)! : rawTc;

    Widget chip(String label, bool active, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? ink : paper,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: active ? ink : line),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? (isDark ? Colors.black : Colors.white) : ink3)),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('피칭 디자인 — 구종별 로케이션',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sub, letterSpacing: 0.5)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: paper,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: line),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.05),
                  blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // stance 토글
                Row(children: [
                  chip('전체', _pdStance == '', () {
                    setState(() => _pdStance = '');
                    _loadPitchDesign();
                  }),
                  chip('vs 우타', _pdStance == 'R', () {
                    setState(() => _pdStance = 'R');
                    _loadPitchDesign();
                  }),
                  chip('vs 좌타', _pdStance == 'L', () {
                    setState(() => _pdStance = 'L');
                    _loadPitchDesign();
                  }),
                ]),
                const SizedBox(height: 4),
                // 구종 칩 (구사율 %)
                Wrap(children: [
                  for (final t in types)
                    chip('${t['type']} ${t['pct']}%', selType == t['type'],
                        () => setState(() => _pdType = t['type'] as String)),
                ]),
                const SizedBox(height: 10),
                // 5x5 히트맵 (포수 시점, 내부 3x3 존 보더 강조)
                Center(
                  child: SizedBox(
                    width: 230, height: 230,
                    child: Stack(children: [
                      Column(children: [
                        for (int r = 0; r < 5; r++)
                          Expanded(child: Row(children: [
                            for (int c = 0; c < 5; c++)
                              Expanded(child: Builder(builder: (_) {
                                final v = zones[r * 5 + c];
                                final ratio = v / maxZ;
                                final pct = selCount > 0 ? v * 100 / selCount : 0.0;
                                return Container(
                                  margin: const EdgeInsets.all(1),
                                  decoration: BoxDecoration(
                                    color: v == 0
                                        ? (isDark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6))
                                        : tc.withValues(alpha: 0.10 + 0.80 * ratio),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  alignment: Alignment.center,
                                  child: pct >= 2
                                      ? Text('${pct.round()}',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                                              color: ratio > 0.55 ? Colors.white : ink,
                                              fontFeatures: const [FontFeature.tabularFigures()]))
                                      : null,
                                );
                              })),
                          ])),
                      ]),
                      // 스트라이크존(내부 3x3) 단일 굵은 외곽선 — 존 경계 명확화
                      Positioned(
                        left: 230 / 5, top: 230 / 5,
                        width: 230 * 3 / 5, height: 230 * 3 / 5,
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: ink.withValues(alpha: 0.85), width: 2.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                Text('$selType $selCount구 · 전체 $total구 · 셀 숫자 = 해당 구종 내 비율(%)',
                    style: TextStyle(fontSize: 10, color: sub)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 타자 존 히트맵 — 피투구 분포 / 헛스윙률 / 존별 타율 (2026-06-07) ──
  Widget _buildBatterZonesCard(Map<String, dynamic> player) {
    final d = _batterZones!;
    final zonesMap = d['zones'] as Map<String, dynamic>? ?? {};
    final pitchesZ = (zonesMap['pitches'] as List? ?? List.filled(25, 0)).cast<num>();
    final swingsZ = (zonesMap['swings'] as List? ?? List.filled(25, 0)).cast<num>();
    final whiffsZ = (zonesMap['whiffs'] as List? ?? List.filled(25, 0)).cast<num>();
    final abZ = (zonesMap['inplay_ab'] as List? ?? List.filled(25, 0)).cast<num>();
    final hitsZ = (zonesMap['hits'] as List? ?? List.filled(25, 0)).cast<num>();
    final total = (d['total'] as num?)?.toInt() ?? 0;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
    final ink3 = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    final sub = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final paper = isDark ? const Color(0xFF18181C) : Colors.white;
    final line = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
    final emptyCell = isDark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6);
    final rawTc = teamColor(player['team_code'] as String? ?? '');
    final tc = isDark ? Color.lerp(rawTc, Colors.white, 0.2)! : rawTc;

    Widget chip(String label, bool active, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? ink : paper,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: active ? ink : line),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? (isDark ? Colors.black : Colors.white) : ink3)),
      ),
    );

    // 셀 (색, 라벨) — metric별 계산
    final maxPitch = pitchesZ.fold<num>(1, (m, v) => v > m ? v : m);
    (Color, String) cell(int i) {
      switch (_bzMetric) {
        case 'whiff':
          final sw = swingsZ[i];
          if (sw < 5) return (emptyCell, '');  // 표본 가드 (스윙 5개 미만)
          final r = whiffsZ[i] / sw;
          return (const Color(0xFFE53935).withValues(alpha: 0.08 + 0.80 * r.clamp(0, 1)),
                  '${(r * 100).round()}');
        case 'avg':
          final ab = abZ[i];
          if (ab < 5) return (emptyCell, '');  // 표본 가드 (5타수 미만)
          final avg = hitsZ[i] / ab;
          // 발산 색: 리그 평균 .270 기준 핫(적)/콜드(청)
          final diff = (avg - 0.270).clamp(-0.27, 0.27);
          final c = diff >= 0
              ? const Color(0xFFE53935).withValues(alpha: 0.10 + 0.85 * (diff / 0.27))
              : const Color(0xFF2563EB).withValues(alpha: 0.10 + 0.85 * (-diff / 0.27));
          return (c, avg.toStringAsFixed(3).substring(1));  // '.342'
        default:  // dist
          final v = pitchesZ[i];
          final pct = total > 0 ? v * 100 / total : 0.0;
          return (v == 0 ? emptyCell : tc.withValues(alpha: 0.10 + 0.80 * (v / maxPitch)),
                  pct >= 2 ? '${pct.round()}' : '');
      }
    }

    String metricNote() {
      switch (_bzMetric) {
        case 'whiff': return '셀 = 헛스윙률% (스윙 5개 미만 회색)';
        case 'avg': return '셀 = 존별 타율 (5타수 미만 회색, 적=핫·청=콜드)';
        default: return '셀 = 전체 피투구 중 비율%';
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('존 히트맵',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sub, letterSpacing: 0.5)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: paper,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: line),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.05),
                  blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 지표 토글
                Row(children: [
                  chip('피투구 분포', _bzMetric == 'dist', () => setState(() => _bzMetric = 'dist')),
                  chip('헛스윙률', _bzMetric == 'whiff', () => setState(() => _bzMetric = 'whiff')),
                  chip('타율', _bzMetric == 'avg', () => setState(() => _bzMetric = 'avg')),
                ]),
                // 투수 손 토글
                Row(children: [
                  chip('전체', _bzThrows == '', () {
                    setState(() => _bzThrows = '');
                    _loadBatterZones();
                  }),
                  chip('vs 우투', _bzThrows == 'R', () {
                    setState(() => _bzThrows = 'R');
                    _loadBatterZones();
                  }),
                  chip('vs 좌투', _bzThrows == 'L', () {
                    setState(() => _bzThrows = 'L');
                    _loadBatterZones();
                  }),
                ]),
                const SizedBox(height: 10),
                Center(
                  child: SizedBox(
                    width: 230, height: 230,
                    child: Stack(children: [
                      Column(children: [
                        for (int r = 0; r < 5; r++)
                          Expanded(child: Row(children: [
                            for (int c = 0; c < 5; c++)
                              Expanded(child: Builder(builder: (_) {
                                final i = r * 5 + c;
                                final (color, label) = cell(i);
                                return Container(
                                  margin: const EdgeInsets.all(1),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  alignment: Alignment.center,
                                  child: label.isEmpty
                                      ? null
                                      : Text(label,
                                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800,
                                              color: ink,
                                              fontFeatures: const [FontFeature.tabularFigures()])),
                                );
                              })),
                          ])),
                      ]),
                      // 스트라이크존(내부 3x3) 단일 굵은 외곽선 — 존 경계 명확화
                      Positioned(
                        left: 230 / 5, top: 230 / 5,
                        width: 230 * 3 / 5, height: 230 * 3 / 5,
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: ink.withValues(alpha: 0.85), width: 2.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                Text('전체 $total구 · ${metricNote()}',
                    style: TextStyle(fontSize: 10, color: sub)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 피칭 존 히트맵 — 피투구 분포 / 피안타율 (구종 무관 합산) ──
  Widget _buildPitcherZonesCard(Map<String, dynamic> player) {
    final d = _pitcherZones!;
    final zonesMap = d['zones'] as Map<String, dynamic>? ?? {};
    final pitchesZ = (zonesMap['pitches'] as List? ?? List.filled(25, 0)).cast<num>();
    final abZ = (zonesMap['inplay_ab'] as List? ?? List.filled(25, 0)).cast<num>();
    final hitsZ = (zonesMap['hits'] as List? ?? List.filled(25, 0)).cast<num>();
    final total = (d['total'] as num?)?.toInt() ?? 0;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
    final ink3 = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    final sub = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final paper = isDark ? const Color(0xFF18181C) : Colors.white;
    final line = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
    final emptyCell = isDark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6);
    final rawTc = teamColor(player['team_code'] as String? ?? '');
    final tc = isDark ? Color.lerp(rawTc, Colors.white, 0.2)! : rawTc;

    Widget chip(String label, bool active, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? ink : paper,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: active ? ink : line),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? (isDark ? Colors.black : Colors.white) : ink3)),
      ),
    );

    final maxPitch = pitchesZ.fold<num>(1, (m, v) => v > m ? v : m);
    (Color, String) cell(int i) {
      if (_pzMetric == 'avg') {
        final ab = abZ[i];
        if (ab < 5) return (emptyCell, '');  // 표본 가드 (5타수 미만)
        final avg = hitsZ[i] / ab;
        // 피안타율: 투수 관점 → 적=많이 맞음(나쁨)/청=잘 막음(좋음), 리그 .270 기준
        final diff = (avg - 0.270).clamp(-0.27, 0.27);
        final c = diff >= 0
            ? const Color(0xFFE53935).withValues(alpha: 0.10 + 0.85 * (diff / 0.27))
            : const Color(0xFF2563EB).withValues(alpha: 0.10 + 0.85 * (-diff / 0.27));
        return (c, avg.toStringAsFixed(3).substring(1));  // '.342'
      }
      final v = pitchesZ[i];
      final pct = total > 0 ? v * 100 / total : 0.0;
      return (v == 0 ? emptyCell : tc.withValues(alpha: 0.10 + 0.80 * (v / maxPitch)),
              pct >= 2 ? '${pct.round()}' : '');
    }

    final note = _pzMetric == 'avg'
        ? '셀 = 존별 피안타율 (5타수 미만 회색, 적=많이맞음·청=잘막음)'
        : '셀 = 전체 투구 중 비율%';

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('피칭 존 히트맵',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sub, letterSpacing: 0.5)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: paper,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: line),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.05),
                  blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 지표 토글
                Row(children: [
                  chip('피투구 분포', _pzMetric == 'dist', () => setState(() => _pzMetric = 'dist')),
                  chip('피안타율', _pzMetric == 'avg', () => setState(() => _pzMetric = 'avg')),
                ]),
                // 타자 손 토글
                Row(children: [
                  chip('전체', _pzStance == '', () { setState(() => _pzStance = ''); _loadPitcherZones(); }),
                  chip('vs 우타', _pzStance == 'R', () { setState(() => _pzStance = 'R'); _loadPitcherZones(); }),
                  chip('vs 좌타', _pzStance == 'L', () { setState(() => _pzStance = 'L'); _loadPitcherZones(); }),
                ]),
                const SizedBox(height: 10),
                Center(
                  child: SizedBox(
                    width: 230, height: 230,
                    child: Stack(children: [
                      Column(children: [
                        for (int r = 0; r < 5; r++)
                          Expanded(child: Row(children: [
                            for (int c = 0; c < 5; c++)
                              Expanded(child: Builder(builder: (_) {
                                final i = r * 5 + c;
                                final (color, label) = cell(i);
                                return Container(
                                  margin: const EdgeInsets.all(1),
                                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                                  alignment: Alignment.center,
                                  child: label.isEmpty ? null : Text(label,
                                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: ink,
                                          fontFeatures: const [FontFeature.tabularFigures()])),
                                );
                              })),
                          ])),
                      ]),
                      // 스트라이크존(내부 3x3) 외곽선
                      Positioned(
                        left: 230 / 5, top: 230 / 5,
                        width: 230 * 3 / 5, height: 230 * 3 / 5,
                        child: IgnorePointer(child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: ink.withValues(alpha: 0.85), width: 2.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        )),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                Text('전체 $total구 · $note', style: TextStyle(fontSize: 10, color: sub)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
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

  static const _hitterTrendOptions = [
    {'value': 'avg',        'label': '타율',   'decimals': 3},
    {'value': 'hits',       'label': '안타',   'decimals': 0},
    {'value': 'home_runs',  'label': '홈런',   'decimals': 0},
    {'value': 'rbi',        'label': '타점',   'decimals': 0},
    {'value': 'walks',      'label': '볼넷',   'decimals': 0},
  ];
  static const _pitcherTrendOptions = [
    {'value': 'era',  'label': 'ERA',    'decimals': 2},
    {'value': 'ip',   'label': '이닝',   'decimals': 1},
    {'value': 'so',   'label': '탈삼진', 'decimals': 0},
    {'value': 'bb',   'label': '볼넷',   'decimals': 0},
    {'value': 'er',   'label': '자책',   'decimals': 0},
  ];

  /// 시즌 트렌드 그래프 카드 (스탯 선택 가능)
  Widget _buildTrendCard(Map<String, dynamic> player) {
    final isHitter = player['player_type'] == '타자';
    final trendStat = isHitter ? _hitterTrendStat : _pitcherTrendStat;
    final options = isHitter ? _hitterTrendOptions : _pitcherTrendOptions;
    final optionMap = options.firstWhere((o) => o['value'] == trendStat, orElse: () => options.first);
    final statLabel = optionMap['label'] as String;
    final decimals = optionMap['decimals'] as int;

    final filtered = _dailyStats
        .where((d) {
          if (isHitter) {
            final pa = (d['pa'] as num?)?.toInt() ?? 0;
            final ab = (d['ab'] as num?)?.toInt() ?? 0;
            return d['stat_type'] == 'hitter' && (pa > 0 || ab > 0);
          } else {
            final ip = (d['ip'] as num?)?.toDouble() ?? 0;
            return d['stat_type'] == 'pitcher' && ip > 0;
          }
        })
        .toList();

    final recent = filtered.length > 20 ? filtered.sublist(filtered.length - 20) : filtered;
    if (recent.isEmpty) return const SizedBox.shrink();

    double? getValue(Map d) {
      if (trendStat == 'avg') return (d['avg'] as num?)?.toDouble();
      if (trendStat == 'era') {
        final ip = (d['ip'] as num?)?.toDouble() ?? 0;
        final er = (d['er'] as num?)?.toDouble() ?? 0;
        final realIp = _ipToDecimal(ip);
        return realIp > 0 ? er * 9 / realIp : null;
      }
      if (trendStat == 'ip') return (d['ip'] as num?)?.toDouble();
      return (d[trendStat] as num?)?.toDouble();
    }

    final spots = <FlSpot>[];
    final labels = <String>[];
    for (int i = 0; i < recent.length; i++) {
      final val = getValue(recent[i] as Map);
      if (val != null) {
        spots.add(FlSpot(i.toDouble(), val));
        final dateStr = (recent[i] as Map)['game_date'] as String? ?? '';
        labels.add(dateStr.length >= 10 ? '${dateStr.substring(5, 7)}/${dateStr.substring(8, 10)}' : '');
      }
    }
    if (spots.isEmpty) return const SizedBox.shrink();

    final values = spots.map((s) => s.y).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final isLowStat = trendStat == 'era';
    final padding = decimals == 3 ? 0.05 : (decimals == 2 ? 0.5 : 1.0);
    final yMin = (minVal - padding).clamp(0.0, double.infinity);
    final yMax = decimals == 3
        ? (maxVal + padding).clamp(0.0, 1.0)
        : maxVal + padding;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chartColor = isLowStat
        ? (isDark ? const Color(0xFFEF5350) : const Color(0xFFB71C1C))
        : isHitter
            ? (isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark)
            : (isDark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('시즌 트렌드'),
              const SizedBox(height: 8),
              // 스탯 선택 칩
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: options.map((opt) {
                    final sel = trendStat == opt['value'];
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (isHitter) {
                          _hitterTrendStat = opt['value'] as String;
                        } else {
                          _pitcherTrendStat = opt['value'] as String;
                        }
                      }),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: sel ? chartColor : Colors.grey.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          opt['label'] as String,
                          style: TextStyle(
                            fontSize: 11,
                            // 선택 칩 bg(chartColor)가 밝으면(다크모드 타자=흰색) 검은 글씨로 대비 확보
                            color: sel ? (chartColor.computeLuminance() > 0.5 ? Colors.black : Colors.white) : null,
                            fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 150,
                child: LineChart(
                  LineChartData(
                    minY: yMin,
                    maxY: yMax,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: Colors.grey.withValues(alpha: 0.3),
                        strokeWidth: 0.8,
                        dashArray: const [4, 4],
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.4), width: 1),
                        left: BorderSide(color: Colors.grey.withValues(alpha: 0.4), width: 1),
                      ),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          getTitlesWidget: (value, _) {
                            final text = decimals == 3
                                ? value.toStringAsFixed(3)
                                : decimals == 2
                                    ? value.toStringAsFixed(2)
                                    : value.toInt().toString();
                            return Text(text, style: TextStyle(fontSize: 11, color: Colors.grey[600]));
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          interval: recent.length <= 5 ? 1 : (recent.length / 4).ceilToDouble(),
                          getTitlesWidget: (value, _) {
                            final idx = value.toInt();
                            if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(labels[idx], style: TextStyle(fontSize: 11, color: Colors.grey[600])),
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
                          color: chartColor.withValues(alpha: 0.08),
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
                            final lbl = idx < labels.length ? labels[idx] : '';
                            final valText = decimals == 3
                                ? spot.y.toStringAsFixed(3)
                                : decimals == 2
                                    ? spot.y.toStringAsFixed(2)
                                    : spot.y.toInt().toString();
                            return LineTooltipItem(
                              '$lbl  $statLabel $valText',
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
    return '$month월 $day일';
  }

  Widget _buildRecent5Games(Map<String, dynamic> player) {
    final isHitter = player['player_type'] == '타자';
    final filtered = _dailyStats
        .where((d) {
          if (isHitter) {
            final pa = (d['pa'] as num?)?.toInt() ?? 0;
            final ab = (d['ab'] as num?)?.toInt() ?? 0;
            return d['stat_type'] == 'hitter' && (pa > 0 || ab > 0);
          }
          return d['stat_type'] == 'pitcher' && ((d['ip'] as num?) ?? 0) > 0;
        })
        .toList();
    if (filtered.isEmpty) return const SizedBox.shrink();
    final recent = filtered.length > 5
        ? filtered.sublist(filtered.length - 5).reversed.toList()
        : filtered.reversed.toList();

    // 그리드 섹션과 동일 디자인 언어 (2026-06-07): sub 타이틀 + paper 카드, 요약 4칸 + 경기 행 통합
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
    final sub = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final paper = isDark ? const Color(0xFF18181C) : Colors.white;
    final line = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);

    Widget summaryCell(String label, String value) => Column(children: [
      Text(value,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink,
              letterSpacing: 0, fontFeatures: const [FontFeature.tabularFigures()])),
      const SizedBox(height: 3),
      Text(label, style: TextStyle(fontSize: 9, color: sub)),
    ]);

    final summary = isHitter ? _hitterSummaryItems(recent) : _pitcherSummaryItems(recent);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('최근 5경기',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sub, letterSpacing: 0.5)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
            decoration: BoxDecoration(
              color: paper,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: line),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.05),
                  blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [for (final s in summary) summaryCell(s.$1, s.$2)],
                ),
                const SizedBox(height: 12),
                Container(height: 1, color: line),
                const SizedBox(height: 6),
                isHitter ? _buildHitterRows(recent) : _buildPitcherRows(recent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<(String, String)> _hitterSummaryItems(List<dynamic> rows) {
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
    return [
      ('AVG', avg.toStringAsFixed(3)),
      ('OPS', (obp + slg).toStringAsFixed(3)),
      ('HR', '$totalHr'),
      ('RBI', '$totalRbi'),
    ];
  }

  List<(String, String)> _pitcherSummaryItems(List<dynamic> rows) {
    final totalEr = rows.fold<int>(0, (s, d) => s + ((d['er'] as num?)?.toInt() ?? 0));
    final totalH  = rows.fold<int>(0, (s, d) => s + ((d['h'] as num?)?.toInt() ?? 0));
    final totalBb = rows.fold<int>(0, (s, d) => s + ((d['bb'] as num?)?.toInt() ?? 0));
    final totalSo = rows.fold<int>(0, (s, d) => s + ((d['so'] as num?)?.toInt() ?? 0));
    final realIp  = rows.fold<double>(0.0, (s, d) => s + _ipToDecimal((d['ip'] as num?)?.toDouble() ?? 0));
    final era  = realIp > 0 ? totalEr * 9 / realIp : 0.0;
    final whip = realIp > 0 ? (totalH + totalBb) / realIp : 0.0;
    return [
      ('ERA', era.toStringAsFixed(2)),
      ('WHIP', whip.toStringAsFixed(2)),
      ('K', '$totalSo'),
      ('IP', _fmtRealIp(realIp)),
    ];
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween, // 카드 폭 채워 정렬(좌측 쏠림 방지)
        children: List.generate(cells.length, (i) {
          final isFirst = i == 0;
          return SizedBox(
            width: widths[i],
            child: Text(
              cells[i],
              style: TextStyle(
                fontSize: isFirst ? 12 : 12,
                fontWeight: isHeader ? FontWeight.w700 : FontWeight.normal,
                color: isHeader ? (isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark) : null,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark)),
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
