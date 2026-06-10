import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/web_image.dart';
import '../../api/api_service.dart';
import '../../utils/local_cache.dart';
import '../../utils/team_theme.dart';
import '../../services/widget_service.dart';
import '../player/player_detail_screen.dart';
import '../game/game_detail_screen.dart';
import '../community/post_detail_screen.dart';

// 구단 공식 외부 링크 (short_name 코드 기준). 유튜브/인스타/굿즈샵 = 사용자 제공(정확)
const Map<String, Map<String, String>> _teamLinks = {
  'LG': {'yt': 'https://www.youtube.com/@lg_twins', 'ig': 'https://www.instagram.com/lgtwinsbaseballclub', 'home': 'https://www.lgtwins.com', 'gd': 'https://www.lgtwins.com/shop'},
  'KT': {'yt': 'https://www.youtube.com/@ktwiz_baseballclub', 'ig': 'https://www.instagram.com/ktwiz.pr', 'home': 'https://www.ktwiz.co.kr', 'gd': 'https://ktwizstore.co.kr/'},
  'SK': {'yt': 'https://www.youtube.com/@ssglanders', 'ig': 'https://www.instagram.com/ssglanders.incheon', 'home': 'https://www.ssglanders.com', 'gd': 'https://landerscorestore.co.kr/'},
  'NC': {'yt': 'https://www.youtube.com/@ncdinos', 'ig': 'https://www.instagram.com/ncdinos2011', 'home': 'https://www.ncdinos.com', 'gd': 'https://store.ncdinos.com'},
  'OB': {'yt': 'https://www.youtube.com/@doosanbears', 'ig': 'https://www.instagram.com/doosanbears.1982', 'home': 'https://www.doosanbears.com', 'gd': 'https://www.doosanbears.com/shop'},
  'HT': {'yt': 'https://www.youtube.com/@kiatigers', 'ig': 'https://www.instagram.com/always_kia_tigers', 'home': 'https://www.tigers.co.kr', 'gd': 'https://teamstore.tigers.co.kr'},
  'LT': {'yt': 'https://www.youtube.com/@lottegiants', 'ig': 'https://www.instagram.com/busanlottegiants', 'home': 'https://www.giantsclub.com', 'gd': 'https://www.lotteon.com/display/seller/sellerShop/lottegiants'},
  'SS': {'yt': 'https://www.youtube.com/@samsunglions', 'ig': 'https://www.instagram.com/samsunglions_baseballclub', 'home': 'https://www.samsunglions.com', 'gd': 'https://shop.berriz.in'},
  'HH': {'yt': 'https://www.youtube.com/@hanwhaeagles_official', 'ig': 'https://www.instagram.com/hanwhaeagles_soori', 'home': 'https://www.hanwhaeagles.co.kr', 'gd': 'https://eaglesshop.co.kr'},
  'WO': {'yt': 'https://www.youtube.com/@heroesbaseballclub', 'ig': 'https://www.instagram.com/heroesbaseballclub', 'home': 'https://www.heroesbaseball.co.kr', 'gd': 'https://nolmdshop.com/category/%ED%82%A4%EC%9B%80%ED%9E%88%EC%96%B4%EB%A1%9C%EC%A6%88/29/'},
};

class TeamDetailScreen extends StatefulWidget {
  final Map<String, dynamic> team;
  const TeamDetailScreen({required this.team, super.key});

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  int _mainTabIndex = 0;
  int _gameSubIndex = 0;
  List _players = [];
  List _games = [];
  List _rosterChanges = [];
  List _news = [];
  List _communityPosts = [];
  List _monthlyStats = [];
  List _h2hRecords = [];
  List _battingOrderStats = [];
  Map<String, dynamic>? _seasonStats;
  bool _playersLoading = true;
  bool _gamesLoading = false;
  bool _rosterLoading = false;
  bool _newsLoading = false;
  bool _communityLoading = false;
  bool _monthlyLoading = false;
  bool _h2hLoading = false;
  bool _battingOrderLoading = false;
  bool _isFav = false;
  bool _favLoading = false;
  num? _gamesBehind;
  // 선수 탭 필터 (타자 포지션 / 투수 구위)
  String _batFilter = '전체';
  String _pitFilter = '전체';
  final PageController _tabPageController = PageController();

  @override
  void initState() {
    super.initState();
    _loadPlayers();
    _loadFavStatus();
    _loadSeasonStats();
    _loadGamesBehind();
    _loadRosterChanges();
    _loadNews();
  }

