import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api/api_service.dart';
import '../../utils/local_cache.dart';
import '../mypage/my_page_screen.dart';
import 'post_detail_screen.dart';
import 'create_post_screen.dart';

const _categories = ['전체', '자유', '분석', '유머'];

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _latestKey = GlobalKey<_PostListTabState>();

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
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        title: const Text('커뮤니티'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: '마이페이지',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyPageScreen())),
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: '전체'),
            Tab(text: '팀별'),
            Tab(text: '인기'),
            Tab(text: '맛집'),
          ],
        ),
      ),
      floatingActionButton: _tabCtrl.index == 3 ? null : Padding(
        padding: EdgeInsets.only(
          bottom: (ApiService.myTeamData.value.isNotEmpty ? 142.0 : 90.0) + MediaQuery.of(context).viewPadding.bottom,
        ),
        child: FloatingActionButton(
          onPressed: () async {
            final created = await Navigator.push<bool>(context,
                MaterialPageRoute(builder: (_) => const CreatePostScreen()));
            if (created == true) _latestKey.currentState?._load();
          },
          backgroundColor: const Color(0xFF111113),
          child: const Icon(Icons.edit, color: Colors.white),
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _PostListTab(key: _latestKey, sort: 'latest'),
          const _TeamTab(),
          const _PostListTab(sort: 'hot'),
          const _FoodTab(),
        ],
      ),
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
        if (mounted) setState(() {
          _posts = posts;
          _hasMore = posts.length >= 20;
          _loading = false;
        });
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
    return Column(
      children: [
        // 검색바
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '검색',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQ.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQ = '');
                        _load();
                      })
                  : null,
            ),
            onSubmitted: (v) { setState(() => _searchQ = v.trim()); _load(); },
          ),
        ),
        // 카테고리 칩
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: _categories.map((c) {
              final selected = _category == c;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(c),
                  selected: selected,
                  selectedColor: const Color(0xFF111113),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : Colors.black87,
                    fontSize: 12,
                  ),
                  onSelected: (_) {
                    setState(() => _category = c);
                    _load();
                  },
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _posts.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 80),
                          Center(child: Text('게시글이 없습니다', style: TextStyle(color: Colors.grey))),
                        ])
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          itemCount: _posts.length + (_loadingMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == _posts.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            }
                            return _PostCard(post: _posts[i], onRefresh: _load);
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
  int? _selectedTeamId;
  List<Map<String, dynamic>> _teams = [];
  bool _teamsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    try {
      final data = await ApiService.getTeams();
      if (mounted) {
        setState(() {
          _teams = List<Map<String, dynamic>>.from(data['teams'] ?? []);
          _teamsLoaded = true;
        });
      }
    } catch (_) {
      setState(() => _teamsLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_teamsLoaded) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        // 팀 선택 가로 스크롤
        SizedBox(
          height: 72,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: _teams.length,
            itemBuilder: (_, i) {
              final t = _teams[i];
              final selected = _selectedTeamId == t['id'];
              return GestureDetector(
                onTap: () => setState(() => _selectedTeamId = t['id']),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF111113) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? const Color(0xFF111113) : Colors.grey[300]!),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(t['name'] ?? '',
                          style: TextStyle(
                              fontSize: 11,
                              color: selected ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: _selectedTeamId == null
              ? const Center(child: Text('팀을 선택하세요', style: TextStyle(color: Colors.grey)))
              : _PostListTab(sort: 'latest', teamId: _selectedTeamId),
        ),
      ],
    );
  }
}

// ===== 게시글 카드 =====

class _PostCard extends StatelessWidget {
  final Map post;
  final VoidCallback onRefresh;
  const _PostCard({required this.post, required this.onRefresh});

  Widget _tagChip(String text, {Color? color}) {
    return Container(
      margin: const EdgeInsets.only(right: 5),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: (color ?? Colors.grey).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 11, color: color ?? Colors.grey[600], fontWeight: FontWeight.w600)),
    );
  }

  Widget _engagementBar() {
    return Row(
      children: [
        Text(post['author'] ?? '',
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const Spacer(),
        const Icon(Icons.favorite_border, size: 13, color: Colors.grey),
        const SizedBox(width: 2),
        Text('${post['likes'] ?? 0}',
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(width: 8),
        const Icon(Icons.chat_bubble_outline, size: 13, color: Colors.grey),
        const SizedBox(width: 2),
        Text('${post['comment_count'] ?? 0}',
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(width: 8),
        const Icon(Icons.remove_red_eye_outlined, size: 13, color: Colors.grey),
        const SizedBox(width: 2),
        Text('${post['views'] ?? 0}',
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = post['image_url'] as String?;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => PostDetailScreen(postId: post['id'])));
          onRefresh();
        },
        child: hasImage
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 이미지 먼저
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(
                        color: Colors.grey[100],
                        child: const Icon(Icons.broken_image, color: Colors.grey),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          if (post['team_name'] != null)
                            _tagChip(post['team_name'], color: const Color(0xFF111113)),
                          _tagChip(post['category'] ?? ''),
                        ]),
                        const SizedBox(height: 6),
                        Text(post['title'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 8),
                        _engagementBar(),
                      ],
                    ),
                  ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      if (post['team_name'] != null)
                        _tagChip(post['team_name'], color: const Color(0xFF111113)),
                      _tagChip(post['category'] ?? ''),
                    ]),
                    const SizedBox(height: 6),
                    Text(post['title'] ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (post['content'] != null && (post['content'] as String).isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(post['content'] ?? '',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 8),
                    _engagementBar(),
                  ],
                ),
              ),
      ),
    );
  }
}

// ===== 맛집 탭 =====

