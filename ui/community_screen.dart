// community_screen.dart — Option A 디자인 시스템 반영
import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import '../../utils/team_theme.dart';

// ── 모델 ──────────────────────────────────────────────────────────────────────

class PostItem {
  final String? teamCode, teamName, category, title, content, author;
  final int likes, comments, views;
  final bool hasImage;
  const PostItem({
    this.teamCode, this.teamName, this.category,
    required this.title, this.content, required this.author,
    required this.likes, required this.comments, required this.views,
    this.hasImage = false,
  });
}

class FoodPlace {
  final String name, category, submitter;
  final int votes;
  final bool verified;
  final String? memo;
  const FoodPlace({
    required this.name, required this.category, required this.submitter,
    required this.votes, required this.verified, this.memo,
  });
}

// ── 샘플 데이터 ───────────────────────────────────────────────────────────────

const _kLatestPosts = [
  PostItem(teamCode:'LG', teamName:'LG', category:'자유',
      title:'오늘 7회말 역전 직관 진짜 소름이었다',
      author:'잠실주민', likes:42, comments:8, views:310, hasImage:true),
  PostItem(teamCode:'HT', teamName:'KIA', category:'분석',
      title:'김도영 시즌 25호 홈런 페이스 어때요?',
      author:'호랑이사랑', likes:31, comments:15, views:240),
  PostItem(teamCode:'HH', teamName:'한화', category:'자유',
      title:'류현진 복귀 이후 성적 정리',
      author:'독수리팬', likes:28, comments:9, views:187),
  PostItem(teamCode:'SS', teamName:'삼성', category:'자유',
      title:'원태인 오늘 완봉 가능성 있어 보임',
      author:'라이온즈팬', likes:19, comments:5, views:132),
];

const _kHotPosts = [
  PostItem(teamCode:'LG', teamName:'LG', category:'유머',
      title:'박해민 슈퍼캐치 GIF 모음집',
      author:'잠실주민', likes:184, comments:32, views:2410, hasImage:true),
  PostItem(teamCode:'HT', teamName:'KIA', category:'분석',
      title:'김도영 시즌 OPS 역대급 페이스 분석',
      author:'호랑이사랑', likes:97, comments:21, views:1230),
  PostItem(teamCode:'HH', teamName:'한화', category:'자유',
      title:'류현진 복귀 이후 성적 진짜 미쳤다',
      author:'독수리팬', likes:61, comments:14, views:890),
];

const _kFoodPlaces = [
  FoodPlace(name:'잠실 왕족발',       category:'족발·보쌈', submitter:'잠실주민', votes:24, verified:true,  memo:'경기 전 필수 코스'),
  FoodPlace(name:'뚝도시장 순대국밥', category:'국밥',      submitter:'야구사랑', votes:18, verified:false, memo:'가성비 최고'),
  FoodPlace(name:'GS25 잠실점',      category:'편의점',    submitter:'먹짱',    votes:7,  verified:false),
  FoodPlace(name:'화덕피자 잠실',    category:'피자',      submitter:'치즈덕',  votes:5,  verified:false, memo:'구장 옆 5분 거리'),
];

const _kTeams = [
  ['LG','LG'],['KT','KT'],['SK','SSG'],['NC','NC'],['OB','두산'],
  ['HT','KIA'],['LT','롯데'],['SS','삼성'],['HH','한화'],['WO','키움'],
];

const _kStadiums = ['서울','고척','수원','인천','대전','광주','대구','창원','사직'];

// ── 메인 화면 ─────────────────────────────────────────────────────────────────

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});
  @override State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override void initState() { super.initState(); _tab = TabController(length: 4, vsync: this); }
  @override void dispose()   { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cs = _C(context);
    return Scaffold(
      backgroundColor: cs.bg,
      body: SafeArea(child: Column(children: [
        // AppBar
        Container(
          color: cs.paper,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 13),
              child: Row(children: [
                Text('커뮤니티', style: TextStyle(fontSize: Typo.h2, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.5)),
                const Spacer(),
                _Btn32(border: cs.line2, onTap: () {},
                  child: Icon(Icons.search, size: 18, color: cs.ink3)),
              ]),
            ),
            TabBar(
              controller: _tab,
              labelColor: cs.ink,
              unselectedLabelColor: cs.sub,
              indicatorColor: cs.ink,
              indicatorWeight: 2,
              labelStyle: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra, fontFamily: 'Pretendard'),
              unselectedLabelStyle: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.medium, fontFamily: 'Pretendard'),
              tabs: const [Tab(text:'전체'), Tab(text:'팀별'), Tab(text:'인기'), Tab(text:'맛집')],
            ),
          ]),
        ),
        // Content
        Expanded(child: TabBarView(controller: _tab, children: [
          _AllTab(posts: _kLatestPosts, cs: cs),
          _TeamTab(cs: cs),
          _AllTab(posts: _kHotPosts, cs: cs),
          _FoodTab(cs: cs),
        ])),
      ])),
      floatingActionButton: AnimatedBuilder(
        animation: _tab,
        builder: (_, __) => _tab.index == 3 ? const SizedBox() : FloatingActionButton(
          onPressed: () {},
          backgroundColor: cs.ink,
          child: Icon(Icons.edit_outlined, color: cs.dark ? const Color(0xFF0F0F12) : Colors.white),
        ),
      ),
    );
  }
}