  // 메인 탭 슬라이드 전환
  void _goToMainTab(int i) {
    if (i == _mainTabIndex) return;
    _tabPageController.animateToPage(i,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  void _onMainTabChange(int idx) {
    setState(() => _mainTabIndex = idx);
    if (idx == 2 && _games.isEmpty && !_gamesLoading) _loadGames();
    if (idx == 3 && _communityPosts.isEmpty && !_communityLoading) _loadCommunityPosts();
  }

  void _onGameSubChange(int idx) {
    setState(() => _gameSubIndex = idx);
    if (idx == 1 && _monthlyStats.isEmpty && !_monthlyLoading) _loadMonthlyStats();
    if (idx == 2 && _h2hRecords.isEmpty && !_h2hLoading) _loadH2H();
    if (idx == 3 && _battingOrderStats.isEmpty && !_battingOrderLoading) _loadBattingOrder();
  }

  Future<void> _loadGamesBehind() async {
    // widget.team에 games_behind 있으면 그대로 사용
    final existing = widget.team['games_behind'];
    if (existing != null) {
      if (mounted) setState(() => _gamesBehind = existing as num);
      return;
    }
    // 없으면 team_rankings 캐시에서 보완
    final cached = await LocalCache.getStale('team_rankings') as List?;
    if (cached != null) {
      final teamId = widget.team['id'];
      try {
        final found = cached.firstWhere((t) => t['id'] == teamId, orElse: () => null);
        if (found != null && found['games_behind'] != null && mounted) {
          setState(() => _gamesBehind = found['games_behind'] as num);
          return;
        }
      } catch (e) { debugPrint('team_detail: $e'); }
    }
    // 캐시도 없으면 API 호출
    try {
      final data = await ApiService.getTeamRankings();
      final rankings = data['rankings'] as List? ?? [];
      await LocalCache.set('team_rankings', rankings);
      final teamId = widget.team['id'];
      final found = rankings.firstWhere((t) => t['id'] == teamId, orElse: () => null);
      if (found != null && mounted) setState(() => _gamesBehind = found['games_behind'] as num?);
    } catch (e) { debugPrint('team_detail: $e'); }
  }

  Future<void> _loadFavStatus() async {
    final cached = await LocalCache.get('favorite_teams') as List?;
    final id = widget.team['id'] as int;
    if (cached != null && mounted) {
      setState(() => _isFav = cached.any((t) => (t as Map)['id'] == id));
    }
    try {
      final data = await ApiService.getFavoriteTeams();
      final teams = data['teams'] as List? ?? [];
      await LocalCache.set('favorite_teams', teams);
      if (mounted) setState(() => _isFav = teams.any((t) => t['id'] == id));
    } catch (e) { debugPrint('team_detail: $e'); }
  }

  Future<void> _loadSeasonStats() async {
    final teamId = widget.team['id'] as int;
    final ck = 'team_season_stats_$teamId';
    final cached = await LocalCache.get(ck, maxAgeSeconds: 1800) as Map?;
    if (cached != null && mounted) setState(() => _seasonStats = Map<String, dynamic>.from(cached));
    try {
      final data = await ApiService.getTeamSeasonStats(teamId);
      await LocalCache.set(ck, data);
      if (mounted) setState(() => _seasonStats = data);
    } catch (e) { debugPrint('team_detail: $e'); }
  }

  Future<void> _toggleFav() async {
    setState(() => _favLoading = true);
    try {
      final id = widget.team['id'] as int;
      if (_isFav) {
        await ApiService.removeFavoriteTeam(id);
        final currentWidgetTeam = await WidgetService.getTeamId();
        if (currentWidgetTeam == id) await WidgetService.setTeamId(null);
      } else {
        await ApiService.addFavoriteTeam(id);
        final currentWidgetTeam = await WidgetService.getTeamId();
        if (currentWidgetTeam == null) await WidgetService.setTeamId(id);
      }
      if (mounted) setState(() => _isFav = !_isFav);
      ApiService.favoriteTeamsChanged.value++;
    } catch (e) { debugPrint('team_detail: $e'); }
    if (mounted) setState(() => _favLoading = false);
  }

  @override
  void dispose() {
    _tabPageController.dispose();
    super.dispose();
  }

  Future<void> _loadPlayers() async {
    final teamId = widget.team['id'] as int;
    final cacheKey = 'team_players_$teamId';
    final cached = await LocalCache.get(cacheKey, maxAgeSeconds: 300) as List?;
    if (cached != null && mounted) {
      setState(() { _players = cached; _playersLoading = false; });
    }
    try {
      final data = await ApiService.getTeamPlayers(teamId);
      final players = data['players'] as List? ?? [];
      await LocalCache.set(cacheKey, players);
      if (mounted) setState(() { _players = players; _playersLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _playersLoading = false);
    }
  }

  Future<void> _loadGames() async {
    final teamId = widget.team['id'] as int;
    final ck = 'team_games_$teamId';
    final cached = await LocalCache.get(ck, maxAgeSeconds: 600) as List?;
    if (cached != null && mounted) {
      setState(() { _games = cached; _gamesLoading = false; });
    } else if (mounted) {
      setState(() => _gamesLoading = true);
    }
    try {
      final data = await ApiService.getTeamGames(teamId);
      final games = data['games'] as List? ?? [];
      await LocalCache.set(ck, games);
      if (mounted) setState(() { _games = games; _gamesLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _gamesLoading = false);
    }
  }

  Future<void> _loadRosterChanges() async {
    final teamId = widget.team['id'] as int;
    final ck = 'team_roster_changes_$teamId';
    final cached = await LocalCache.get(ck, maxAgeSeconds: 300) as List?;
    if (cached != null && mounted) {
      setState(() { _rosterChanges = cached; _rosterLoading = false; });
    } else if (mounted) {
      setState(() => _rosterLoading = true);
    }
    try {
      final data = await ApiService.getTeamRosterChanges(teamId, days: 30);
      final changes = data['changes'] as List? ?? [];
      await LocalCache.set(ck, changes);
      if (mounted) setState(() { _rosterChanges = changes; _rosterLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _rosterLoading = false);
    }
  }

  Future<void> _loadNews() async {
    final teamId = widget.team['id'] as int;
    final ck = 'team_news_$teamId';
    final cached = await LocalCache.get(ck, maxAgeSeconds: 1800) as List?;
    if (cached != null && mounted) {
      setState(() { _news = cached; _newsLoading = false; });
    } else if (mounted) {
      setState(() => _newsLoading = true);
    }
    try {
      final data = await ApiService.getTeamNews(teamId, limit: 30);
      final news = data['news'] as List? ?? [];
      await LocalCache.set(ck, news);
      if (mounted) setState(() { _news = news; _newsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _newsLoading = false);
    }
  }

  Future<void> _loadCommunityPosts() async {
    final teamId = widget.team['id'] as int;
    final ck = 'team_community_$teamId';
    final cached = await LocalCache.get(ck, maxAgeSeconds: 300) as List?;
    if (cached != null && mounted) {
      setState(() { _communityPosts = cached; _communityLoading = false; });
    } else if (mounted) {
      setState(() => _communityLoading = true);
    }
    try {
      final data = await ApiService.getPosts(teamId: teamId, sort: 'latest', page: 1);
      final posts = data['posts'] as List? ?? [];
      await LocalCache.set(ck, posts);
      if (mounted) setState(() { _communityPosts = posts; _communityLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _communityLoading = false);
    }
  }

  Future<void> _loadMonthlyStats() async {
    final teamId = widget.team['id'] as int;
    final ck = 'team_monthly_$teamId';
    final cached = await LocalCache.get(ck, maxAgeSeconds: 3600) as List?;
    if (cached != null && mounted) {
      setState(() { _monthlyStats = cached; _monthlyLoading = false; });
    } else if (mounted) {
      setState(() => _monthlyLoading = true);
    }
    try {
      final data = await ApiService.getTeamMonthlyStats(teamId);
      final stats = data['monthly'] as List? ?? [];
      await LocalCache.set(ck, stats);
      if (mounted) setState(() { _monthlyStats = stats; _monthlyLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _monthlyLoading = false);
    }
  }

  Future<void> _loadH2H() async {
    final teamId = widget.team['id'] as int;
    final ck = 'team_h2h_$teamId';
    final cached = await LocalCache.get(ck, maxAgeSeconds: 3600) as List?;
    if (cached != null && mounted) {
      setState(() { _h2hRecords = cached; _h2hLoading = false; });
    } else if (mounted) {
      setState(() => _h2hLoading = true);
    }
    try {
      final data = await ApiService.getTeamHeadToHead(teamId);
      final records = data['records'] as List? ?? [];
      await LocalCache.set(ck, records);
      if (mounted) setState(() { _h2hRecords = records; _h2hLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _h2hLoading = false);
    }
  }

  Future<void> _loadBattingOrder() async {
    final teamId = widget.team['id'] as int;
    final ck = 'team_batting_order_$teamId';
    final cached = await LocalCache.get(ck, maxAgeSeconds: 1800) as List?;
    if (cached != null && mounted) {
      setState(() { _battingOrderStats = cached; _battingOrderLoading = false; });
    } else if (mounted) {
      setState(() => _battingOrderLoading = true);
    }
    try {
      final data = await ApiService.getTeamBattingOrder(teamId);
      final stats = data['stats'] as List? ?? [];
      await LocalCache.set(ck, stats);
      if (mounted) setState(() { _battingOrderStats = stats; _battingOrderLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _battingOrderLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = widget.team;
    final code = team['short_name'] as String? ?? '';
    final color = teamColor(code);
    final wins = team['wins'] as int? ?? 0;
    final losses = team['losses'] as int? ?? 0;
    final draws = team['draws'] as int? ?? 0;
    final hr = (team['home_record'] as Map?)?.cast<String, dynamic>() ?? {};
    final ar = (team['away_record'] as Map?)?.cast<String, dynamic>() ?? {};
    final vp = MediaQuery.of(context).viewPadding.bottom;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F12) : const Color(0xFFFAFAFB),
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // ── 팀컬러 헤더 (Option A: 흰색 _Btn32 back/star) ──
          Container(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            color: color,
            child: Row(children: [
              _WhiteBtn32(icon: Icons.chevron_left, onTap: () => Navigator.maybePop(context)),
              const SizedBox(width: 10),
              Expanded(child: Text(team['name'] ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5))),
              _favLoading
                  ? const SizedBox(width: 32, height: 32,
                      child: Padding(padding: EdgeInsets.all(7),
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
                  : _WhiteBtn32(
                      icon: _isFav ? Icons.star_rounded : Icons.star_border_rounded,
                      onTap: _toggleFav),
            ]),
          ),
          Expanded(
            child: Stack(children: [
              Padding(
                padding: EdgeInsets.only(bottom: 64 + vp),
                // PageView(스와이프 비활성)+animateToPage = 탭 슬라이드, keepalive로 상태 보존
                child: PageView(
                  controller: _tabPageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: _onMainTabChange,
                  children: [
                    _KeepAlive(child: _buildOverviewTab(team, code, color, wins, losses, draws, hr, ar)),
                    _KeepAlive(child: _buildPlayers()),
                    _KeepAlive(child: _buildGamesTab()),
                    _KeepAlive(child: _buildCommunity()),
                  ],
                ),
              ),
              Positioned(
                left: 16, right: 16,
                bottom: 12 + vp,
                child: _buildMainFloatingNav(color),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildMainFloatingNav(Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const labels = ['개요', '선수', '경기', '커뮤'];
    const icons = [Icons.home_outlined, Icons.people_outlined, Icons.sports_baseball_outlined, Icons.forum_outlined];
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF26262C) : Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: isDark ? Border.all(color: const Color(0xFF3A3A42)) : null,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.12), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: LayoutBuilder(builder: (ctx, c) {
        final slotW = c.maxWidth / labels.length;
        return Stack(children: [
          // 슬라이딩 선택 하이라이트
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            left: _mainTabIndex * slotW + 4,
            top: 4, bottom: 4,
            width: slotW - 8,
            child: Container(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
          Row(
            children: List.generate(labels.length, (i) {
              final selected = _mainTabIndex == i;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _goToMainTab(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icons[i], size: 18, color: selected ? color : Colors.grey),
                      const SizedBox(height: 1),
                      Text(labels[i], style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                        color: selected ? color : Colors.grey,
                      )),
                    ],
                  ),
                ),
              );
            }),
          ),
        ]);
      }),
    );
  }

  Widget _buildOverviewTab(Map team, String code, Color color, int wins, int losses, int draws, Map<String, dynamic> hr, Map<String, dynamic> ar) {
    final cs = _C(context);
    final rosters = _rosterChanges.take(6).toList();
    final newsList = _news.take(6).toList();
    return ListView(padding: EdgeInsets.zero, children: [
      _buildHeader(team, code, color, wins, losses, draws, hr, ar),
      // 등록말소
      _SectionLabel(label: '최근 등록말소', cs: cs),
      if (_rosterLoading)
        _CardWrap(cs: cs, child: Padding(padding: const EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: color))))
      else if (rosters.isEmpty)
        _CardWrap(cs: cs, child: Padding(padding: const EdgeInsets.all(16),
            child: Text('최근 30일 등록말소 내역이 없습니다', style: TextStyle(color: cs.sub, fontSize: 12))))
      else
        _CardWrap(cs: cs, child: Column(children: rosters.asMap().entries.map((e) =>
            _buildChangeItem(cs, Map<String, dynamic>.from(e.value as Map), e.key == rosters.length - 1)).toList())),
      // 뉴스
      _SectionLabel(label: '최근 뉴스', cs: cs),
      if (_newsLoading)
        _CardWrap(cs: cs, child: Padding(padding: const EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: color))))
      else if (newsList.isEmpty)
        _CardWrap(cs: cs, child: Padding(padding: const EdgeInsets.all(16),
            child: Text('뉴스가 없습니다', style: TextStyle(color: cs.sub, fontSize: 12))))
      else
        _CardWrap(cs: cs, child: Column(children: newsList.asMap().entries.map((e) =>
            _buildNewsItem(cs, e.value as Map, e.key == newsList.length - 1)).toList())),
      const SizedBox(height: 24),
    ]);
  }

  Widget _buildNewsItem(_C cs, Map n, bool last) {
    final title = n['title'] as String? ?? '';
    final media = n['media'] as String? ?? '';
    final pub = n['published_at'] as String?;
    final url = n['url'] as String? ?? '';
    final thumbnail = n['thumbnail'] as String? ?? '';
    String dateStr = '';
    if (pub != null) {
      try {
        final dt = DateTime.parse(pub).toLocal();
        dateStr = '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (e) { debugPrint('team_detail: $e'); }
    }
    return GestureDetector(
      onTap: () => _openUrl(url),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (thumbnail.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: webSafeImageUrl(thumbnail),
                  width: 72, height: 54, fit: BoxFit.cover,
                  placeholder: (_, _) => Container(width: 72, height: 54, color: cs.paper2),
                  errorWidget: (_, _, _) => Container(width: 72, height: 54, color: cs.paper2,
                      child: Icon(Icons.article_outlined, color: cs.sub, size: 20)),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(fontSize: 12, fontWeight: Typo.medium, color: cs.ink, height: 1.45),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  Row(children: [
                    if (media.isNotEmpty) ...[
                      Text(media, style: TextStyle(fontSize: 10, color: cs.sub)),
                      const SizedBox(width: 6),
                    ],
                    if (dateStr.isNotEmpty)
                      Text(dateStr, style: TextStyle(fontSize: 10, color: cs.sub)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGamesTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = teamColor(widget.team['short_name'] as String? ?? '');
    const subLabels = ['최근경기', '월별성적', '상대전적', '타순별'];
    return Column(
      children: [
        Container(
          color: isDark ? const Color(0xFF18181C) : Colors.white,
          child: SizedBox(
            height: 40,
            child: Row(
              children: List.generate(subLabels.length, (i) {
                final selected = _gameSubIndex == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _onGameSubChange(i),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(
                          color: selected ? color : Colors.transparent,
                          width: 2.5,
                        )),
                      ),
                      child: Text(subLabels[i], style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                        color: selected
                            ? color
                            : (isDark ? Colors.grey[400] : Colors.grey),
                      )),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _gameSubIndex,
            children: [_buildGames(), _buildMonthlyStats(), _buildHeadToHead(), _buildBattingOrder()],
          ),
        ),
      ],
    );
  }

  Widget _buildSeasonStatsBar(_C cs) {
    final bat = (_seasonStats!['batting'] as Map?)?.cast<String, dynamic>() ?? {};
    final pit = (_seasonStats!['pitching'] as Map?)?.cast<String, dynamic>() ?? {};
    final rec = (_seasonStats!['record'] as Map?)?.cast<String, dynamic>() ?? {};
    return Container(
      decoration: BoxDecoration(color: cs.paper, border: Border.all(color: cs.line), borderRadius: BorderRadius.circular(Radii.md)),
      child: IntrinsicHeight(child: Row(children: [
        _StatBlock(label: '팀타율', value: (bat['avg'] as num?)?.toStringAsFixed(3) ?? '-', cs: cs),
        VerticalDivider(width: 1, color: cs.line),
        _StatBlock(label: '방어율', value: (pit['era'] as num?)?.toStringAsFixed(2) ?? '-', cs: cs),
        VerticalDivider(width: 1, color: cs.line),
        _StatBlock(label: 'WHIP', value: (pit['whip'] as num?)?.toStringAsFixed(2) ?? '-', cs: cs),
        VerticalDivider(width: 1, color: cs.line),
        _StatBlock(label: '득점', value: '${rec['runs_scored'] ?? '-'}', cs: cs),
        VerticalDivider(width: 1, color: cs.line),
        _StatBlock(label: '실점', value: '${rec['runs_allowed'] ?? '-'}', cs: cs),
        VerticalDivider(width: 1, color: cs.line),
        _StatBlock(label: '홈런', value: '${bat['home_runs'] ?? '-'}', cs: cs),
      ])),
    );
  }

  Widget _buildHeader(Map team, String code, Color color,
      int wins, int losses, int draws,
      Map<String, dynamic> hr, Map<String, dynamic> ar) {
    final cs = _C(context);
    final gb = _gamesBehind ?? team['games_behind'] as num?;
    final gbText = (gb == null || gb == 0) ? '선두' : '${gb.toStringAsFixed(1)} 게임차';
    final pythag = (team['pythag_winpct'] as num?)?.toStringAsFixed(3);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: cs.dark ? 0.14 : 0.06),
        border: Border(bottom: BorderSide(color: color.withValues(alpha: cs.dark ? 0.3 : 0.15))),
      ),
      child: Column(children: [
        Row(children: [
          TeamLogo(teamCode: code, size: 64, logoUrl: team['logo_url']),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(team['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 20, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.5))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: Text('${team['rank'] ?? '-'}위', style: TextStyle(fontSize: 12, fontWeight: Typo.bold, color: color)),
              ),
            ]),
            const SizedBox(height: 5),
            Text('$wins승 $losses패${draws > 0 ? ' $draws무' : ''} · 승률 ${(team['win_rate'] as num?)?.toStringAsFixed(3) ?? '-'} · $gbText',
                style: TextStyle(fontSize: 13, color: cs.ink3)),
            const SizedBox(height: 3),
            Text('홈 ${hr['wins'] ?? 0}-${hr['losses'] ?? 0} · 원정 ${ar['wins'] ?? 0}-${ar['losses'] ?? 0}'
                '${pythag != null ? ' · 피타고리안 $pythag' : ''}',
                style: TextStyle(fontSize: 11, color: cs.sub)),
          ])),
        ]),
        if (_teamLinks[code] != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            _linkBtn(Icons.smart_display, '유튜브', color, _teamLinks[code]!['yt'], color),
            const SizedBox(width: 7),
            _linkBtn(Icons.photo_camera, '인스타', color, _teamLinks[code]!['ig'], color),
            const SizedBox(width: 7),
            _linkBtn(Icons.shopping_bag, '굿즈', color, _teamLinks[code]!['gd'], color),
            const SizedBox(width: 7),
            _linkBtn(Icons.language, '공식홈', color, _teamLinks[code]!['home'], color),
          ]),
        ],
        if (_seasonStats != null) ...[
          const SizedBox(height: 14),
          _buildSeasonStatsBar(cs),
        ],
      ]),
    );
  }

  Widget _linkBtn(IconData icon, String label, Color iconColor, String? url, Color teamColor) {
    if (url == null || url.isEmpty) return const Expanded(child: SizedBox.shrink());
    final cs = _C(context);
    return Expanded(child: GestureDetector(
      onTap: () async {
        final u = Uri.tryParse(url);
        if (u == null) return;
        try {
          await launchUrl(u, mode: LaunchMode.externalApplication);
        } catch (_) {
          try { await launchUrl(u, mode: LaunchMode.platformDefault); } catch (_) {}
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: teamColor.withValues(alpha: cs.dark ? 0.14 : 0.07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 10, color: cs.ink, fontWeight: FontWeight.w600)),
        ]),
      ),
    ));
  }

  // 타자 position → 필터 그룹 (포수/내야/외야/DH)
  String _posType(String pos) {
    if (pos.contains('포수')) return '포수';
    if (pos.contains('지명')) return 'DH';
    if (pos.contains('외야') || pos.contains('좌익') || pos.contains('중견') || pos.contains('우익')) return '외야';
    return '내야';
  }
  // 투수 throws → 구위 (우완/좌완/언더)
  String _armType(String throws) {
    if (throws.contains('좌')) return '좌완';
    if (throws.contains('언') || throws.contains('사')) return '언더';
    return '우완';
  }

  Widget _buildPlayers() {
    final cs = _C(context);
    final color = teamColor(widget.team['short_name'] as String? ?? '');
    if (_playersLoading) return Center(child: CircularProgressIndicator(color: color, strokeWidth: 2.5));
    if (_players.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadPlayers,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 180),
            Center(child: Text('선수 정보가 없습니다\n아래로 당겨서 새로고침',
                textAlign: TextAlign.center, style: TextStyle(color: cs.sub))),
          ],
        ),
      );
    }

    final batters = _players.where((p) => p['player_type'] == '타자').toList();
    final pitchers = _players.where((p) => p['player_type'] == '투수').toList();
    final batF = _batFilter == '전체' ? batters
        : batters.where((p) => _posType(((p as Map)['position'] ?? '').toString()) == _batFilter).toList();
    final pitF = _pitFilter == '전체' ? pitchers
        : pitchers.where((p) => _armType(((p as Map)['throws'] ?? '').toString()) == _pitFilter).toList();

    return Row(children: [
      // 타자 열
      Expanded(child: Container(
        decoration: BoxDecoration(border: Border(right: BorderSide(color: cs.line))),
        child: Column(children: [
          _ColumnHeader(title: '타자', filters: const ['전체', '포수', '내야', '외야'],
              selected: _batFilter, tc: color, cs: cs, onSelect: (f) => setState(() => _batFilter = f)),
          Expanded(child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: batF.length,
            itemBuilder: (_, i) => _teamPlayerRow(cs, color, batF[i] as Map, isPitcher: false),
          )),
        ]),
      )),
      // 투수 열
      Expanded(child: Column(children: [
        _ColumnHeader(title: '투수', filters: const ['전체', '우완', '좌완', '언더'],
            selected: _pitFilter, tc: color, cs: cs, onSelect: (f) => setState(() => _pitFilter = f)),
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 80),
          itemCount: pitF.length,
          itemBuilder: (_, i) => _teamPlayerRow(cs, color, pitF[i] as Map, isPitcher: true),
        )),
      ])),
    ]);
  }

  Widget _teamPlayerRow(_C cs, Color color, Map p, {required bool isPitcher}) {
    final arm = isPitcher ? _armType((p['throws'] ?? '').toString()) : '';
    final armColor = arm == '좌완' ? const Color(0xFF2563EB)
        : arm == '언더' ? const Color(0xFF9333EA) : color;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerDetailScreen(
        playerId: p['id'],
        initialData: {'name': p['name'], 'team': widget.team['name'], 'position': p['position'],
          'player_type': p['player_type'], 'number': p['number'], 'team_code': widget.team['short_name']},
      ))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.line))),
        child: Row(children: [
          _NumChip(no: p['number'] as int?, tc: color, cs: cs),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: cs.ink)),
            const SizedBox(height: 3),
            if (isPitcher)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: armColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3)),
                child: Text(arm, style: TextStyle(fontSize: 9, fontWeight: Typo.bold, color: armColor)),
              )
            else
              Text(p['position'] ?? '', style: TextStyle(fontSize: 10, color: cs.sub)),
          ])),
        ]),
      ),
    );
  }

  List<List<Map>> _groupIntoSeries(List games, String teamName) {
    final sorted = List<Map>.from(games)
      ..sort((a, b) => (a['game_date'] as String).compareTo(b['game_date'] as String));

    final series = <List<Map>>[];

    for (final g in sorted) {
      final isHome = g['home_team'] == teamName;
      final opp = isHome ? g['away_team'] : g['home_team'];
      final date = DateTime.tryParse(g['game_date'] as String? ?? '') ?? DateTime(2000);

      if (series.isEmpty) {
        series.add([g]);
        continue;
      }

      final last = series.last;
      final lastG = last.last;
      final lastIsHome = lastG['home_team'] == teamName;
      final lastOpp = lastIsHome ? lastG['away_team'] : lastG['home_team'];
      final lastDate = DateTime.tryParse(lastG['game_date'] as String? ?? '') ?? DateTime(2000);
      final dayDiff = date.difference(lastDate).inDays;

      if (lastOpp == opp && dayDiff <= 3 && last.length < 3) {
        last.add(g);
      } else {
        series.add([g]);
      }
    }

    return series.reversed.toList();
  }

  String _gResult(Map g, String teamName) {
    final isHome = g['home_team'] == teamName;
    final my = isHome ? (g['home_score'] ?? 0) : (g['away_score'] ?? 0);
    final opp = isHome ? (g['away_score'] ?? 0) : (g['home_score'] ?? 0);
    if ((my as num) > (opp as num)) return 'win';
    if (my < opp) return 'loss';
    return 'draw';
  }

  Widget _buildGames() {
    final cs = _C(context);
    final tc = teamColor(widget.team['short_name'] as String? ?? '');
    if (_gamesLoading) return Center(child: CircularProgressIndicator(color: tc, strokeWidth: 2.5));
    if (_games.isEmpty) return Center(child: Text('경기 정보가 없습니다', style: TextStyle(color: cs.sub)));

    final teamName = widget.team['name'] as String? ?? '';
    final seriesList = _groupIntoSeries(_games, teamName); // 최근 시리즈 우선

    return ListView(
      padding: const EdgeInsets.all(18),
      children: seriesList.map((s) => _seriesCard(cs, tc, teamName, s)).toList(),
    );
  }

  Widget _seriesCard(_C cs, Color tc, String teamName, List s) {
    final games = s.cast<Map>();
    int wins = 0, losses = 0, draws = 0;
    for (final g in games) {
      final r = _gResult(g, teamName);
      if (r == 'win') {
        wins++;
      } else if (r == 'loss') {
        losses++;
      } else {
        draws++;
      }
    }
    final first = games.first;
    final firstIsHome = first['home_team'] == teamName;
    final oppName = (firstIsHome ? first['away_team'] : first['home_team']) ?? '';
    final oppCode = (firstIsHome ? first['away_code'] : first['home_code']) as String? ?? '';
    final isWinning = wins > losses;
    final label = wins == games.length ? '스윕승'
        : losses == games.length ? '스윕패'
        : wins > losses ? '위닝' : wins < losses ? '루징' : '스플릿';
    // 승=팀컬러, 패/무=무채색(패 진한 / 무 연한)
    final labelColor = isWinning ? tc : wins < losses ? const Color(0xFF71717A) : cs.sub;
    Color rc(String r) => r == 'win' ? tc : r == 'draw' ? const Color(0xFFA1A1AA) : const Color(0xFF71717A);
    // 날짜 범위
    final dates = games.map((g) => (g['game_date'] as String? ?? '')).toList()..sort();
    String md(String d) => d.length >= 10 ? '${d.substring(5, 7)}.${d.substring(8, 10)}' : d;
    final dateRange = dates.isEmpty ? '' : '${md(dates.first)}~${md(dates.last).substring(md(dates.last).length - 2)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.paper,
        border: Border.all(color: isWinning ? tc.withValues(alpha: 0.3) : cs.line),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(children: [
        // 헤더
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.line))),
          child: Row(children: [
            Text(dateRange, style: TextStyle(fontSize: 11, color: cs.sub)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: labelColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Radii.pill)),
              child: Text(label, style: TextStyle(fontSize: 11, fontWeight: Typo.extra, color: labelColor)),
            ),
          ]),
        ),
        // 3등분
        IntrinsicHeight(child: Row(children: [
          // ① 상대팀
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              TeamLogo(teamCode: oppCode, size: 44),
              const SizedBox(height: 7),
              Text('vs $oppName', style: TextStyle(fontSize: 13, fontWeight: Typo.extra, color: cs.ink)),
            ]),
          )),
          VerticalDivider(width: 1, color: cs.line),
          // ② 경기별 스코어
          Expanded(child: Column(children: games.asMap().entries.map((e) {
            final g = e.value;
            final last = e.key == games.length - 1;
            final r = _gResult(g, teamName);
            final gid = g['id'] as int?;
            final d = (g['game_date'] as String? ?? '');
            return GestureDetector(
              onTap: gid != null ? () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => GameDetailScreen(gameId: gid))) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
                child: Row(children: [
                  SizedBox(width: 30, child: Text(d.length >= 10 ? '${d.substring(5, 7)}.${d.substring(8, 10)}' : d,
                      style: TextStyle(fontSize: 10, color: cs.sub))),
                  Expanded(child: Text('${g['home_score'] ?? 0} : ${g['away_score'] ?? 0}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, fontWeight: Typo.extra, color: cs.ink))),
                  Container(width: 18, height: 18,
                    decoration: BoxDecoration(color: rc(r), borderRadius: BorderRadius.circular(5)),
                    child: Center(child: Text(r == 'win' ? '승' : r == 'draw' ? '무' : '패',
                        style: TextStyle(fontSize: 10, fontWeight: Typo.extra,
                            color: cs.dark ? const Color(0xFF0F0F12) : Colors.white)))),
                ]),
              ),
            );
          }).toList())),
          VerticalDivider(width: 1, color: cs.line),
          // ③ 시리즈 요약
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: games.map((g) => Container(
                width: 14, height: 14, margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(color: rc(_gResult(g, teamName)), borderRadius: BorderRadius.circular(4)),
              )).toList()),
              const SizedBox(height: 8),
              Text('$wins승$losses패${draws > 0 ? '$draws무' : ''}',
                  style: TextStyle(fontSize: 18, fontWeight: Typo.extra, color: labelColor)),
              const SizedBox(height: 4),
              Text('${games.length}연전', style: TextStyle(fontSize: 10, color: cs.sub)),
            ]),
          )),
        ])),
      ]),
    );
  }


  Widget _buildChangeItem(_C cs, Map<String, dynamic> c, bool last) {
    final changeType = c['change_type'] as String? ?? '';
    final playerName = c['player_name'] as String? ?? '';
    final reason = c['reason'] as String? ?? '';
    final position = c['position'] as String? ?? '';
    final playerId = c['player_id'] as int?;

    final typeColor = changeType == '1군등록' ? const Color(0xFF2563EB)
        : changeType == '부상자명단' ? SemColor.live
        : changeType == '임의탈퇴' ? cs.sub
        : SemColor.warning; // 등록말소 등

    return GestureDetector(
      onTap: playerId != null
          ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: playerId)))
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5)),
            child: Text(changeType, style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: typeColor)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Row(children: [
            Flexible(child: Text(playerName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: cs.ink))),
            if (reason.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(child: Text(reason, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: cs.sub))),
            ],
          ])),
          if (position.isNotEmpty) Text(position, style: TextStyle(fontSize: 11, color: cs.sub)),
        ]),
      ),
    );
  }


  Widget _buildCommunity() {
    final cs = _C(context);
    final color = teamColor(widget.team['short_name'] as String? ?? '');
    final teamShort = (widget.team['name'] as String? ?? '').split(' ').first;
    if (_communityLoading) return Center(child: CircularProgressIndicator(color: color, strokeWidth: 2.5));
    if (_communityPosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('커뮤니티 글이 없습니다', style: TextStyle(color: cs.sub)),
            const SizedBox(height: 12),
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('새로고침'),
              onPressed: () {
                setState(() => _communityPosts = []);
                _loadCommunityPosts();
              },
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _communityPosts = []);
        await _loadCommunityPosts();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(18),
        itemCount: _communityPosts.length,
        itemBuilder: (_, i) {
          final post = _communityPosts[i] as Map;
          final title = post['title'] as String? ?? '';
          final nickname = post['nickname'] as String? ?? '';
          final views = post['views'] as int? ?? 0;
          final likes = post['likes'] as int? ?? 0;
          final comments = post['comment_count'] as int? ?? 0;
          final category = post['category'] as String? ?? '';
          final createdAt = post['created_at'] as String?;
          final postId = post['id'] as int?;

          String dateStr = '';
          if (createdAt != null) {
            try {
              final dt = DateTime.parse(createdAt).toLocal();
              final diff = DateTime.now().difference(dt);
              if (diff.inMinutes < 60) {
                dateStr = '${diff.inMinutes}분 전';
              } else if (diff.inHours < 24) {
                dateStr = '${diff.inHours}시간 전';
              } else {
                dateStr = '${dt.month}/${dt.day}';
              }
            } catch (e) { debugPrint('team_detail: $e'); }
          }

          return GestureDetector(
            onTap: postId != null
                ? () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)))
                : null,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.paper, border: Border.all(color: cs.line),
                borderRadius: BorderRadius.circular(Radii.lg),
                boxShadow: cs.dark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 2, offset: const Offset(0, 1))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 5, children: [
                    _SmallChip(label: teamShort, color: color, bg: color.withValues(alpha: 0.1)),
                    if (category.isNotEmpty)
                      _SmallChip(label: category, color: cs.ink3, bg: cs.paper2, border: cs.line),
                  ]),
                  const SizedBox(height: 7),
                  Text(title,
                      style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: cs.ink, height: 1.45),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Row(children: [
                    Text(nickname, style: TextStyle(fontSize: 10, color: cs.sub)),
                    if (dateStr.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(dateStr, style: TextStyle(fontSize: 10, color: cs.sub)),
                    ],
                    const Spacer(),
                    Icon(Icons.visibility_outlined, size: 12, color: cs.sub),
                    const SizedBox(width: 2),
                    Text('$views', style: TextStyle(fontSize: 10, color: cs.sub)),
                    const SizedBox(width: 8),
                    Icon(Icons.favorite_border, size: 12, color: cs.sub),
                    const SizedBox(width: 2),
                    Text('$likes', style: TextStyle(fontSize: 10, color: cs.sub)),
                    const SizedBox(width: 8),
                    Icon(Icons.mode_comment_outlined, size: 12, color: cs.sub),
                    const SizedBox(width: 2),
                    Text('$comments', style: TextStyle(fontSize: 10, color: cs.sub)),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMonthlyStats() {
    final cs = _C(context);
    final tc = teamColor(widget.team['short_name'] as String? ?? '');
    if (_monthlyLoading) return Center(child: CircularProgressIndicator(color: tc, strokeWidth: 2.5));
    if (_monthlyStats.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('월별 성적이 없습니다', style: TextStyle(color: cs.sub)),
        const SizedBox(height: 12),
        TextButton.icon(icon: const Icon(Icons.refresh, size: 16), label: const Text('새로고침'),
          onPressed: () { setState(() => _monthlyStats = []); _loadMonthlyStats(); }),
      ]));
    }
    const monthNames = {3: '3월', 4: '4월', 5: '5월', 6: '6월', 7: '7월', 8: '8월', 9: '9월', 10: '10월'};
    final ms = _monthlyStats.cast<Map>();
    final totalW = ms.fold<int>(0, (s, m) => s + ((m['wins'] as num?)?.toInt() ?? 0));
    final totalL = ms.fold<int>(0, (s, m) => s + ((m['losses'] as num?)?.toInt() ?? 0));
    final maxG = ms.map((m) => ((m['wins'] as num?)?.toInt() ?? 0) + ((m['losses'] as num?)?.toInt() ?? 0))
        .fold<int>(1, (a, b) => b > a ? b : a);
    final seasonAvg = ((_seasonStats?['batting'] as Map?)?['avg'] as num?)?.toStringAsFixed(3);

    return ListView(padding: const EdgeInsets.all(18), children: [
      // 요약칩
      Row(children: [
        _SummaryChip(value: '$totalW승', color: const Color(0xFF2563EB), cs: cs),
        const SizedBox(width: 8),
        _SummaryChip(value: '$totalL패', color: SemColor.live, cs: cs),
        const SizedBox(width: 8),
        _SummaryChip(value: seasonAvg ?? '-', color: tc, cs: cs, label: '시즌 타율'),
      ]),
      const SizedBox(height: 14),
      // 막대 차트
      Container(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
        decoration: BoxDecoration(color: cs.paper, border: Border.all(color: cs.line), borderRadius: BorderRadius.circular(Radii.lg)),
        child: Column(children: [
          Text('월별 승/패', style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub, letterSpacing: 0.8)),
          const SizedBox(height: 14),
          SizedBox(height: 120, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: ms.map((m) {
            final w = (m['wins'] as num?)?.toInt() ?? 0;
            final l = (m['losses'] as num?)?.toInt() ?? 0;
            final total = w + l;
            final pct = total > 0 ? (w / total * 100).round() : 0;
            final mn = monthNames[(m['month'] as num?)?.toInt()] ?? '${m['month']}월';
            return Expanded(child: Column(children: [
              Text('$pct%', style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: pct >= 50 ? tc : const Color(0xFF8A8A93))),
              const SizedBox(height: 4),
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (w > 0) Container(height: w / maxG * 74, margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(color: tc.withValues(alpha: cs.dark ? 0.8 : 0.9), borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                  child: Center(child: Text('$w', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)))),
                if (l > 0) Container(height: l / maxG * 74, margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(color: const Color(0xFF9A9AA3), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4))),
                  child: Center(child: Text('$l', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)))),
              ])),
              const SizedBox(height: 6),
              Text(mn, style: TextStyle(fontSize: 11, fontWeight: Typo.bold, color: cs.ink)),
            ]));
          }).toList())),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _LegendDot(color: tc, label: '승'),
            const SizedBox(width: 14),
            _LegendDot(color: const Color(0xFF9A9AA3), label: '패'),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      // 월별 테이블 (월/승/패/승률)
      Container(
        decoration: BoxDecoration(color: cs.paper, border: Border.all(color: cs.line), borderRadius: BorderRadius.circular(Radii.lg)),
        child: Column(children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: ['월', '승', '패', '승률'].asMap().entries.map((e) => Expanded(
              child: Text(e.value, textAlign: e.key == 0 ? TextAlign.left : TextAlign.center,
                  style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub)))).toList())),
          Divider(height: 1, color: cs.line),
          ...ms.asMap().entries.map((e) {
            final m = e.value;
            final last = e.key == ms.length - 1;
            final mn = monthNames[(m['month'] as num?)?.toInt()] ?? '${m['month']}월';
            final wr = (m['win_rate'] as num?)?.toDouble() ?? 0;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
              child: Row(children: [
                Expanded(child: Text(mn, style: TextStyle(fontSize: 12, fontWeight: Typo.bold, color: cs.ink))),
                Expanded(child: Text('${(m['wins'] as num?)?.toInt() ?? 0}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)))),
                Expanded(child: Text('${(m['losses'] as num?)?.toInt() ?? 0}', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SemColor.live))),
                Expanded(child: Text(wr.toStringAsFixed(3), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.ink3))),
              ]),
            );
          }),
        ]),
      ),
    ]);
  }

  void _openUrl(String url) async {
    if (url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) { debugPrint('team_detail: $e'); }
  }

  Widget _buildHeadToHead() {
    final cs = _C(context);
    final tc = teamColor(widget.team['short_name'] as String? ?? '');
    if (_h2hLoading) return Center(child: CircularProgressIndicator(color: tc, strokeWidth: 2.5));
    if (_h2hRecords.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('상대 전적 데이터가 없습니다', style: TextStyle(color: cs.sub)),
        const SizedBox(height: 12),
        TextButton.icon(onPressed: _loadH2H, icon: const Icon(Icons.refresh, size: 16), label: const Text('다시 시도')),
      ]));
    }
    final h2h = _h2hRecords.cast<Map>();
    final totalW = h2h.fold<int>(0, (s, r) => s + ((r['wins'] as num?)?.toInt() ?? 0));
    final totalL = h2h.fold<int>(0, (s, r) => s + ((r['losses'] as num?)?.toInt() ?? 0));
    final totalG = totalW + totalL;
    final overallPct = totalG > 0 ? (totalW / totalG * 100).round() : 0;

    return ListView(padding: const EdgeInsets.all(18), children: [
      // 전체 요약 (원형 게이지)
      Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: cs.paper, border: Border.all(color: cs.line), borderRadius: BorderRadius.circular(Radii.lg)),
        child: Row(children: [
          SizedBox(width: 64, height: 64, child: Stack(children: [
            CustomPaint(size: const Size(64, 64), painter: _RingPainter(pct: overallPct / 100, color: tc, bg: cs.paper2)),
            Center(child: Text('$overallPct%', style: TextStyle(fontSize: 14, fontWeight: Typo.extra, color: tc))),
          ])),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('상대 전적 종합', style: TextStyle(fontSize: 16, fontWeight: Typo.extra, color: cs.ink)),
            const SizedBox(height: 5),
            Row(children: [
              Text('$totalW승', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF2563EB))),
              const SizedBox(width: 10),
              Text('$totalL패', style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: SemColor.live)),
              const SizedBox(width: 8),
              Text('($totalG경기)', style: TextStyle(fontSize: 11, color: cs.sub)),
            ]),
          ]),
        ]),
      ),
      // 2열 그리드
      GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.5,
        children: h2h.map((h) {
          final w = (h['wins'] as num?)?.toInt() ?? 0;
          final l = (h['losses'] as num?)?.toInt() ?? 0;
          final g = (h['total'] as num?)?.toInt() ?? (w + l);
          final pct = g > 0 ? (w / g * 100).round() : 0;
          final isWinning = w >= l;
          final oppCode = h['opp_code'] as String? ?? '';
          final oppName = h['opp_name'] as String? ?? '';
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cs.paper,
                border: Border.all(color: isWinning ? tc.withValues(alpha: 0.3) : cs.line),
                borderRadius: BorderRadius.circular(Radii.lg)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                TeamLogo(teamCode: oppCode, size: 28),
                const SizedBox(width: 7),
                Flexible(child: Text(oppName, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: cs.ink))),
              ]),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text('$w', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF2563EB))),
                Text('승', style: TextStyle(fontSize: 11, color: cs.sub)),
                const SizedBox(width: 6),
                Text('$l', style: TextStyle(fontSize: 20, fontWeight: Typo.extra, color: SemColor.live)),
                Text('패', style: TextStyle(fontSize: 11, color: cs.sub)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(
                value: pct / 100, minHeight: 5, backgroundColor: cs.paper2,
                valueColor: AlwaysStoppedAnimation<Color>(isWinning ? tc : SemColor.live))),
              const SizedBox(height: 4),
              Text('$pct%', style: TextStyle(fontSize: 11, fontWeight: Typo.bold, color: isWinning ? tc : SemColor.live)),
            ]),
          );
        }).toList(),
      ),
    ]);
  }

  // ── 타순별 (Option A) ──
  Widget _buildBattingOrder() {
    final cs = _C(context);
    final tc = teamColor(widget.team['short_name'] as String? ?? '');
    if (_battingOrderLoading) return Center(child: CircularProgressIndicator(color: tc, strokeWidth: 2.5));
    if (_battingOrderStats.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('타순별 성적 데이터가 없습니다', style: TextStyle(color: cs.sub)),
        const SizedBox(height: 12),
        TextButton.icon(onPressed: _loadBattingOrder, icon: const Icon(Icons.refresh, size: 16), label: const Text('다시 시도')),
      ]));
    }
    final stats = _battingOrderStats.cast<Map>();
    final avgs = stats.map((s) => (s['avg'] as num?)?.toDouble() ?? 0).toList();
    final maxAvg = avgs.fold<double>(0.001, (a, b) => b > a ? b : a);
    final minAvg = avgs.fold<double>(1.0, (a, b) => b < a ? b : a);
    String fmt3(double v) => v.toStringAsFixed(3).replaceFirst('0.', '.');

    return ListView(padding: const EdgeInsets.all(18), children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text('2026 시즌 타순별 누적 성적',
            style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub, letterSpacing: 0.8)),
      ),
      // 타순 리스트 카드
      Container(
        decoration: BoxDecoration(color: cs.paper, border: Border.all(color: cs.line), borderRadius: BorderRadius.circular(Radii.lg)),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: Row(children: [
              const SizedBox(width: 32),
              Expanded(flex: 4, child: Text('주요 타자', style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub))),
              Expanded(flex: 2, child: Text('타율', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub))),
              Expanded(flex: 2, child: Text('출루율', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub))),
              Expanded(flex: 2, child: Text('HR', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub))),
              Expanded(flex: 2, child: Text('타점', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub))),
            ]),
          ),
          Divider(height: 1, color: cs.line),
          ...stats.asMap().entries.map((e) {
            final s = e.value;
            final last = e.key == stats.length - 1;
            final order = (s['batting_order'] as num?)?.toInt() ?? 0;
            final avg = (s['avg'] as num?)?.toDouble() ?? 0;
            final obp = (s['obp'] as num?)?.toDouble() ?? 0;
            final hr = (s['home_runs'] as num?)?.toInt() ?? 0;
            final rbi = (s['rbis'] as num?)?.toInt() ?? 0;
            final topName = s['top_player'] as String? ?? '-';
            final topId = s['top_player_id'] as int?;
            final topImg = s['top_player_image'] as String?;
            final t = maxAvg > minAvg ? (avg - minAvg) / (maxAvg - minAvg) : 0.5;
            final rowBg = Color.lerp(Colors.transparent, tc.withValues(alpha: cs.dark ? 0.16 : 0.10), t);
            return GestureDetector(
              onTap: topId != null
                  ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: topId)))
                  : null,
              child: Container(
                decoration: BoxDecoration(color: rowBg, border: last ? null : Border(bottom: BorderSide(color: cs.line))),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Container(width: 26, height: 26,
                    decoration: BoxDecoration(color: tc, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text('$order', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white))),
                  const SizedBox(width: 6),
                  Expanded(flex: 4, child: Row(children: [
                    CircleAvatar(radius: 11, backgroundColor: tc.withValues(alpha: 0.15),
                      backgroundImage: (topImg != null && topImg.isNotEmpty) ? CachedNetworkImageProvider(topImg) : null,
                      child: (topImg == null || topImg.isEmpty) ? Icon(Icons.person, size: 13, color: tc) : null),
                    const SizedBox(width: 5),
                    Expanded(child: Text(topName, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: Typo.medium, color: cs.ink))),
                  ])),
                  Expanded(flex: 2, child: Text(fmt3(avg), textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 12, fontWeight: Typo.bold,
                          color: avg >= 0.300 ? const Color(0xFF2563EB) : avg < 0.230 ? SemColor.live : cs.ink))),
                  Expanded(flex: 2, child: Text(fmt3(obp), textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: cs.ink3))),
                  Expanded(flex: 2, child: Text('$hr', textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 12, color: hr >= 5 ? const Color(0xFF9333EA) : cs.ink3))),
                  Expanded(flex: 2, child: Text('$rbi', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: cs.ink3))),
                ]),
              ),
            );
          }),
        ]),
      ),
      const SizedBox(height: 14),
      // 타순별 타율 막대 차트
      Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(color: cs.paper, border: Border.all(color: cs.line), borderRadius: BorderRadius.circular(Radii.lg)),
        child: Column(children: [
          Text('타순별 타율', style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub, letterSpacing: 0.8)),
          const SizedBox(height: 14),
          SizedBox(height: 116, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: stats.map((s) {
            final order = (s['batting_order'] as num?)?.toInt() ?? 0;
            final avg = (s['avg'] as num?)?.toDouble() ?? 0;
            return Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(fmt3(avg), style: TextStyle(fontSize: 9, color: cs.sub)),
              const SizedBox(height: 3),
              Container(height: maxAvg > 0 ? avg / maxAvg * 80 : 0.0, margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(color: tc.withValues(alpha: cs.dark ? 0.75 : 0.8), borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))),
              const SizedBox(height: 5),
              Text('$order', style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.ink)),
            ]));
          }).toList())),
        ]),
      ),
    ]);
  }

}

