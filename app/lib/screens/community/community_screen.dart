// community_screen.dart — Option A 디자인 시스템 반영
import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import '../../utils/web_image.dart';
import '../../utils/web_safe_area.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api/api_service.dart';
import '../../utils/local_cache.dart';
import '../../utils/team_theme.dart';
import '../mypage/my_page_screen.dart';
import '../../widgets/stadium_ranking_sheet.dart';
import 'post_detail_screen.dart';
import 'create_post_screen.dart';
import 'food_add_screen.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';

const _categories = ['전체', '자유', '분석', '유머'];

const _kTeams = [
  (id: 9,  code: 'LG', name: 'LG'),
  (id: 1,  code: 'KT', name: 'KT'),
  (id: 10, code: 'SK', name: 'SSG'),
  (id: 6,  code: 'NC', name: 'NC'),
  (id: 7,  code: 'OB', name: '두산'),
  (id: 2,  code: 'HT', name: 'KIA'),
  (id: 4,  code: 'LT', name: '롯데'),
  (id: 11, code: 'SS', name: '삼성'),
  (id: 5,  code: 'HH', name: '한화'),
  (id: 8,  code: 'WO', name: '키움'),
];

// 게시글 team_id → 팀컬러 코드
const _kTeamIdToCode = {
  1: 'KT', 2: 'HT', 4: 'LT', 5: 'HH', 6: 'NC',
  7: 'OB', 8: 'WO', 9: 'LG', 10: 'SK', 11: 'SS',
};

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _latestKey = GlobalKey<_PostListTabState>();
  final _foodKey = GlobalKey<_FoodTabState>();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = _C(context);
    return Scaffold(
      backgroundColor: cs.bg,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          bottom: (ApiService.myTeamData.value.isNotEmpty ? 142.0 : 90.0) + MediaQuery.of(context).viewPadding.bottom,
        ),
        child: FloatingActionButton(
          // 맛집 탭(3) = 맛집 제안, 그 외 = 글 작성 — 4탭 동일 위치/형태
          onPressed: () async {
            if (_tabCtrl.index == 3) {
              _foodKey.currentState?._openSubmit();
              return;
            }
            final created = await Navigator.push<bool>(context,
                MaterialPageRoute(builder: (_) => const CreatePostScreen()));
            if (created == true) _latestKey.currentState?._load();
          },
          backgroundColor: cs.ink,
          foregroundColor: cs.dark ? const Color(0xFF0F0F12) : Colors.white,
          child: Icon(_tabCtrl.index == 3 ? Icons.add : Icons.edit_outlined,
              color: cs.dark ? const Color(0xFF0F0F12) : Colors.white),
        ),
      ),
      body: Column(children: [
          // AppBar — 상태바 영역까지 paper (SafeArea 단차 방지, 06-13)
          Container(
            color: cs.paper,
            padding: EdgeInsets.only(top: MediaQuery.of(context).viewPadding.top),
            child: Column(children: [
              Padding(
                // bottom 13→4: 탭바 위 여백 과다 (06-13)
                padding: EdgeInsets.fromLTRB(18, headerTopGap(context), 18, 4),
                child: Row(children: [
                  Text('커뮤니티', style: TextStyle(fontSize: Typo.h2, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.5)),
                  const Spacer(),
                  Tooltip(
                    message: '직관승률 랭킹',
                    child: _Btn32(border: cs.line2,
                      onTap: () => StadiumRankingSheet.show(context),
                      child: Icon(Icons.emoji_events_outlined, size: 18, color: cs.ink3)),
                  ),
                  const SizedBox(width: 7),
                  Tooltip(
                    message: cs.dark ? '라이트 모드' : '다크 모드',
                    child: _Btn32(border: cs.line2,
                      onTap: () => context.read<ThemeProvider>().toggle(),
                      child: Icon(cs.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                          size: 18, color: cs.ink3)),
                  ),
                  const SizedBox(width: 7),
                  Tooltip(
                    message: '마이페이지',
                    child: _Btn32(border: cs.line2,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyPageScreen())),
                      child: Icon(Icons.person_outline, size: 18, color: cs.ink3)),
                  ),
                ]),
              ),
              TabBar(
                controller: _tabCtrl,
                labelColor: cs.ink,
                unselectedLabelColor: cs.sub,
                indicatorColor: cs.ink,
                indicatorWeight: 2,
                dividerColor: cs.line,
                labelStyle: const TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra),
                unselectedLabelStyle: const TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.medium),
                tabs: const [Tab(text: '전체'), Tab(text: '팀별'), Tab(text: '인기'), Tab(text: '맛집')],
              ),
            ]),
          ),
          // Content
          Expanded(child: TabBarView(
            controller: _tabCtrl,
            children: [
              _PostListTab(key: _latestKey, sort: 'latest'),
              const _TeamTab(),
              const _PostListTab(sort: 'hot'),
              _FoodTab(key: _foodKey),
            ],
          )),
        ]),
    );
  }
}

