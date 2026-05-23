import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import 'post_detail_screen.dart';
import 'create_post_screen.dart';

const _categories = ['전체', '자유', '분석', '유머'];
const _teamCodes = <String, String>{
  'LG': 'LG', 'KT': 'KT', 'SK': 'SSG', 'NC': 'NC', 'OB': '두산',
  'HT': 'KIA', 'LT': '롯데', 'SS': '삼성', 'HH': '한화', 'WO': '키움',
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

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
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
        title: const Text('커뮤니티'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: '전체'),
            Tab(text: '팀별'),
            Tab(text: '인기'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.push<bool>(context,
              MaterialPageRoute(builder: (_) => const CreatePostScreen()));
          if (created == true) _latestKey.currentState?._load();
        },
        backgroundColor: const Color(0xFF1A237E),
        child: const Icon(Icons.edit, color: Colors.white),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _PostListTab(key: _latestKey, sort: 'latest'),
          const _TeamTab(),
          const _PostListTab(sort: 'hot'),
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
    setState(() { _loading = true; _page = 1; _hasMore = true; });
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
        setState(() {
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
          _posts = [..._posts, ...more];
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
                  selectedColor: const Color(0xFF1A237E),
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
                    color: selected ? const Color(0xFF1A237E) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? const Color(0xFF1A237E) : Colors.grey[300]!),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(t['short_name'] ?? '',
                          style: TextStyle(
                              fontSize: 11,
                              color: selected ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold)),
                      Text(t['name'] ?? '',
                          style: TextStyle(
                              fontSize: 10,
                              color: selected ? Colors.white70 : Colors.grey)),
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

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => PostDetailScreen(postId: post['id'])));
          onRefresh();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (post['team_name'] != null)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A237E).withAlpha(20),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(post['team_name'],
                          style: const TextStyle(fontSize: 10, color: Color(0xFF1A237E))),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(post['category'] ?? '',
                        style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(post['title'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Row(
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