const _stadiums = [
  (id: 1, name: '서울'),
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
  const _FoodTab();

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

  void _showSubmit() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _FoodSubmitSheet(
        stadiumId: _stadiumId,
        onSubmitted: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = const Color(0xFF111113);
    final navBottom = (ApiService.myTeamData.value.isNotEmpty ? 142.0 : 90.0)
        + MediaQuery.of(context).viewPadding.bottom + 56; // FAB 없으므로 nav only

    return Column(
      children: [
        // 구장 선택 칩
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _stadiums.length,
            itemBuilder: (_, i) {
              final s = _stadiums[i];
              final sel = s.id == _stadiumId;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(s.name),
                  selected: sel,
                  onSelected: (_) {
                    setState(() { _stadiumId = s.id; _places = []; });
                    _load();
                  },
                  selectedColor: activeColor,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                    color: sel ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                  ),
                  backgroundColor: isDark ? Colors.white10 : Colors.grey[100],
                  side: BorderSide.none,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              );
            },
          ),
        ),
        Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
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
                      Icon(Icons.restaurant_menu, size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text('아직 팬 추천 맛집이 없습니다\n첫 번째로 추천해보세요!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                    ],
                  ),
                )
              else
                ListView.separated(
                  padding: EdgeInsets.only(bottom: navBottom),
                  itemCount: _places.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: Colors.grey.withValues(alpha: 0.12)),
                  itemBuilder: (_, i) {
                    final p = _places[i];
                    final isApproved = p['status'] == 'approved';
                    final votes = p['upvote_count'] as int? ?? 0;
                    final voted = _myVotes.contains(p['id'] as int);
                    return ListTile(
                      leading: Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          color: isApproved
                              ? activeColor.withValues(alpha: 0.12)
                              : Colors.grey.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isApproved ? Icons.verified : Icons.restaurant,
                          color: isApproved ? activeColor : Colors.grey,
                          size: 18,
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(p['name'] as String? ?? '',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          ),
                          if (isApproved)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: activeColor.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('인증',
                                  style: TextStyle(fontSize: 11, color: activeColor, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${p['category'] ?? ''} · ${p['submitted_by'] ?? ''} 추천',
                              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                          if ((p['memo'] as String? ?? '').isNotEmpty)
                            Text('"${p['memo']}"',
                                style: TextStyle(fontSize: 11, color: Colors.grey[500],
                                    fontStyle: FontStyle.italic)),
                        ],
                      ),
                      isThreeLine: (p['memo'] as String? ?? '').isNotEmpty,
                      trailing: GestureDetector(
                        onTap: () => _vote(p['id'] as int),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(voted ? Icons.thumb_up : Icons.thumb_up_outlined,
                                size: 18, color: voted ? activeColor : Colors.grey),
                            Text('$votes',
                                style: TextStyle(fontSize: 11, color: voted ? activeColor : Colors.grey)),
                          ],
                        ),
                      ),
                      onTap: () => _openUrl(p['url'] as String? ?? ''),
                    );
                  },
                ),
              // 맛집 제안 FAB
              Positioned(
                bottom: 16 + MediaQuery.of(context).viewPadding.bottom,
                right: 16,
                child: FloatingActionButton.extended(
                  heroTag: 'food_fab',
                  onPressed: _showSubmit,
                  backgroundColor: activeColor,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('맛집 제안', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ===== 맛집 제안 시트 =====

class _FoodSubmitSheet extends StatefulWidget {
  final int stadiumId;
  final VoidCallback onSubmitted;

  const _FoodSubmitSheet({required this.stadiumId, required this.onSubmitted});

  @override
  State<_FoodSubmitSheet> createState() => _FoodSubmitSheetState();
}

class _FoodSubmitSheetState extends State<_FoodSubmitSheet> {
  final _searchCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  List _results = [];
  bool _searching = false;
  Map? _selected;
  bool _submitting = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _searching = true; _results = []; _selected = null; });
    try {
      final data = await ApiService.searchFoodPlace(widget.stadiumId, q);
      if (mounted) setState(() { _results = data['places'] ?? []; _searching = false; });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _submit() async {
    if (_selected == null) return;
    setState(() => _submitting = true);
    try {
      await ApiService.submitFoodPlace(widget.stadiumId, {
        'kakao_place_id': _selected!['id'],
        'name': _selected!['name'],
        'category': _selected!['category'],
        'address': _selected!['address'],
        'phone': _selected!['phone'],
        'url': _selected!['url'],
        'memo': _memoCtrl.text.trim(),
      });
      widget.onSubmitted();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('제안이 등록되었습니다. 팬 5명의 추천을 받으면 목록에 표시됩니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        final msg = e.toString().contains('409') ? '이미 등록된 장소입니다' : '제안 실패. 로그인 상태를 확인해주세요';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF111113);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('맛집 제안', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('구장 2km 이내 음식점만 등록 가능합니다',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: '가게 이름 검색',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _searching ? null : _search,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    child: _searching
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('검색'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_selected != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: color, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_selected!['name'] as String,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _memoCtrl,
                  decoration: InputDecoration(
                    hintText: '한줄 추천 이유 (선택)',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                  maxLength: 60,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _submitting
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('제안 등록'),
                  ),
                ),
              ] else if (_results.isNotEmpty) ...[
                Expanded(
                  child: ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
                    itemBuilder: (_, i) {
                      final p = _results[i];
                      return ListTile(
                        dense: true,
                        title: Text(p['name'] as String,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: Text(p['category'] as String? ?? '',
                            style: const TextStyle(fontSize: 11)),
                        trailing: const Icon(Icons.add, size: 18, color: color),
                        onTap: () => setState(() => _selected = p),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