// ===== 전체/인기 탭 =====

class _PostListTab extends StatefulWidget {
  final String sort;
  final int? teamId;
  const _PostListTab({super.key, required this.sort, this.teamId});

  @override
  State<_PostListTab> createState() => _PostListTabState();
}

class _PostListTabState extends State<_PostListTab>
    with AutomaticKeepAliveClientMixin {
  List _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String _category = '전체';
  String _searchQ = '';
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200
        && !_loadingMore && _hasMore) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    final cacheKey = 'community_posts_${widget.sort}_${widget.teamId ?? 'all'}';
    final canCache = _category == '전체' && _searchQ.isEmpty;

    setState(() { _page = 1; _hasMore = true; });

    if (canCache) {
      final cached = await LocalCache.get(cacheKey, maxAgeSeconds: 300);
      if (cached != null && mounted) {
        final cachedPosts = (cached['posts'] as List?) ?? [];
        setState(() {
          _posts = cachedPosts;
          _hasMore = cachedPosts.length >= 20;
          _loading = false;
        });
      } else if (mounted && _posts.isEmpty) {
        setState(() => _loading = true);
      }
    } else if (_posts.isEmpty) {
      setState(() => _loading = true);
    }

    try {
      final data = await ApiService.getPosts(
        sort: widget.sort,
        teamId: widget.teamId,
        category: _category == '전체' ? null : _category,
        q: _searchQ.isEmpty ? null : _searchQ,
        page: 1,
      );
      if (mounted) {
        final posts = data['posts'] as List? ?? [];
        if (canCache) await LocalCache.set(cacheKey, {'posts': posts});
        if (mounted) {
          setState(() {
          _posts = posts;
          _hasMore = posts.length >= 20;
          _loading = false;
        });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final data = await ApiService.getPosts(
        sort: widget.sort,
        teamId: widget.teamId,
        category: _category == '전체' ? null : _category,
        q: _searchQ.isEmpty ? null : _searchQ,
        page: _page + 1,
      );
      if (mounted) {
        final more = data['posts'] as List? ?? [];
        setState(() {
          // #22 memory cap — 200개 초과 시 oldest 제거 (스크롤 위치는 유지, 새 페이지 표시)
          var combined = [..._posts, ...more];
          if (combined.length > 200) {
            combined = combined.sublist(combined.length - 200);
          }
          _posts = combined;
          _page++;
          _hasMore = more.length >= 20;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = _C(context);
    return Column(
      children: [
        // 검색바
        Container(
          margin: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: cs.paper2, border: Border.all(color: cs.line),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(children: [
            Icon(Icons.search, size: 16, color: cs.sub),
            const SizedBox(width: 9),
            Expanded(child: TextField(
              controller: _searchCtrl,
              style: TextStyle(fontSize: 13, color: cs.ink),
              cursorColor: cs.ink,
              decoration: InputDecoration(
                hintText: '게시글 검색',
                hintStyle: TextStyle(fontSize: 13, color: cs.sub),
                border: InputBorder.none, isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onSubmitted: (v) { setState(() => _searchQ = v.trim()); _load(); },
            )),
            if (_searchQ.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchCtrl.clear();
                  setState(() => _searchQ = '');
                  _load();
                },
                child: Icon(Icons.close, size: 16, color: cs.sub),
              ),
          ]),
        ),
        // 카테고리 칩
        SizedBox(
          height: 44,
          child: _fade(ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
            itemCount: _categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final act = _categories[i] == _category;
              return GestureDetector(
                onTap: () {
                  setState(() => _category = _categories[i]);
                  _load();
                },
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: act ? cs.ink : cs.paper,
                    borderRadius: BorderRadius.circular(Radii.pill),
                    border: Border.all(color: act ? cs.ink : cs.line2),
                  ),
                  child: Text(_categories[i], style: TextStyle(fontSize: 12,
                      fontWeight: act ? Typo.bold : Typo.medium,
                      color: act ? (cs.dark ? const Color(0xFF0F0F12) : Colors.white) : cs.ink3)),
                ),
              );
            },
          )),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _posts.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 80),
                          Center(child: Text('게시글이 없습니다', style: TextStyle(fontSize: Typo.body, color: cs.sub))),
                        ])
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: _posts.length + (_loadingMore || (!_hasMore && _posts.isNotEmpty) ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == _posts.length) {
                              if (_loadingMore) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                );
                              }
                              // 끝 표시
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: Text('— 마지막 글입니다 —',
                                      style: TextStyle(fontSize: 12, color: cs.sub)),
                                ),
                              );
                            }
                            return _PostCard(post: _posts[i], cs: cs, onRefresh: _load);
                          },
                        ),
                ),
        ),
      ],
    );
  }
}

