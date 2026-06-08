import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../api/api_service.dart';
import '../../utils/local_cache.dart';
import '../../utils/team_theme.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import 'player_detail_screen.dart';
import '../mypage/my_page_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;

  List _allHitters = [];
  List _allPitchers = [];
  List _hitters = [];
  List _pitchers = [];
  bool _hitterLoading = true;
  bool _pitcherLoading = true;

  String _hitterSort = 'avg';
  String _pitcherSort = 'era';
  String _hitterPos = '전체';   // 타자 포지션 필터 (포수/내야/외야)
  String _pitcherArm = '전체';  // 투수 구위 필터 (우완/좌완/언더)

  List _teams = [];
  int? _selectedTeamId;
  bool _isListView = true; // 리스트 / 카드 토글

  List _searchResults = [];
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  // 인기투표
  List _popularPlayers = [];
  List _popularTeams = [];
  bool _popularLoading = false;
  bool _popularShowTeam = false;
  bool _isLoggedIn = false;

  static const List<Map<String, String>> _hitterSorts = [
    {'value': 'avg',          'label': '타율'},
    {'value': 'home_runs',    'label': '홈런'},
    {'value': 'rbis',         'label': '타점'},
    {'value': 'hits',         'label': '안타'},
    {'value': 'stolen_bases', 'label': '도루'},
    {'value': 'ops',          'label': 'OPS'},
    {'value': 'war',          'label': 'WAR'},
  ];

  static const List<Map<String, String>> _pitcherSorts = [
    {'value': 'era',        'label': 'ERA'},
    {'value': 'wins',       'label': '승'},
    {'value': 'strikeouts', 'label': '탈삼진'},
    {'value': 'saves',      'label': '세이브'},
    {'value': 'holds',      'label': '홀드'},
    {'value': 'whip',       'label': 'WHIP'},
    {'value': 'war',        'label': 'WAR'},
  ];

  static const List<Map<String, String>> _hitterPosOpts = [
    {'value': '전체', 'label': '전체'},
    {'value': '포수', 'label': '포수'},
    {'value': '1루수', 'label': '1루'},
    {'value': '2루수', 'label': '2루'},
    {'value': '3루수', 'label': '3루'},
    {'value': '유격수', 'label': '유격수'},
    {'value': '좌익수', 'label': '좌익수'},
    {'value': '중견수', 'label': '중견수'},
    {'value': '우익수', 'label': '우익수'},
  ];
  static const List<Map<String, String>> _pitcherArmOpts = [
    {'value': '전체', 'label': '전체'}, {'value': '우완', 'label': '우완'},
    {'value': '좌완', 'label': '좌완'}, {'value': '언더', 'label': '언더'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 2 && _popularPlayers.isEmpty && !_popularLoading) {
        _loadPopularity();
      }
    });
    _loadTeams();
    _loadHitters();
    _loadPitchers();
    _checkLogin();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadHitters();
      _loadPitchers();
    }
  }

  Future<void> _checkLogin() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _isLoggedIn = prefs.getString('access_token') != null);
  }

  Future<void> _loadPopularity() async {
    if (mounted) setState(() => _popularLoading = true);
    try {
      final r1 = await ApiService.getPlayerPopularity(limit: 30);
      final r2 = await ApiService.getTeamPopularity();
      if (mounted) {
        setState(() {
        _popularPlayers = r1['players'] ?? [];
        _popularTeams = r2['teams'] ?? [];
        _popularLoading = false;
      });
      }
    } catch (_) {
      if (mounted) setState(() => _popularLoading = false);
    }
  }

  Future<void> _votePlayer(int playerId) async {
    if (!_isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인 후 투표할 수 있습니다')));
      return;
    }
    try {
      final res = await ApiService.votePlayer(playerId);
      final voted = res['voted'] as bool? ?? false;
      final count = res['vote_count'] as int? ?? 0;
      if (mounted) {
        setState(() {
        final idx = _popularPlayers.indexWhere((p) => (p as Map)['id'] == playerId);
        if (idx >= 0) {
          final updated = Map<String, dynamic>.from(_popularPlayers[idx] as Map);
          updated['voted'] = voted;
          updated['vote_count'] = count;
          _popularPlayers[idx] = updated;
          _popularPlayers.sort((a, b) =>
              ((b as Map)['vote_count'] as int? ?? 0)
                  .compareTo((a as Map)['vote_count'] as int? ?? 0));
        } else if (voted) {
          _loadPopularity();
        }
      });
      }
    } catch (e) {
      if (!mounted) return;
      final msg = _voteErrorMessage(e);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  String _voteErrorMessage(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 429) return '잠시 후 다시 시도해주세요';
      if (code == 401 || code == 403) return '로그인이 필요합니다';
    }
    return '투표 중 오류가 발생했습니다';
  }

  Future<void> _voteTeam(int teamId) async {
    if (!_isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인 후 투표할 수 있습니다')));
      return;
    }
    try {
      final res = await ApiService.voteTeam(teamId);
      final voted = res['voted'] as bool? ?? false;
      final count = res['vote_count'] as int? ?? 0;
      if (mounted) {
        setState(() {
        final idx = _popularTeams.indexWhere((t) => (t as Map)['id'] == teamId);
        if (idx >= 0) {
          final updated = Map<String, dynamic>.from(_popularTeams[idx] as Map);
          updated['voted'] = voted;
          updated['vote_count'] = count;
          _popularTeams[idx] = updated;
          _popularTeams.sort((a, b) =>
              ((b as Map)['vote_count'] as int? ?? 0)
                  .compareTo((a as Map)['vote_count'] as int? ?? 0));
        }
      });
      }
    } catch (e) {
      if (!mounted) return;
      final msg = _voteErrorMessage(e);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _loadTeams() async {
    try {
      final data = await ApiService.getTeams();
      if (mounted) setState(() => _teams = data['teams'] ?? []);
    } catch (e) { debugPrint('player_screen: $e'); }
  }

  Future<void> _loadHitters() async {
    final cached = await LocalCache.get('hitters_list', maxAgeSeconds: 300) as List?;
    if (cached != null && mounted) {
      _allHitters = cached;
      _applyHitterFilter();
      setState(() => _hitterLoading = false);
    } else {
      if (mounted) setState(() => _hitterLoading = true);
    }
    try {
      final data = await ApiService.getHitters(sortBy: 'avg', limit: 500, teamId: null);
      if (mounted) {
        final fresh = data['hitters'] as List? ?? [];
        await LocalCache.set('hitters_list', fresh);
        _allHitters = fresh;
        _applyHitterFilter();
        setState(() => _hitterLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _hitterLoading = false);
    }
  }

  Future<void> _loadPitchers() async {
    final cached = await LocalCache.get('pitchers_list', maxAgeSeconds: 300) as List?;
    if (cached != null && mounted) {
      _allPitchers = cached;
      _applyPitcherFilter();
      setState(() => _pitcherLoading = false);
    } else {
      if (mounted) setState(() => _pitcherLoading = true);
    }
    try {
      final data = await ApiService.getPitchers(sortBy: 'era', limit: 500, teamId: null);
      if (mounted) {
        final fresh = data['pitchers'] as List? ?? [];
        await LocalCache.set('pitchers_list', fresh);
        _allPitchers = fresh;
        _applyPitcherFilter();
        setState(() => _pitcherLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _pitcherLoading = false);
    }
  }

  // 투수 throws → 구위 (우완/좌완/언더)
  String _armGroup(String throws) {
    if (throws.contains('좌')) return '좌완';
    if (throws.contains('언') || throws.contains('사')) return '언더';
    return '우완';
  }

  void _applyHitterFilter() {
    List filtered = _selectedTeamId == null
        ? List.from(_allHitters)
        : _allHitters.where((p) {
            final code = (p as Map)['team_code'] as String? ?? '';
            return _teams.any((t) =>
                t['id'] == _selectedTeamId &&
                t['short_name'] == code);
          }).toList();

    if (_hitterPos != '전체') {
      filtered = filtered.where((p) => ((p as Map)['position'] ?? '').toString() == _hitterPos).toList();
    }

    filtered.sort((a, b) {
      final am = a as Map;
      final bm = b as Map;
      switch (_hitterSort) {
        case 'avg':          return _cmpDesc(bm['avg'],          am['avg']);
        case 'home_runs':    return _cmpDesc(bm['home_runs'],    am['home_runs']);
        case 'rbis':         return _cmpDesc(bm['rbis'],         am['rbis']);
        case 'hits':         return _cmpDesc(bm['hits'],         am['hits']);
        case 'stolen_bases': return _cmpDesc(bm['stolen_bases'], am['stolen_bases']);
        case 'ops':          return _cmpDesc(bm['ops'],          am['ops']);
        case 'war':          return _cmpDesc(bm['war'],          am['war']);
        default:             return 0;
      }
    });

    _hitters = filtered;
  }

  void _applyPitcherFilter() {
    List filtered = _selectedTeamId == null
        ? List.from(_allPitchers)
        : _allPitchers.where((p) {
            final code = (p as Map)['team_code'] as String? ?? '';
            return _teams.any((t) =>
                t['id'] == _selectedTeamId &&
                t['short_name'] == code);
          }).toList();

    if (_pitcherArm != '전체') {
      filtered = filtered.where((p) => _armGroup(((p as Map)['throws'] ?? '').toString()) == _pitcherArm).toList();
    }

    filtered.sort((a, b) {
      final am = a as Map;
      final bm = b as Map;
      switch (_pitcherSort) {
        case 'era':
          // ascending; 0 (no IP) goes to bottom
          final ae = (am['era'] as num?)?.toDouble() ?? 0;
          final be = (bm['era'] as num?)?.toDouble() ?? 0;
          final ae2 = ae == 0 ? 99.99 : ae;
          final be2 = be == 0 ? 99.99 : be;
          return ae2.compareTo(be2);
        case 'whip':
          final aw = (am['whip'] as num?)?.toDouble() ?? 0;
          final bw = (bm['whip'] as num?)?.toDouble() ?? 0;
          final aw2 = aw == 0 ? 99.99 : aw;
          final bw2 = bw == 0 ? 99.99 : bw;
          return aw2.compareTo(bw2);
        case 'wins':       return _cmpDesc(bm['wins'],       am['wins']);
        case 'strikeouts': return _cmpDesc(bm['strikeouts'], am['strikeouts']);
        case 'saves':      return _cmpDesc(bm['saves'],      am['saves']);
        case 'holds':      return _cmpDesc(bm['holds'],      am['holds']);
        case 'war':        return _cmpDesc(bm['war'],        am['war']);
        default:           return 0;
      }
    });

    _pitchers = filtered;
  }

  int _cmpDesc(dynamic b, dynamic a) =>
      ((b as num?) ?? 0).compareTo((a as num?) ?? 0);

  Timer? _searchDebounce;

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () => _search(q));
    setState(() {}); // clear 버튼 표시 갱신
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      if (mounted) setState(() => _searchResults = []);
      return;
    }
    try {
      final data = await ApiService.searchPlayers(query);
      if (mounted) setState(() => _searchResults = data['players'] ?? []);
    } catch (e) { debugPrint('player_screen: $e'); }
  }

  String _hitterStat(Map p) {
    switch (_hitterSort) {
      case 'avg':          return (p['avg'] as num?)?.toStringAsFixed(3) ?? '-';
      case 'home_runs':    return '${p['home_runs'] ?? 0}';
      case 'rbis':         return '${p['rbis'] ?? 0}';
      case 'hits':         return '${p['hits'] ?? 0}';
      case 'stolen_bases': return '${p['stolen_bases'] ?? 0}';
      case 'ops':          return (p['ops'] as num?)?.toStringAsFixed(3) ?? '-';
      case 'war':          return (p['war'] as num?)?.toStringAsFixed(1) ?? '-';
      default:             return '-';
    }
  }

  String _pitcherStat(Map p) {
    switch (_pitcherSort) {
      case 'era':        return (p['era'] as num?)?.toStringAsFixed(2) ?? '-';
      case 'wins':       return '${p['wins'] ?? 0}';
      case 'strikeouts': return '${p['strikeouts'] ?? 0}';
      case 'saves':      return '${p['saves'] ?? 0}';
      case 'holds':      return '${p['holds'] ?? 0}';
      case 'whip':       return (p['whip'] as num?)?.toStringAsFixed(2) ?? '-';
      case 'war':        return (p['war'] as num?)?.toStringAsFixed(1) ?? '-';
      default:           return '-';
    }
  }

  // ── 팀 필터 칩 — 팀컬러 tint 스타일 (mockup) ──
  Widget _buildTeamFilterChips(VoidCallback onSelect) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
    final line = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
    final paper2 = isDark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6);
    final ink2 = isDark ? const Color(0xFFC9C9D1) : const Color(0xFF3F3F46);

    Widget chip({required String label, required bool active, required Color color, required VoidCallback onTap}) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          margin: const EdgeInsets.only(right: 5),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: isDark ? 0.22 : 0.12) : paper2,
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(color: active ? color.withValues(alpha: 0.45) : line),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? color : ink2)),
        ),
      );
    }

    return _fadeStrip(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 0),
        children: [
          chip(label: '전체', active: _selectedTeamId == null, color: ink, onTap: () {
            setState(() => _selectedTeamId = null);
            onSelect();
          }),
          ..._teams.map((t) {
            final tm = t as Map;
            final tid = tm['id'] as int?;
            final code = tm['short_name'] as String? ?? '';
            final raw = teamColor(code);
            final c = isDark ? Color.lerp(raw, Colors.white, 0.25)! : raw;
            return chip(
              label: tm['name'] ?? '',
              active: _selectedTeamId == tid,
              color: c,
              onTap: () {
                setState(() => _selectedTeamId = _selectedTeamId == tid ? null : tid);
                onSelect();
              },
            );
          }),
        ],
      ),
    );
  }

  // 가로 칩 스트립 — 가장자리 페이드(ShaderMask)로 자연스럽게 사라지게
  Widget _fadeStrip({required double height, required Widget child}) => SizedBox(
    height: height,
    child: ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.centerLeft, end: Alignment.centerRight,
        colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
        stops: [0.0, 0.04, 0.96, 1.0],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: child,
    ),
  );

  // ── 스탯 칩 + 리스트/카드 토글 (mockup) ──
  Widget _buildSortChips(
    List<Map<String, String>> sorts,
    String selected,
    void Function(String) onSelect,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
    final inkOn = isDark ? Colors.black : Colors.white;
    final line = isDark ? const Color(0xFF33333A) : const Color(0xFFE0E0E4);
    final paper = isDark ? const Color(0xFF18181C) : Colors.white;
    final sub = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: _fadeStrip(
        height: 32,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          children: sorts.map((s) {
            final sel = selected == s['value'];
            return GestureDetector(
              onTap: () => onSelect(s['value']!),
              child: Container(
                alignment: Alignment.center,
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: sel ? ink : paper,
                  borderRadius: BorderRadius.circular(Radii.pill),
                  border: Border.all(color: sel ? ink : line),
                ),
                child: Text(s['label']!,
                    style: TextStyle(fontSize: 12,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        color: sel ? inkOn : sub)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _openDetail(Map p) {
    final code = p['team_code'] as String? ?? '';
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerDetailScreen(
        playerId: p['id'],
        initialData: {'name': p['name'], 'team': teamDisplayName(code), 'profile_image': p['profile_image'], 'number': p['number'], 'player_type': p['player_type'], 'team_code': code},
      )),
    );
  }

  // 선수 이미지 원형 아바타 (팀컬러 테두리, 이미지 없으면 등번호 fallback)
  Widget _numAvatar(Map p, double size) {
    final code = p['team_code'] as String? ?? '';
    final c = teamColor(code);
    final img = p['profile_image'] as String?;
    Widget fallback = Container(
      color: c.withValues(alpha: 0.88),
      child: Center(
        child: Text('#${p['number'] ?? '-'}',
            style: TextStyle(color: Colors.white, fontSize: size * 0.28,
                fontWeight: FontWeight.w800, letterSpacing: 0)),
      ),
    );
    return Hero(
      tag: 'player_${p['id']}',
      child: SizedBox(
        width: size, height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size, height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.withValues(alpha: 0.45), width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: (img != null && img.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: img, fit: BoxFit.cover,
                      errorWidget: (_, _, _) => fallback,
                    )
                  : fallback,
            ),
            // 등번호 미니 배지 (우하단) — 번호 있을 때만
            if (p['number'] != null)
              Positioned(
                right: -2, bottom: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: Text('#${p['number']}',
                      style: const TextStyle(color: Colors.white, fontSize: 8,
                          fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── 순위 리스트 행 (mockup _RankListRow) ──
  Widget _buildRankRow(int rank, Map p, String statVal, String statLabel) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
    final ink2 = isDark ? const Color(0xFFC9C9D1) : const Color(0xFF3F3F46);
    final sub = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final line = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
    final code = p['team_code'] as String? ?? '';
    final raw = teamColor(code);
    final tc = isDark ? Color.lerp(raw, Colors.white, 0.25)! : raw;
    final isTop3 = rank <= 3;
    final position = p['position'] as String? ?? p['player_type'] as String? ?? '';

    return InkWell(
      onTap: () => _openDetail(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: line))),
          child: Row(children: [
            SizedBox(
              width: 28,
              child: Text('$rank', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: isTop3 ? 18 : 14, fontWeight: FontWeight.w800,
                      color: isTop3 ? tc : sub,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
            const SizedBox(width: 11),
            _numAvatar(p, 42),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p['name'] ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: ink)),
                const SizedBox(height: 4),
                Text('${teamDisplayName(code)} · $position',
                    style: TextStyle(fontSize: 10, color: ink2)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(statVal,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                      color: ink, letterSpacing: 0,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              Text(statLabel, style: TextStyle(fontSize: 9, color: sub)),
            ]),
          ]),
        ),
      ),
    );
  }

  // ── 카드 그리드 셀 (mockup _PlayerCard — 팀컬러 헤더 + 등번호) ──
  Widget _buildStatCard(int rank, Map p, String statVal, String statLabel) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final ink3 = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    final paper = isDark ? const Color(0xFF18181C) : Colors.white;
    final line = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
    final code = p['team_code'] as String? ?? '';
    final raw = teamColor(code);
    final tcText = isDark ? Color.lerp(raw, Colors.white, 0.25)! : raw;
    final position = p['position'] as String? ?? p['player_type'] as String? ?? '';

    return GestureDetector(
      onTap: () => _openDetail(p),
      child: Container(
        decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: line),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.04), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 11),
            color: raw.withValues(alpha: 0.9),
            child: Stack(children: [
              if (rank <= 3)
                Positioned(
                  right: 9, top: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text('#$rank',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white70)),
                  ),
                ),
              Center(child: Column(children: [
                Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.15),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.32), width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ((p['profile_image'] as String?)?.isNotEmpty ?? false)
                      ? CachedNetworkImage(
                          imageUrl: p['profile_image'] as String, fit: BoxFit.cover,
                          errorWidget: (_, _, _) => Center(child: Text('#${p['number'] ?? '-'}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white))),
                        )
                      : Center(child: Text('#${p['number'] ?? '-'}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white))),
                ),
                const SizedBox(height: 7),
                Text(p['name'] ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
              ])),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Flexible(
                    child: Text(statVal,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: tcText,
                            letterSpacing: 0, fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                  const SizedBox(width: 4),
                  Text(statLabel, style: TextStyle(fontSize: 10, color: sub)),
                ]),
                const SizedBox(height: 5),
                Text('${teamDisplayName(code)} · $position',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: ink3)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildPlayerShimmer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
      itemCount: 10,
      itemBuilder: (_, _) => Shimmer.fromColors(
        baseColor: base,
        highlightColor: highlight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(children: [
            Container(width: 28, height: 16, color: Colors.white),
            const SizedBox(width: 11),
            Container(width: 42, height: 42,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
            const SizedBox(width: 11),
            Expanded(child: Container(height: 14, color: Colors.white)),
            const SizedBox(width: 30),
            Container(width: 50, height: 22, color: Colors.white),
          ]),
        ),
      ),
    );
  }

  Widget _buildRankedBody(List players, String Function(Map) statOf, String label) {
    final navBottom = (ApiService.myTeamData.value.isNotEmpty ? 144.0 : 92.0) + MediaQuery.of(context).padding.bottom;
    if (_isListView) {
      return ListView.builder(
        padding: EdgeInsets.only(bottom: navBottom),
        itemCount: players.length,
        itemBuilder: (_, i) {
          final p = players[i] as Map;
          return _buildRankRow(i + 1, p, statOf(p), label);
        },
      );
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(18, 4, 18, navBottom),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.68,
      ),
      itemCount: players.length,
      itemBuilder: (_, i) {
        final p = players[i] as Map;
        return _buildStatCard(i + 1, p, statOf(p), label);
      },
    );
  }

  Widget _buildHitterList() {
    if (_hitterLoading) return _buildPlayerShimmer(context);
    if (_hitters.isEmpty) return const Center(child: Text('데이터가 없습니다'));
    final label = _hitterSorts.firstWhere((s) => s['value'] == _hitterSort)['label']!;
    return _buildRankedBody(_hitters, (p) => _hitterStat(p), label);
  }

  Widget _buildPitcherList() {
    if (_pitcherLoading) return _buildPlayerShimmer(context);
    if (_pitchers.isEmpty) return const Center(child: Text('데이터가 없습니다'));
    final label = _pitcherSorts.firstWhere((s) => s['value'] == _pitcherSort)['label']!;
    return _buildRankedBody(_pitchers, (p) => _pitcherStat(p), label);
  }

  Widget _buildPopularityTab() {
    if (_popularLoading) {
      return Center(child: CircularProgressIndicator(color: SemColor.brand(context), strokeWidth: 2.5));
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = _popularShowTeam ? _popularTeams : _popularPlayers;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _popularShowTeam = false),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: !_popularShowTeam ? SemColor.brand(context) : Colors.grey.withValues(alpha: 0.12),
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                    ),
                    child: Text('선수',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: !_popularShowTeam ? (Theme.of(context).brightness == Brightness.dark ? SemColor.panelDark : Colors.white) : Colors.grey[600])),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _popularShowTeam = true),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _popularShowTeam ? SemColor.brand(context) : Colors.grey.withValues(alpha: 0.12),
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
                    ),
                    child: Text('구단',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _popularShowTeam ? (Theme.of(context).brightness == Brightness.dark ? SemColor.panelDark : Colors.white) : Colors.grey[600])),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!_isLoggedIn)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 13, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text('로그인하면 하트를 눌러 투표할 수 있어요',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ),
        if (items.isEmpty && !_popularLoading)
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite_border, size: 48, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text('아직 투표 기록이 없어요\n선수 상세에서 ♥를 눌러 투표해보세요!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[500])),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loadPopularity,
                  child: const Text('새로고침'),
                ),
              ],
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadPopularity,
              child: ListView.separated(
                padding: EdgeInsets.only(bottom: (ApiService.myTeamData.value.isNotEmpty ? 144.0 : 92.0) + MediaQuery.of(context).padding.bottom),
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, indent: 64, endIndent: 16, color: Colors.grey.withValues(alpha: 0.15)),
                itemBuilder: (_, i) {
                  final item = items[i] as Map;
                  final voted = item['voted'] as bool? ?? false;
                  final count = item['vote_count'] as int? ?? 0;
                  if (_popularShowTeam) {
                    final code = item['short_name'] as String? ?? '';
                    final logoUrl = item['logo_url'] as String?;
                    return ListTile(
                      leading: SizedBox(
                        width: 40,
                        height: 40,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: teamColor(code).withValues(alpha: 0.1),
                              child: TeamLogo(teamCode: code, size: 32, logoUrl: logoUrl),
                            ),
                            if (i < 3)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: i == 0 ? const Color(0xFFFFD700) : i == 1 ? const Color(0xFFC0C0C0) : const Color(0xFFCD7F32),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(child: Text('${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white))),
                                ),
                              ),
                          ],
                        ),
                      ),
                      title: Text(item['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: GestureDetector(
                        onTap: () => _voteTeam(item['id'] as int),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              voted ? Icons.favorite : Icons.favorite_border,
                              color: voted ? Colors.red : (isDark ? Colors.grey[400] : Colors.grey[500]),
                              size: 22,
                            ),
                            Text('$count',
                                style: TextStyle(fontSize: 11, color: Colors.grey[600],
                                    fontWeight: voted ? FontWeight.bold : FontWeight.normal)),
                          ],
                        ),
                      ),
                    );
                  } else {
                    final code = item['team_code'] as String? ?? '';
                    final img = item['profile_image'] as String?;
                    return ListTile(
                      leading: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: teamColor(code).withValues(alpha: 0.15),
                            backgroundImage: (img != null && img.isNotEmpty)
                                ? CachedNetworkImageProvider(img)
                                : null,
                            child: (img == null || img.isEmpty)
                                ? Text(teamDisplayName(code).characters.take(2).string,
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: teamColor(code)))
                                : null,
                          ),
                          if (i < 3)
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: i == 0 ? const Color(0xFFFFD700) : i == 1 ? const Color(0xFFC0C0C0) : const Color(0xFFCD7F32),
                                shape: BoxShape.circle,
                              ),
                              child: Center(child: Text('${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white))),
                            ),
                        ],
                      ),
                      title: Text(item['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${item['team_name'] ?? ''}  ${item['position'] ?? ''}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      trailing: GestureDetector(
                        onTap: () => _votePlayer(item['id'] as int),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              voted ? Icons.favorite : Icons.favorite_border,
                              color: voted ? Colors.red : (isDark ? Colors.grey[400] : Colors.grey[500]),
                              size: 22,
                            ),
                            Text('$count',
                                style: TextStyle(fontSize: 11, color: Colors.grey[600],
                                    fontWeight: voted ? FontWeight.bold : FontWeight.normal)),
                          ],
                        ),
                      ),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => PlayerDetailScreen(
                            playerId: item['id'] as int,
                            initialData: {'name': item['name'], 'team': item['team_name'] ?? teamDisplayName(item['team_code'] ?? ''), 'profile_image': item['profile_image'], 'position': item['position'], 'player_type': item['player_type']},
                          ))),
                    );
                  }
                },
              ),
            ),
          ),
      ],
    );
  }

  // ── 헤더 아이콘 버튼 (mockup 32×32 rounded10 border) ──
  Widget _headerIconBtn(IconData icon, String tip, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final line = isDark ? const Color(0xFF33333A) : const Color(0xFFE0E0E4);
    final sub3 = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: line),
          ),
          child: Icon(icon, size: 18, color: sub3),
        ),
      ),
    );
  }

  // ── 검색 풀스크린 오버레이 (mockup _SearchOverlay) ──
  Widget _buildSearchOverlay() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
    final ink3 = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    final sub = isDark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2);
    final bg = isDark ? const Color(0xFF111113) : const Color(0xFFFAFAFB);
    final bar = isDark ? const Color(0xFF18181C) : Colors.white;
    final paper2 = isDark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6);
    final line = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);

    return Material(
      color: bg,
      child: SafeArea(
        child: Column(children: [
          Container(
            color: bar,
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
            child: Row(children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: paper2,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: line),
                  ),
                  child: Row(children: [
                    Icon(Icons.search, size: 16, color: sub),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        autofocus: true,
                        style: TextStyle(fontSize: 14, color: ink),
                        decoration: InputDecoration(
                          hintText: '선수 이름 검색',
                          border: InputBorder.none, isDense: true,
                          contentPadding: EdgeInsets.zero,
                          hintStyle: TextStyle(color: sub, fontSize: 14),
                        ),
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() => _searchResults = []);
                        },
                        child: Icon(Icons.close, size: 16, color: sub),
                      ),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() { _isSearching = false; _searchResults = []; });
                },
                child: Text('취소',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ink3)),
              ),
            ]),
          ),
          Expanded(
            child: _searchController.text.isEmpty
                ? Center(child: Text('선수 이름이나 팀명을 입력해주세요', style: TextStyle(color: sub)))
                : _searchResults.isEmpty
                    ? Center(child: Text('검색 결과가 없습니다', style: TextStyle(color: sub)))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, _) => Divider(height: 1, color: line),
                        itemBuilder: (_, i) {
                          final p = _searchResults[i] as Map;
                          return InkWell(
                            onTap: () {
                              _openDetail(p);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(children: [
                                _numAvatar(p, 42),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(p['name'] ?? '',
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink)),
                                    const SizedBox(height: 4),
                                    Text('${p['team'] ?? ''} · ${p['position'] ?? p['player_type'] ?? ''} · #${p['number'] ?? '-'}',
                                        style: TextStyle(fontSize: 10, color: ink3)),
                                  ]),
                                ),
                              ]),
                            ),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
    final sub = isDark ? const Color(0xFF9A9AA2) : const Color(0xFF9A9AA2);
    final bar = isDark ? const Color(0xFF18181C) : Colors.white;
    final line = isDark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
    final themeProv = context.watch<ThemeProvider>();

    return Scaffold(
      body: Stack(children: [
        Column(children: [
          // ── 헤더 (mockup): '선수' 타이틀 + 검색/테마 아이콘 버튼 + TabBar ──
          Container(
            color: bar,
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                child: Row(children: [
                  Text('선수',
                      style: TextStyle(fontSize: Typo.h2, fontWeight: Typo.extra,
                          letterSpacing: -0.5, color: ink)),
                  const Spacer(),
                  _headerIconBtn(Icons.search, '검색',
                      () => setState(() => _isSearching = true)),
                  const SizedBox(width: 7),
                  _headerIconBtn(
                      _isListView ? Icons.grid_view_rounded : Icons.view_list_rounded,
                      _isListView ? '카드 보기' : '리스트 보기',
                      () => setState(() => _isListView = !_isListView)),
                  const SizedBox(width: 7),
                  _headerIconBtn(
                      isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                      isDark ? '라이트 모드' : '다크 모드',
                      () => themeProv.toggle()),
                  const SizedBox(width: 7),
                  _headerIconBtn(Icons.person_outline, '마이페이지',
                      () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const MyPageScreen()))),
                ]),
              ),
              TabBar(
                controller: _tabController,
                tabs: const [Tab(text: '타자'), Tab(text: '투수'), Tab(text: '인기투표')],
                labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                labelColor: ink,
                unselectedLabelColor: sub,
                indicatorColor: ink,
                indicatorWeight: 2,
                dividerColor: line,
              ),
            ]),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                Column(
                  children: [
                    const SizedBox(height: 6),
                    _buildSortChips(_hitterSorts, _hitterSort, (val) {
                      setState(() {
                        _hitterSort = val;
                        _applyHitterFilter();
                      });
                    }),
                    const SizedBox(height: 4),
                    _buildSortChips(_hitterPosOpts, _hitterPos, (val) {
                      setState(() {
                        _hitterPos = val;
                        _applyHitterFilter();
                      });
                    }),
                    const SizedBox(height: 4),
                    _buildTeamFilterChips(() {
                      setState(_applyHitterFilter);
                    }),
                    const SizedBox(height: 4),
                    const Divider(height: 1),
                    Expanded(child: _buildHitterList()),
                  ],
                ),
                Column(
                  children: [
                    const SizedBox(height: 6),
                    _buildSortChips(_pitcherSorts, _pitcherSort, (val) {
                      setState(() {
                        _pitcherSort = val;
                        _applyPitcherFilter();
                      });
                    }),
                    const SizedBox(height: 4),
                    _buildSortChips(_pitcherArmOpts, _pitcherArm, (val) {
                      setState(() {
                        _pitcherArm = val;
                        _applyPitcherFilter();
                      });
                    }),
                    const SizedBox(height: 4),
                    _buildTeamFilterChips(() {
                      setState(_applyPitcherFilter);
                    }),
                    const SizedBox(height: 4),
                    const Divider(height: 1),
                    Expanded(child: _buildPitcherList()),
                  ],
                ),
                _buildPopularityTab(),
              ],
            ),
          ),
        ]),
        if (_isSearching) Positioned.fill(child: _buildSearchOverlay()),
      ]),
    );
  }
}