// PageView 탭 상태 보존 (IndexedStack 대체)
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// ── 선수 탭 2열: 번호칩 ──
class _NumChip extends StatelessWidget {
  final int? no;
  final Color tc;
  final _C cs;
  const _NumChip({required this.no, required this.tc, required this.cs});
  @override
  Widget build(BuildContext context) => Container(
    width: 30, height: 30,
    decoration: BoxDecoration(
      color: tc.withValues(alpha: cs.dark ? 0.18 : 0.08),
      border: Border.all(color: tc.withValues(alpha: 0.2)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Center(child: Text('#${no ?? '-'}',
        style: TextStyle(fontSize: 10, fontWeight: Typo.extra, color: tc))),
  );
}

// ── 선수 탭 2열: 컬럼 헤더 (제목 + 필터칩) ──
class _ColumnHeader extends StatelessWidget {
  final String title, selected;
  final List<String> filters;
  final Color tc;
  final _C cs;
  final ValueChanged<String> onSelect;
  const _ColumnHeader({required this.title, required this.filters, required this.selected,
      required this.tc, required this.cs, required this.onSelect});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.line))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 13, fontWeight: Typo.extra, color: cs.ink)),
      const SizedBox(height: 8),
      Wrap(spacing: 4, runSpacing: 4, children: filters.map((f) => GestureDetector(
        onTap: () => onSelect(f),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: f == selected ? tc : cs.paper2,
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(color: f == selected ? tc : cs.line),
          ),
          child: Text(f, style: TextStyle(fontSize: 10,
              fontWeight: f == selected ? Typo.bold : Typo.medium,
              color: f == selected ? (cs.dark ? const Color(0xFF0F0F12) : Colors.white) : cs.ink3)),
        ),
      )).toList()),
    ]),
  );
}