// ===== 팀별 탭 =====

class _TeamTab extends StatefulWidget {
  const _TeamTab();

  @override
  State<_TeamTab> createState() => _TeamTabState();
}

class _TeamTabState extends State<_TeamTab> {
  int _selectedTeamId = 9; // LG 기본

  @override
  Widget build(BuildContext context) {
    final cs = _C(context);
    return Column(
      children: [
        // 팀 칩 스크롤
        Container(
          height: 50,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.line))),
          child: _fade(ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            itemCount: _kTeams.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final t = _kTeams[i];
              final active = _selectedTeamId == t.id;
              final c = teamColor(t.code);
              return GestureDetector(
                onTap: () => setState(() => _selectedTeamId = t.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: active ? c.withValues(alpha: cs.dark ? 0.22 : 0.1) : cs.paper2,
                    borderRadius: BorderRadius.circular(Radii.pill),
                    border: Border.all(color: active ? c.withValues(alpha: 0.4) : cs.line),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    TeamLogo(teamCode: t.code, size: 14),
                    const SizedBox(width: 5),
                    Text(t.name, style: TextStyle(fontSize: 11,
                        fontWeight: active ? Typo.bold : Typo.medium,
                        color: active ? c : cs.ink2)),
                  ]),
                ),
              );
            },
          )),
        ),
        Expanded(
          child: _PostListTab(key: ValueKey(_selectedTeamId), sort: 'latest', teamId: _selectedTeamId),
        ),
      ],
    );
  }
}

// ===== 게시글 카드 =====

class _PostCard extends StatelessWidget {
  final Map post;
  final _C cs;
  final VoidCallback onRefresh;
  const _PostCard({required this.post, required this.cs, required this.onRefresh});