// ── 전체 / 인기 탭 ────────────────────────────────────────────────────────────

class _AllTab extends StatefulWidget {
  final List<PostItem> posts;
  final _C cs;
  const _AllTab({required this.posts, required this.cs});
  @override State<_AllTab> createState() => _AllTabState();
}

class _AllTabState extends State<_AllTab> {
  int _cat = 0;
  static const _cats = ['전체','자유','분석','유머'];

  @override
  Widget build(BuildContext context) {
    final filtered = _cat == 0 ? widget.posts
        : widget.posts.where((p) => p.category == _cats[_cat]).toList();
    return ListView(children: [
      _SearchBar(cs: widget.cs),
      _ChipRow(
        items: _cats,
        selected: _cat,
        onSelect: (i) => setState(() => _cat = i),
        cs: widget.cs,
      ),
      ...filtered.map((p) => _PostCard(post: p, cs: widget.cs)),
      const SizedBox(height: 80),
    ]);
  }
}

// ── 팀별 탭 ──────────────────────────────────────────────────────────────────

class _TeamTab extends StatefulWidget {
  final _C cs;
  const _TeamTab({required this.cs});
  @override State<_TeamTab> createState() => _TeamTabState();
}

class _TeamTabState extends State<_TeamTab> {
  String _sel = 'LG';

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final selName = kTeamDisplayNames[_sel] ?? _sel;
    final posts = [
      PostItem(teamCode:_sel, teamName:selName, category:'자유', title:'오늘 선발 기대됩니다', author:'팬', likes:28, comments:6, views:195),
      PostItem(teamCode:_sel, teamName:selName, category:'분석', title:'불펜 개선이 최우선 과제', author:'투수사랑', likes:14, comments:11, views:310),
      PostItem(teamCode:_sel, teamName:selName, category:'유머', title:'오늘 다이빙 캐치 ㄷㄷ', author:'야구팬', likes:52, comments:18, views:620, hasImage:true),
    ];
    return Column(children: [
      // 팀 칩 스크롤
      Container(
        height: 50,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.line))),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          itemCount: _kTeams.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final code = _kTeams[i][0], name = _kTeams[i][1];
            final active = _sel == code;
            final c = teamColor(code);
            return GestureDetector(
              onTap: () => setState(() => _sel = code),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: active ? c.withOpacity(cs.dark ? 0.22 : 0.1) : cs.paper2,
                  borderRadius: BorderRadius.circular(Radii.pill),
                  border: Border.all(color: active ? c.withOpacity(0.4) : cs.line),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  TeamLogo(teamCode: code, size: 14),
                  const SizedBox(width: 5),
                  Text(name, style: TextStyle(fontSize: 11, fontWeight: active ? Typo.bold : Typo.medium, color: active ? c : cs.ink2)),
                ]),
              ),
            );
          },
        ),
      ),
      Expanded(child: ListView(children: [
        ...posts.map((p) => _PostCard(post: p, cs: cs)),
        const SizedBox(height: 80),
      ])),
    ]);
  }
}

// ── 맛집 탭 ──────────────────────────────────────────────────────────────────

class _FoodTab extends StatefulWidget {
  final _C cs;
  const _FoodTab({required this.cs});
  @override State<_FoodTab> createState() => _FoodTabState();
}

class _FoodTabState extends State<_FoodTab> {
  String _sta = '서울';

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    return Column(children: [
      // 구장 칩
      Container(
        height: 50,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.line))),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          itemCount: _kStadiums.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final s = _kStadiums[i];
            final act = _sta == s;
            return GestureDetector(
              onTap: () => setState(() => _sta = s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: act ? cs.ink : cs.paper2,
                  borderRadius: BorderRadius.circular(Radii.pill),
                  border: Border.all(color: act ? cs.ink : cs.line),
                ),
                child: Text(s, style: TextStyle(fontSize: 12, fontWeight: act ? Typo.bold : Typo.medium,
                    color: act ? (cs.dark ? const Color(0xFF0F0F12) : Colors.white) : cs.ink3)),
              ),
            );
          },
        ),
      ),
      Expanded(child: Stack(children: [
        ListView.builder(
          padding: const EdgeInsets.only(bottom: 80),
          itemCount: _kFoodPlaces.length,
          itemBuilder: (_, i) => _FoodTile(place: _kFoodPlaces[i], cs: cs),
        ),
        // FAB
        Positioned(
          bottom: 16, right: 18,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: cs.ink, borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 14, offset: const Offset(0,4))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, size: 14, color: cs.dark ? const Color(0xFF0F0F12) : Colors.white),
                const SizedBox(width: 7),
                Text('맛집 제안', style: TextStyle(fontSize: 12, fontWeight: Typo.bold,
                    color: cs.dark ? const Color(0xFF0F0F12) : Colors.white)),
              ]),
            ),
          ),
        ),
      ])),
    ]);
  }
}