// ── 상대전적 원형 게이지 ──
class _RingPainter extends CustomPainter {
  final double pct;
  final Color color, bg;
  const _RingPainter({required this.pct, required this.color, required this.bg});
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2, r = cx - 4;
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 7..strokeCap = StrokeCap.round;
    paint.color = bg;
    canvas.drawCircle(Offset(cx, cy), r, paint);
    paint.color = color;
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r),
        -1.5707963267948966, pct * 6.283185307179586, false, paint);
  }
  @override
  bool shouldRepaint(covariant _RingPainter old) => old.pct != pct || old.color != color;
}

// ── 월별 요약칩 ──
class _SummaryChip extends StatelessWidget {
  final String value;
  final Color color;
  final _C cs;
  final String? label;
  const _SummaryChip({required this.value, required this.color, required this.cs, this.label});
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(color: cs.paper, border: Border.all(color: cs.line),
        borderRadius: BorderRadius.circular(Radii.md)),
    child: Column(children: [
      Text(value, style: TextStyle(fontSize: 15, fontWeight: Typo.extra, color: color)),
      if (label != null) ...[
        const SizedBox(height: 4),
        Text(label!, style: TextStyle(fontSize: 10, color: cs.sub)),
      ],
    ]),
  ));
}

// ── 차트 범례 점 ──
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 5),
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
  ]);
}

