import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import 'dart:async';
import 'package:shimmer/shimmer.dart';
import '../../api/api_service.dart';
import '../../utils/local_cache.dart';
import '../../utils/team_theme.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import 'player_detail_screen.dart';
import '../mypage/my_page_screen.dart';
import '../../utils/web_image.dart';
import '../../utils/web_safe_area.dart';

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
    {'value': '지명타자', 'label': '지명타자'},
  ];
  static const List<Map<String, String>> _pitcherArmOpts = [
    {'value': '전체', 'label': '전체'}, {'value': '우완', 'label': '우완'},
    {'value': '좌완', 'label': '좌완'}, {'value': '언더', 'label': '언더'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _loadTeams();
    _loadHitters();
    _loadPitchers();
    _loadRecent();
  }

  List _recent = [];
  Future<void> _loadRecent() async {
    final r = await LocalCache.getRecentPlayers();
    if (mounted) setState(() => _recent = r);
  }

  Widget _buildRecentStrip(Color ink, Color sub) {
    if (_recent.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 26,
      margin: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        const SizedBox(width: 14),
        Icon(Icons.history, size: 12, color: sub),
        const SizedBox(width: 5),
        Expanded(child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _recent.length,
          separatorBuilder: (c, i) => const SizedBox(width: 5),
          itemBuilder: (_, i) {
            final p = _recent[i] as Map;
            final code = p['team_code'] as String? ?? '';
            final tc = teamColor(code);
            return GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerDetailScreen(
                playerId: p['id'] as int,
                initialData: {'name': p['name'], 'team_code': code, 'team': teamDisplayName(code)},
              ))).then((_) { if (mounted) _loadRecent(); }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tc.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tc.withValues(alpha: 0.30)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 5, height: 5, decoration: BoxDecoration(color: tc, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(p['name'] ?? '', style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.medium, color: ink)),
                ]),
              ),
            );
          },
        )),
        const SizedBox(width: 8),
      ]),
    );
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
  // ── 필터 드롭다운 (정렬·포지션·팀 — 1줄 압축) ──
  Widget _filterDropdown<T>({
    required String currentLabel,
    required bool active,
    required T initial,
    required List<PopupMenuEntry<T>> items,
    required ValueChanged<T> onSelected,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
    final line = isDark ? const Color(0xFF33333A) : const Color(0xFFE0E0E4);
    final paper2 = isDark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6);
    final onActive = isDark ? Colors.black : Colors.white;
    final sub = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    return PopupMenuButton<T>(
      initialValue: initial,
      onSelected: onSelected,
      itemBuilder: (_) => items,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      color: isDark ? const Color(0xFF1F1F24) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: line),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: active ? ink : paper2,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: active ? ink : line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(currentLabel,
              style: TextStyle(fontSize: Typo.small, fontWeight: Typo.bold,
                  color: active ? onActive : ink)),
          const SizedBox(width: 3),
          Icon(Icons.keyboard_arrow_down_rounded, size: 16,
              color: active ? onActive : sub),
        ]),
      ),
    );
  }

  Widget _buildFilterBar({
    required List<Map<String, String>> sorts,
    required String sortVal,
    required ValueChanged<String> onSort,
    required List<Map<String, String>> posOpts,
    required String posVal,
    required String posHint,
    required ValueChanged<String> onPos,
    required VoidCallback onApply,
  }) {
    String labelOf(List<Map<String, String>> o, String v) =>
        o.firstWhere((e) => e['value'] == v, orElse: () => {'label': v})['label']!;
    final teamLabel = _selectedTeamId == null
        ? '전체 팀'
        : ((_teams.firstWhere((t) => (t as Map)['id'] == _selectedTeamId,
                orElse: () => {'name': '팀'}) as Map)['name'] as String? ?? '팀');
    PopupMenuItem<String> opt(Map<String, String> s) => PopupMenuItem<String>(
        value: s['value'], height: 42,
        child: Text(s['label']!, style: const TextStyle(fontSize: Typo.body)));
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
      child: Row(children: [
        _filterDropdown<String>(
            currentLabel: labelOf(sorts, sortVal), active: true,
            initial: sortVal, onSelected: onSort,
            items: sorts.map(opt).toList()),
        const SizedBox(width: 8),
        _filterDropdown<String>(
            currentLabel: posVal == '전체' ? posHint : labelOf(posOpts, posVal),
            active: posVal != '전체',
            initial: posVal, onSelected: onPos,
            items: posOpts.map(opt).toList()),
        const SizedBox(width: 8),
        _filterDropdown<int?>(
            currentLabel: teamLabel, active: _selectedTeamId != null,
            initial: _selectedTeamId,
            onSelected: (v) { setState(() => _selectedTeamId = v); onApply(); },
            items: [
              const PopupMenuItem<int?>(value: null, height: 42,
                  child: Text('전체 팀', style: TextStyle(fontSize: Typo.body))),
              ..._teams.map((t) {
                final tm = t as Map;
                return PopupMenuItem<int?>(value: tm['id'] as int?, height: 42,
                    child: Text(tm['name'] ?? '', style: const TextStyle(fontSize: Typo.body)));
              }),
            ]),
      ]),
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
    ).then((_) { if (mounted) _loadRecent(); });
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
                fontWeight: Typo.extra, letterSpacing: 0)),
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
                  ? netImage(
                      img, fit: BoxFit.cover,
                      error: () => fallback,
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
                      style: const TextStyle(color: Colors.white, fontSize: Typo.micro,
                          fontWeight: Typo.extra)),
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
    final sub = isDark ? const Color(0xFF8E8E98) : const Color(0xFF9A9AA2);
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
                  style: TextStyle(fontSize: isTop3 ? 18 : 14, fontWeight: Typo.extra,
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
                    style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra, color: ink)),
                const SizedBox(height: 4),
                Text('${teamDisplayName(code)} · $position',
                    style: TextStyle(fontSize: Typo.mini, color: ink2)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(statVal,
                  style: TextStyle(fontSize: Typo.h2, fontWeight: Typo.extra,
                      color: ink, letterSpacing: 0,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              Text(statLabel, style: TextStyle(fontSize: Typo.micro, color: sub)),
            ]),
          ]),
        ),
      ),
    );
  }

  // ── 카드 그리드 셀 (mockup _PlayerCard — 팀컬러 헤더 + 등번호) ──
  Widget _buildStatCard(int rank, Map p, String statVal, String statLabel) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = isDark ? const Color(0xFF8E8E98) : const Color(0xFF9A9AA2);
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
                        style: const TextStyle(fontSize: Typo.micro, fontWeight: Typo.extra, color: Colors.white70)),
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
                      ? netImage(
                          p['profile_image'] as String, fit: BoxFit.cover,
                          error: () => Center(child: Text('#${p['number'] ?? '-'}',
                              style: const TextStyle(fontSize: Typo.title, fontWeight: Typo.extra, color: Colors.white))),
                        )
                      : Center(child: Text('#${p['number'] ?? '-'}',
                          style: const TextStyle(fontSize: Typo.title, fontWeight: Typo.extra, color: Colors.white))),
                ),
                const SizedBox(height: 7),
                Text(p['name'] ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: Typo.body, fontWeight: Typo.extra, color: Colors.white)),
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
                        style: TextStyle(fontSize: Typo.h1, fontWeight: Typo.extra, color: tcText,
                            letterSpacing: 0, fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                  const SizedBox(width: 4),
                  Text(statLabel, style: TextStyle(fontSize: Typo.mini, color: sub)),
                ]),
                const SizedBox(height: 5),
                Text('${teamDisplayName(code)} · $position',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: Typo.mini, color: ink3)),
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
        // 500행 리스트 스크롤 비용 절감 — 행 높이를 1회 측정으로 고정
        prototypeItem: players.isEmpty
            ? null
            : _buildRankRow(1, players.first as Map,
                statOf(players.first as Map), label),
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
    final sub = isDark ? const Color(0xFF8E8E98) : const Color(0xFF9A9AA2);
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
                        style: TextStyle(fontSize: Typo.subtitle, color: ink),
                        decoration: InputDecoration(
                          hintText: '선수 이름 검색',
                          border: InputBorder.none, isDense: true,
                          contentPadding: EdgeInsets.zero,
                          hintStyle: TextStyle(color: sub, fontSize: Typo.subtitle),
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
                    style: TextStyle(fontSize: Typo.body, fontWeight: Typo.medium, color: ink3)),
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
                                        style: TextStyle(fontSize: Typo.body, fontWeight: Typo.bold, color: ink)),
                                    const SizedBox(height: 4),
                                    Text('${p['team'] ?? ''} · ${p['position'] ?? p['player_type'] ?? ''} · #${p['number'] ?? '-'}',
                                        style: TextStyle(fontSize: Typo.mini, color: ink3)),
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
                padding: EdgeInsets.fromLTRB(18, headerTopGap(context), 18, 12),
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
              _buildRecentStrip(ink, sub),
              TabBar(
                controller: _tabController,
                tabs: const [Tab(text: '타자'), Tab(text: '투수')],
                labelStyle: const TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra),
                unselectedLabelStyle: const TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.medium),
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
                    _buildFilterBar(
                      sorts: _hitterSorts, sortVal: _hitterSort,
                      onSort: (val) => setState(() { _hitterSort = val; _applyHitterFilter(); }),
                      posOpts: _hitterPosOpts, posVal: _hitterPos, posHint: '포지션',
                      onPos: (val) => setState(() { _hitterPos = val; _applyHitterFilter(); }),
                      onApply: () => setState(_applyHitterFilter),
                    ),
                    const Divider(height: 1),
                    Expanded(child: _buildHitterList()),
                  ],
                ),
                Column(
                  children: [
                    _buildFilterBar(
                      sorts: _pitcherSorts, sortVal: _pitcherSort,
                      onSort: (val) => setState(() { _pitcherSort = val; _applyPitcherFilter(); }),
                      posOpts: _pitcherArmOpts, posVal: _pitcherArm, posHint: '투구',
                      onPos: (val) => setState(() { _pitcherArm = val; _applyPitcherFilter(); }),
                      onApply: () => setState(_applyPitcherFilter),
                    ),
                    const Divider(height: 1),
                    Expanded(child: _buildPitcherList()),
                  ],
                ),
              ],
            ),
          ),
        ]),
        if (_isSearching) Positioned.fill(child: _buildSearchOverlay()),
      ]),
    );
  }
}
