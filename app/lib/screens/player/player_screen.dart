import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../api/api_service.dart';
import '../../utils/local_cache.dart';
import '../../utils/team_theme.dart';
import 'player_detail_screen.dart';
import 'player_compare_screen.dart';
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

  List _teams = [];
  int? _selectedTeamId;

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
    } catch (_) {}
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

  void _applyHitterFilter() {
    List filtered = _selectedTeamId == null
        ? List.from(_allHitters)
        : _allHitters.where((p) {
            final code = (p as Map)['team_code'] as String? ?? '';
            return _teams.any((t) =>
                t['id'] == _selectedTeamId &&
                t['short_name'] == code);
          }).toList();

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

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() { _isSearching = false; _searchResults = []; });
      return;
    }
    try {
      final data = await ApiService.searchPlayers(query);
      if (mounted) setState(() { _searchResults = data['players'] ?? []; _isSearching = true; });
    } catch (_) {}
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

  Widget _buildTeamFilterChips(VoidCallback onSelect) {
    return SizedBox(
      height: 34,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
        itemCount: _teams.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            final sel = _selectedTeamId == null;
            return GestureDetector(
              onTap: () {
                setState(() => _selectedTeamId = null);
                onSelect();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: sel ? SemColor.panelDark : Colors.grey.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text('전체',
                    style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.black87,
                        fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
              ),
            );
          }
          final t = _teams[i - 1] as Map;
          final tid = t['id'] as int?;
          final code = t['short_name'] as String? ?? '';
          final sel = _selectedTeamId == tid;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedTeamId = tid);
              onSelect();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: sel ? teamColor(code) : Colors.grey.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: sel ? null : Border.all(color: Colors.grey.withValues(alpha: 0.25)),
              ),
              child: Text(t['name'] ?? '',
                  style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.black87,
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSortChips(
    List<Map<String, String>> sorts,
    String selected,
    void Function(String) onSelect,
  ) {
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        itemCount: sorts.length,
        itemBuilder: (_, i) {
          final s = sorts[i];
          final sel = selected == s['value'];
          return GestureDetector(
            onTap: () => onSelect(s['value']!),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: sel ? SemColor.panelDark : Colors.grey.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                s['label']!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                  color: sel ? Colors.white : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlayerCard(Map p, String statVal, String statLabel) {
    final code = p['team_code'] as String? ?? '';
    final img = p['profile_image'] as String?;
    final color = teamColor(code);
    final number = p['number'];
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PlayerDetailScreen(
          playerId: p['id'],
          initialData: {'name': p['name'], 'team': teamDisplayName(code), 'profile_image': p['profile_image'], 'number': p['number'], 'player_type': p['player_type']},
        )),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: (img != null && img.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: img,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorWidget: (_, _, _) => _playerPlaceholder(code, color),
                          )
                        : _playerPlaceholder(code, color),
                  ),
                  if (number != null)
                    Positioned(
                      top: 4, left: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text('#$number',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  Positioned(
                    top: 4, right: 4,
                    child: TeamLogo(teamCode: code, size: 18, logoUrl: p['logo_url']),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
              child: Column(
                children: [
                  Text(p['name'] ?? '',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(statVal,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
                      const SizedBox(width: 3),
                      Text(statLabel,
                          style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playerPlaceholder(String code, Color color) {
    return Container(
      color: color.withValues(alpha: 0.12),
      child: Center(
        child: Icon(Icons.person, size: 40, color: color.withValues(alpha: 0.4)),
      ),
    );
  }

  Widget _buildPlayerShimmer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(12, 8, 12, (ApiService.myTeamData.value.isNotEmpty ? 144.0 : 92.0) + MediaQuery.of(context).padding.bottom),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.72,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: 12,
      itemBuilder: (_, _) => Shimmer.fromColors(
        baseColor: base,
        highlightColor: highlight,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildHitterList() {
    if (_hitterLoading) return _buildPlayerShimmer(context);
    if (_hitters.isEmpty) return const Center(child: Text('데이터가 없습니다'));
    final label = _hitterSorts.firstWhere((s) => s['value'] == _hitterSort)['label']!;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(12, 8, 12, (ApiService.myTeamData.value.isNotEmpty ? 144.0 : 92.0) + MediaQuery.of(context).padding.bottom),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.72,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _hitters.length,
      itemBuilder: (_, i) => _buildPlayerCard(_hitters[i] as Map, _hitterStat(_hitters[i] as Map), label),
    );
  }

  Widget _buildPitcherList() {
    if (_pitcherLoading) return _buildPlayerShimmer(context);
    if (_pitchers.isEmpty) return const Center(child: Text('데이터가 없습니다'));
    final label = _pitcherSorts.firstWhere((s) => s['value'] == _pitcherSort)['label']!;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(12, 8, 12, (ApiService.myTeamData.value.isNotEmpty ? 144.0 : 92.0) + MediaQuery.of(context).padding.bottom),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.72,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _pitchers.length,
      itemBuilder: (_, i) => _buildPlayerCard(_pitchers[i] as Map, _pitcherStat(_pitchers[i] as Map), label),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) return const Center(child: Text('검색 결과가 없습니다'));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _searchResults.length,
      itemBuilder: (_, i) {
        final p = _searchResults[i] as Map;
        final img = p['profile_image'] as String?;
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: (img != null && img.isNotEmpty) ? CachedNetworkImageProvider(img) : null,
            child: (img == null || img.isEmpty) ? const Icon(Icons.person) : null,
          ),
          title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${p['team'] ?? ''} | ${p['player_type'] ?? ''} | #${p['number'] ?? '-'}'),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => PlayerDetailScreen(
                playerId: p['id'],
                initialData: {'name': p['name'], 'team': p['team'], 'profile_image': p['profile_image'], 'number': p['number'], 'player_type': p['player_type']},
              ))),
        );
      },
    );
  }

  Widget _buildPopularityTab() {
    if (_popularLoading) {
      return const Center(child: CircularProgressIndicator(color: SemColor.panelDark, strokeWidth: 2.5));
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
                      color: !_popularShowTeam ? SemColor.panelDark : Colors.grey.withValues(alpha: 0.12),
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                    ),
                    child: Text('선수',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: !_popularShowTeam ? Colors.white : Colors.grey[600])),
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
                      color: _popularShowTeam ? SemColor.panelDark : Colors.grey.withValues(alpha: 0.12),
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
                    ),
                    child: Text('구단',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _popularShowTeam ? Colors.white : Colors.grey[600])),
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
                Text('아직 투표 기록이 없어요\n첫 번째로 투표해보세요!',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        title: const Text('선수 기록'),
        actions: [
          IconButton(
            icon: const Icon(Icons.compare_arrows),
            tooltip: '선수 비교',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PlayerCompareScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: '마이페이지',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyPageScreen())),
          ),
        ],
        surfaceTintColor: Colors.transparent,
        bottom: _isSearching
            ? null
            : TabBar(
                controller: _tabController,
                indicatorColor: SemColor.panelDark,
                indicatorWeight: 2.5,
                labelColor: SemColor.panelDark,
                unselectedLabelColor: Colors.grey,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
                dividerColor: Colors.transparent,
                tabs: const [Tab(text: '타자'), Tab(text: '투수'), Tab(text: '인기투표')],
              ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _searchController,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: '선수 이름 검색',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() { _isSearching = false; _searchResults = []; });
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                isDense: true,
              ),
            ),
          ),
          if (!_isSearching) ...[
            const Divider(height: 1, thickness: 1),
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
          ] else ...[
            const Divider(height: 1, thickness: 1),
            Expanded(child: _buildSearchResults()),
          ],
        ],
      ),
    );
  }
}