// ── 팀컬러 헤더용 흰색 32px 버튼 (Option A) ──
class _WhiteBtn32 extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _WhiteBtn32({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Icon(icon, size: 18, color: Colors.white),
    ),
  );
}

// ── Option A 공통 소형 위젯 ──────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  final _C cs;
  const _SectionLabel({required this.label, required this.cs});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub, letterSpacing: 0.8)),
  );
}

class _CardWrap extends StatelessWidget {
  final Widget child;
  final _C cs;
  const _CardWrap({required this.child, required this.cs});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18),
    child: Container(
      decoration: BoxDecoration(
        color: cs.paper, border: Border.all(color: cs.line),
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: cs.dark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 2, offset: const Offset(0, 1))],
      ),
      child: child,
    ),
  );
}

class _StatBlock extends StatelessWidget {
  final String label, value;
  final _C cs;
  const _StatBlock({required this.label, required this.value, required this.cs});
  @override
  Widget build(BuildContext context) => Expanded(child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(children: [
      Text(value, style: TextStyle(fontSize: 13, fontWeight: Typo.extra, color: cs.ink)),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 9, color: cs.sub)),
    ]),
  ));
}

class _SmallChip extends StatelessWidget {
  final String label;
  final Color color, bg;
  final Color? border;
  const _SmallChip({required this.label, required this.color, required this.bg, this.border});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg, borderRadius: BorderRadius.circular(Radii.xs),
      border: border != null ? Border.all(color: border!) : null,
    ),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: color)),
  );
}

// ── 색상 헬퍼 ─────────────────────────────────────────────────────────────────
class _C {
  final Color bg, paper, paper2, ink, ink2, ink3, sub, line, line2, track;
  final bool dark;
  _C(BuildContext ctx)
    : dark   = Theme.of(ctx).brightness == Brightness.dark,
      bg     = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF0F0F12) : const Color(0xFFFAFAFB),
      paper  = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF18181C) : Colors.white,
      paper2 = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6),
      ink    = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFFF4F4F5) : const Color(0xFF111113),
      ink2   = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFFC9C9D1) : const Color(0xFF3F3F46),
      ink3   = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73),
      sub    = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2),
      line   = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0),
      line2  = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF33333A) : const Color(0xFFE0E0E4),
      track  = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF2C2C33) : const Color(0xFFE8E8EC);
}