  Widget _meta(IconData icon, dynamic value) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 12, color: cs.sub),
    const SizedBox(width: 3),
    Text('${value ?? 0}', style: TextStyle(fontSize: 10, color: cs.sub)),
  ]);

  Widget _bottomRow() => Row(children: [
    Text(post['author'] as String? ?? '', style: TextStyle(fontSize: 10, color: cs.sub)),
    const Spacer(),
    _meta(Icons.favorite_border, post['likes']),
    const SizedBox(width: 10),
    _meta(Icons.chat_bubble_outline, post['comment_count']),
    const SizedBox(width: 10),
    _meta(Icons.visibility_outlined, post['views']),
  ]);

  Widget _tags(BuildContext context) {
    final teamName = post['team_name'] as String?;
    final teamCode = _kTeamIdToCode[post['team_id'] as int?];
    final tc = teamCode != null ? teamColor(teamCode) : SemColor.brand(context);
    return Wrap(spacing: 5, runSpacing: 5, children: [
      if (teamName != null) _Tag(label: teamName, color: tc, cs: cs),
      _Tag(label: post['category'] as String? ?? '', color: cs.ink3, cs: cs, muted: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = post['image_url'] as String?;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final content = post['content'] as String?;

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 8, 18, 0),
      decoration: BoxDecoration(
        color: cs.paper, border: Border.all(color: cs.line),
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: cs.dark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 2, offset: const Offset(0, 1))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.lg),
          onTap: () async {
            await Navigator.push(context,
                MaterialPageRoute(builder: (_) => PostDetailScreen(postId: post['id'])));
            onRefresh();
          },
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (hasImage)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.lg)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: netImage(
                    imageUrl,
                    fit: BoxFit.cover,
                    error: () => Container(
                      color: cs.paper2,
                      child: Icon(Icons.broken_image, color: cs.sub),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(13),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _tags(context),
                const SizedBox(height: 7),
                Text(post['title'] as String? ?? '',
                    style: TextStyle(fontSize: Typo.body, fontWeight: Typo.bold, color: cs.ink, height: 1.45),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                if (!hasImage && content != null && content.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(content,
                      style: TextStyle(fontSize: 12, color: cs.ink3),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 9),
                _bottomRow(),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  final _C cs;
  final bool muted;
  const _Tag({required this.label, required this.color, required this.cs, this.muted = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: muted ? cs.paper2 : color.withValues(alpha: cs.dark ? 0.22 : 0.1),
      borderRadius: BorderRadius.circular(Radii.xs),
      border: muted ? Border.all(color: cs.line) : null,
    ),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: Typo.bold,
        color: muted ? cs.ink3 : color)),
  );
}

// ===== 맛집 탭 =====

const _stadiums = [
  (id: 1, name: '잠실'),
  (id: 2, name: '고척'),
  (id: 3, name: '수원'),
  (id: 4, name: '인천'),
  (id: 5, name: '대전'),
  (id: 6, name: '광주'),
  (id: 7, name: '대구'),
  (id: 8, name: '창원'),
  (id: 9, name: '사직'),
];

class _FoodTab extends StatefulWidget {
  const _FoodTab({super.key});

  @override
  State<_FoodTab> createState() => _FoodTabState();
}

class _FoodTabState extends State<_FoodTab> with AutomaticKeepAliveClientMixin {
  int _stadiumId = 1;
  List _places = [];
  bool _loading = true;
  final Set<int> _myVotes = {};

  @override
  bool get wantKeepAlive => false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final data = await ApiService.getCommunityFood(_stadiumId);
      if (mounted) setState(() { _places = data['places'] ?? []; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _vote(int placeId) async {
    try {
      final res = await ApiService.voteFoodPlace(placeId);
      final voted = res['voted'] as bool;
      setState(() {
        if (voted) { _myVotes.add(placeId); } else { _myVotes.remove(placeId); }
        final idx = _places.indexWhere((p) => p['id'] == placeId);
        if (idx >= 0) {
          final cur = (_places[idx]['upvote_count'] as int? ?? 0);
          _places[idx] = Map.from(_places[idx])..['upvote_count'] = voted ? cur + 1 : cur - 1;
        }
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인이 필요합니다')),
        );
      }
    }
  }

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openSubmit() async {
    final submitted = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => FoodAddScreen(initialStadiumId: _stadiumId)));
    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제안이 등록되었습니다. 팬 5명의 추천을 받으면 목록에 표시됩니다.')),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = _C(context);
    final navBottom = (ApiService.myTeamData.value.isNotEmpty ? 142.0 : 90.0)
        + MediaQuery.of(context).viewPadding.bottom + 56;

    return Column(
      children: [
        // 구장 칩
        Container(
          height: 50,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.line))),
          child: _fade(ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            itemCount: _stadiums.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final s = _stadiums[i];
              final act = s.id == _stadiumId;
              return GestureDetector(
                onTap: () {
                  setState(() { _stadiumId = s.id; _places = []; });
                  _load();
                },
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: act ? cs.ink : cs.paper2,
                    borderRadius: BorderRadius.circular(Radii.pill),
                    border: Border.all(color: act ? cs.ink : cs.line),
                  ),
                  child: Text(s.name, style: TextStyle(fontSize: 12,
                      fontWeight: act ? Typo.bold : Typo.medium,
                      color: act ? (cs.dark ? const Color(0xFF0F0F12) : Colors.white) : cs.ink3)),
                ),
              );
            },
          )),
        ),
        // 목록
        Expanded(
          child: Stack(
            children: [
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_places.isEmpty)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.restaurant_menu, size: 48, color: cs.line2),
                      const SizedBox(height: 12),
                      Text('아직 팬 추천 맛집이 없습니다\n첫 번째로 추천해보세요!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.sub, fontSize: 13)),
                    ],
                  ),
                )
              else
                ListView.builder(
                  padding: EdgeInsets.only(bottom: navBottom),
                  itemCount: _places.length,
                  itemBuilder: (_, i) {
                    final p = _places[i];
                    final isApproved = p['status'] == 'approved';
                    final votes = p['upvote_count'] as int? ?? 0;
                    final voted = _myVotes.contains(p['id'] as int);
                    return _FoodTile(
                      place: p,
                      cs: cs,
                      approved: isApproved,
                      votes: votes,
                      voted: voted,
                      onVote: () => _vote(p['id'] as int),
                      onTap: () => _openUrl(p['url'] as String? ?? ''),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FoodTile extends StatelessWidget {
  final Map place;
  final _C cs;
  final bool approved, voted;
  final int votes;
  final VoidCallback onVote, onTap;
  const _FoodTile({
    required this.place, required this.cs, required this.approved,
    required this.votes, required this.voted, required this.onVote, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final memo = place['memo'] as String? ?? '';
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: approved ? SemColor.live.withValues(alpha: 0.1) : cs.paper2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: approved ? SemColor.live.withValues(alpha: 0.25) : cs.line),
            ),
            child: Icon(
              approved ? Icons.verified : Icons.restaurant,
              size: 17, color: approved ? SemColor.live : cs.sub,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(place['name'] as String? ?? '',
                  style: TextStyle(fontSize: Typo.body, fontWeight: Typo.bold, color: cs.ink),
                  overflow: TextOverflow.ellipsis)),
              if (approved) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: SemColor.live.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Radii.xs)),
                  child: const Text('인증', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: SemColor.live)),
                ),
              ],
            ]),
            const SizedBox(height: 3),
            Text('${place['category'] ?? ''} · ${place['submitted_by'] ?? ''} 추천',
                style: TextStyle(fontSize: Typo.caption, color: cs.ink3)),
            if (memo.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text('"$memo"', style: TextStyle(fontSize: Typo.caption, color: cs.sub, fontStyle: FontStyle.italic, height: 1.4)),
            ],
          ])),
          GestureDetector(
            onTap: onVote,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(children: [
                Icon(voted ? Icons.thumb_up : Icons.thumb_up_outlined,
                    size: 18, color: voted ? SemColor.live : cs.sub),
                const SizedBox(height: 3),
                Text('$votes', style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold,
                    color: voted ? SemColor.live : cs.ink3)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ===== 공통 위젯 =====

// 가로 스크롤 칩 스트립 — 양 끝 그라디언트 페이드
Widget _fade(Widget child) => ShaderMask(
  shaderCallback: (rect) => const LinearGradient(
    begin: Alignment.centerLeft, end: Alignment.centerRight,
    colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
    stops: [0.0, 0.04, 0.96, 1.0],
  ).createShader(rect),
  blendMode: BlendMode.dstIn,
  child: child,
);

class _Btn32 extends StatelessWidget {
  final Widget child;
  final Color border;
  final VoidCallback onTap;
  const _Btn32({required this.child, required this.border, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(border: Border.all(color: border), borderRadius: BorderRadius.circular(10)),
      child: child,
    ),
  );
}

// ── 색상 헬퍼 ─────────────────────────────────────────────────────────────────

class _C {
  final Color bg, paper, paper2, ink, ink2, ink3, sub, line, line2;
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
      line2  = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF33333A) : const Color(0xFFE0E0E4);
}