// ── 공통 위젯 ─────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final _C cs;
  const _SearchBar({required this.cs});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(18, 12, 18, 0),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: cs.paper2, border: Border.all(color: cs.line),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(children: [
      Icon(Icons.search, size: 16, color: cs.sub),
      const SizedBox(width: 9),
      Text('게시글 검색', style: TextStyle(fontSize: 13, color: cs.sub)),
    ]),
  );
}

class _ChipRow extends StatelessWidget {
  final List<String> items;
  final int selected;
  final ValueChanged<int> onSelect;
  final _C cs;
  const _ChipRow({required this.items, required this.selected, required this.onSelect, required this.cs});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(width: 6),
      itemBuilder: (_, i) {
        final act = i == selected;
        return GestureDetector(
          onTap: () => onSelect(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: act ? cs.ink : cs.paper,
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(color: act ? cs.ink : cs.line2),
            ),
            child: Text(items[i], style: TextStyle(fontSize: 12,
                fontWeight: act ? Typo.bold : Typo.medium,
                color: act ? (cs.dark ? const Color(0xFF0F0F12) : Colors.white) : cs.ink3)),
          ),
        );
      },
    ),
  );
}

class _PostCard extends StatelessWidget {
  final PostItem post;
  final _C cs;
  const _PostCard({required this.post, required this.cs});
  @override
  Widget build(BuildContext context) {
    final tc = post.teamCode != null ? teamColor(post.teamCode) : null;
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 8, 18, 0),
      decoration: BoxDecoration(
        color: cs.paper, border: Border.all(color: cs.line),
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: cs.dark ? null : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 2, offset: const Offset(0,1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (post.hasImage)
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: cs.paper2,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.lg)),
            ),
            child: Center(child: Text('이미지', style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: cs.sub))),
          ),
        Padding(
          padding: const EdgeInsets.all(13),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 5, runSpacing: 5, children: [
              if (tc != null) _Tag(label: post.teamName ?? '', color: tc, cs: cs),
              _Tag(label: post.category ?? '', color: cs.ink3, cs: cs, muted: true),
            ]),
            const SizedBox(height: 7),
            Text(post.title, style: TextStyle(fontSize: Typo.body, fontWeight: Typo.bold, color: cs.ink, height: 1.45)),
            const SizedBox(height: 9),
            Row(children: [
              Text(post.author, style: TextStyle(fontSize: 10, color: cs.sub)),
              const Spacer(),
              _MetaItem(icon: Icons.favorite_border, value: post.likes, cs: cs),
              const SizedBox(width: 10),
              _MetaItem(icon: Icons.chat_bubble_outline, value: post.comments, cs: cs),
              const SizedBox(width: 10),
              _MetaItem(icon: Icons.visibility_outlined, value: post.views, cs: cs),
            ]),
          ]),
        ),
      ]),
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
      color: muted ? cs.paper2 : color.withOpacity(cs.dark ? 0.22 : 0.1),
      borderRadius: BorderRadius.circular(Radii.xs),
      border: muted ? Border.all(color: cs.line) : null,
    ),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: Typo.bold,
        color: muted ? cs.ink3 : color)),
  );
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final int value;
  final _C cs;
  const _MetaItem({required this.icon, required this.value, required this.cs});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 12, color: cs.sub),
    const SizedBox(width: 3),
    Text('$value', style: TextStyle(fontSize: 10, color: cs.sub)),
  ]);
}

class _FoodTile extends StatelessWidget {
  final FoodPlace place;
  final _C cs;
  const _FoodTile({required this.place, required this.cs});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.line))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: place.verified ? SemColor.live.withOpacity(0.1) : cs.paper2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: place.verified ? SemColor.live.withOpacity(0.25) : cs.line),
        ),
        child: Center(child: Text(place.verified ? '✓' : '🍽', style: const TextStyle(fontSize: 16))),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(place.name, style: TextStyle(fontSize: Typo.body, fontWeight: Typo.bold, color: cs.ink)),
          if (place.verified) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: SemColor.live.withOpacity(0.1), borderRadius: BorderRadius.circular(Radii.xs)),
              child: const Text('인증', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: SemColor.live)),
            ),
          ],
        ]),
        const SizedBox(height: 3),
        Text('${place.category} · ${place.submitter} 추천', style: TextStyle(fontSize: Typo.caption, color: cs.ink3)),
        if (place.memo != null) ...[
          const SizedBox(height: 3),
          Text('"${place.memo}"', style: TextStyle(fontSize: Typo.caption, color: cs.sub, fontStyle: FontStyle.italic, height: 1.4)),
        ],
      ])),
      Column(children: [
        const Text('👍', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 3),
        Text('${place.votes}', style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: cs.ink3)),
      ]),
    ]),
  );
}

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
