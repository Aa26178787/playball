// team_detail_screen.dart — Option A 디자인 시스템 반영 (2026-06)
// team_detail_screen.dart 기반 재구성
import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import '../../utils/team_theme.dart';

// ── 모델 ──────────────────────────────────────────────────────────────────────

class _RosterChange {
  final String type, name, pos, date;
  const _RosterChange({required this.type, required this.name, required this.pos, required this.date});
}

class _NewsItem {
  final String title, media, date;
  const _NewsItem({required this.title, required this.media, required this.date});
}

class _RecentGame {
  final String home, away, result, date, stadium;
  final int hs, as_;
  const _RecentGame({required this.home, required this.away, required this.result,
      required this.date, required this.stadium, required this.hs, required this.as_});
}

class _H2HRecord {
  final String opp, code;
  final int wins, losses, games;
  const _H2HRecord({required this.opp, required this.code,
      required this.wins, required this.losses, required this.games});
}

class _MonthStat {
  final String month;
  final int wins, losses;
  final String avg;
  final double era;
  const _MonthStat({required this.month, required this.wins, required this.losses,
      required this.avg, required this.era});
}

class _Player {
  final String name, pos;
  final int no;
  final String? avg, era;
  final int? hr, rbi, w, l, sv;
  const _Player({required this.name, required this.pos, required this.no,
      this.avg, this.era, this.hr, this.rbi, this.w, this.l, this.sv});
}

class _TeamData {
  final String code, name;
  final int rank, wins, losses;
  final double gb, avg, era, whip;
  final int rs, ra, hr;
  const _TeamData({required this.code, required this.name, required this.rank,
      required this.wins, required this.losses, required this.gb,
      required this.avg, required this.era, required this.whip,
      required this.rs, required this.ra, required this.hr});
}

// ── 샘플 데이터 ───────────────────────────────────────────────────────────────

const _kTeam = _TeamData(
  code:'LG', name:'LG 트윈스', rank:2, wins:42, losses:28, gb:3.0,
  avg:.285, era:3.42, whip:1.18, rs:312, ra:264, hr:72,
);

const _kPlayers = [
  _Player(name:'홍창기', pos:'외야', no:52, avg:'.312', hr:8,  rbi:42),
  _Player(name:'오스틴', pos:'1루',  no:40, avg:'.298', hr:18, rbi:58),
  _Player(name:'박해민', pos:'외야', no:10, avg:'.274', hr:3,  rbi:28),
  _Player(name:'임찬규', pos:'투수', no:30, era:'3.12', w:9,  l:4),
  _Player(name:'이우찬', pos:'투수', no:48, era:'2.85', sv:14, w:3, l:2),
];

const _kGames = [
  _RecentGame(home:'LG', away:'KIA', hs:5, as_:3, result:'win',  date:'06.07', stadium:'잠실'),
  _RecentGame(home:'LG', away:'두산', hs:7, as_:2, result:'win',  date:'06.06', stadium:'잠실'),
  _RecentGame(home:'LG', away:'두산', hs:3, as_:5, result:'loss', date:'06.05', stadium:'잠실'),
  _RecentGame(home:'삼성', away:'LG', hs:2, as_:6, result:'win',  date:'06.03', stadium:'대구'),
  _RecentGame(home:'삼성', away:'LG', hs:4, as_:1, result:'loss', date:'06.02', stadium:'대구'),
];

const _kH2H = [
  _H2HRecord(opp:'한화', code:'HH', wins:4, losses:3, games:7),
  _H2HRecord(opp:'KIA',  code:'HT', wins:3, losses:4, games:7),
  _H2HRecord(opp:'삼성', code:'SS', wins:5, losses:2, games:7),
  _H2HRecord(opp:'두산', code:'OB', wins:4, losses:3, games:7),
  _H2HRecord(opp:'KT',   code:'KT', wins:6, losses:1, games:7),
  _H2HRecord(opp:'SSG',  code:'SK', wins:4, losses:3, games:7),
  _H2HRecord(opp:'NC',   code:'NC', wins:5, losses:2, games:7),
  _H2HRecord(opp:'롯데', code:'LT', wins:6, losses:1, games:7),
  _H2HRecord(opp:'키움', code:'WO', wins:5, losses:2, games:7),
];

const _kMonthly = [
  _MonthStat(month:'3월', wins:6,  losses:3,  avg:'.284', era:3.21),
  _MonthStat(month:'4월', wins:12, losses:8,  avg:'.291', era:3.45),
  _MonthStat(month:'5월', wins:14, losses:6,  avg:'.296', era:3.18),
  _MonthStat(month:'6월', wins:10, losses:11, avg:'.279', era:3.62),
];

const _kRosterChanges = [
  _RosterChange(type:'등록', name:'박동원', pos:'포수',   date:'06.05'),
  _RosterChange(type:'말소', name:'김진성', pos:'투수',   date:'06.03'),
  _RosterChange(type:'등록', name:'이민호', pos:'외야수', date:'05.30'),
];

const _kNews = [
  _NewsItem(title:'LG, 임찬규 6승째 호투…두산 꺾고 선두권 유지', media:'스포츠조선', date:'06.07 18:45'),
  _NewsItem(title:'오스틴, 시즌 18호 홈런…타점도 58개로 팀 1위',  media:'일간스포츠', date:'06.06 22:10'),
  _NewsItem(title:'LG 염경엽 감독 "이번 달이 시즌 분수령"',        media:'스포티비뉴스', date:'06.05 14:30'),
];

// ── 메인 화면 ─────────────────────────────────────────────────────────────────

class TeamDetailScreen extends StatefulWidget {
  /// 실제 앱에서는 team 데이터를 주입받아 사용
  final Map<String, dynamic>? team;
  const TeamDetailScreen({super.key, this.team});
  @override State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  int _tab    = 0;
  int _gameSub = 0;
  bool _isFav = true;

  static const _tabLabels = ['개요', '선수', '경기', '커뮤'];
  static const _tabIcons  = [
    Icons.grid_view_rounded,
    Icons.people_outline,
    Icons.sports_baseball_outlined,
    Icons.forum_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final cs = _C(context);
    final tc = teamColor(_kTeam.code);

    return Scaffold(
      backgroundColor: cs.bg,
      body: SafeArea(child: Column(children: [
        // ── AppBar (팀컬러 배경) ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          color: tc,
          child: Row(children: [
            _WhiteBtn32(icon: Icons.chevron_left, onTap: () => Navigator.maybePop(context)),
            const SizedBox(width: 10),
            Expanded(child: Text(_kTeam.name,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5))),
            _WhiteBtn32(
              icon: _isFav ? Icons.star_rounded : Icons.star_border_rounded,
              onTap: () => setState(() => _isFav = !_isFav),
            ),
          ]),
        ),
        // ── Content ──────────────────────────────────────────────────────────
        Expanded(child: _buildTabContent(cs, tc)),
        // ── 플로팅 탭바 (_buildMainFloatingNav 기반) ──────────────────────────
        _buildFloatingNav(cs, tc),
      ])),
    );
  }

  Widget _buildTabContent(_C cs, Color tc) {
    switch (_tab) {
      case 0: return _buildOverview(cs, tc);
      case 1: return _buildPlayers(cs, tc);
      case 2: return _buildGames(cs, tc);
      case 3: return _buildCommunity(cs, tc);
      default: return const SizedBox();
    }
  }

  // ── 개요 탭 ───────────────────────────────────────────────────────────────
  Widget _buildOverview(_C cs, Color tc) {
    return ListView(padding: EdgeInsets.zero, children: [
      // 팀 헤더
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: tc.withOpacity(cs.dark ? 0.14 : 0.06),
          border: Border(bottom: BorderSide(color: tc.withOpacity(cs.dark ? 0.3 : 0.15))),
        ),
        child: Column(children: [
          Row(children: [
            TeamLogo(teamCode: _kTeam.code, size: 64),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(_kTeam.name, style: TextStyle(fontSize: 20, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.5)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: tc.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                  child: Text('${_kTeam.rank}위', style: TextStyle(fontSize: 12, fontWeight: Typo.bold, color: tc)),
                ),
              ]),
              const SizedBox(height: 5),
              Text('${_kTeam.wins}승 ${_kTeam.losses}패 · ${_kTeam.gb == 0 ? "선두" : "${_kTeam.gb} GB"}',
                  style: TextStyle(fontSize: 13, color: cs.ink3)),
            ])),
          ]),
          const SizedBox(height: 14),
          // 시즌 스탯 6칸 그리드
          Container(
            decoration: BoxDecoration(
              color: cs.paper, border: Border.all(color: cs.line),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: IntrinsicHeight(
              child: Row(children: [
                _StatBlock(label: '팀타율', value: _kTeam.avg.toStringAsFixed(3), cs: cs),
                VerticalDivider(width: 1, color: cs.line),
                _StatBlock(label: '방어율', value: _kTeam.era.toStringAsFixed(2), cs: cs),
                VerticalDivider(width: 1, color: cs.line),
                _StatBlock(label: 'WHIP',  value: _kTeam.whip.toStringAsFixed(2), cs: cs),
                VerticalDivider(width: 1, color: cs.line),
                _StatBlock(label: '득점',  value: '${_kTeam.rs}', cs: cs),
                VerticalDivider(width: 1, color: cs.line),
                _StatBlock(label: '실점',  value: '${_kTeam.ra}', cs: cs),
                VerticalDivider(width: 1, color: cs.line),
                _StatBlock(label: '홈런',  value: '${_kTeam.hr}', cs: cs),
              ]),
            ),
          ),
        ]),
      ),
      // 등록말소
      _SectionLabel(label: '최근 등록말소', cs: cs),
      _CardWrap(cs: cs, child: Column(
        children: _kRosterChanges.asMap().entries.map((e) {
          final c = e.value;
          final last = e.key == _kRosterChanges.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.type == '등록' ? const Color(0xFF2563EB).withOpacity(0.1) : SemColor.live.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(c.type, style: TextStyle(fontSize: 10, fontWeight: Typo.bold,
                    color: c.type == '등록' ? const Color(0xFF2563EB) : SemColor.live)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(c.name, style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: cs.ink))),
              Text(c.pos,  style: TextStyle(fontSize: 11, color: cs.sub)),
              const SizedBox(width: 8),
              Text(c.date, style: TextStyle(fontSize: 10, color: cs.sub)),
            ]),
          );
        }).toList(),
      )),
      // 뉴스
      _SectionLabel(label: '최근 뉴스', cs: cs),
      _CardWrap(cs: cs, child: Column(
        children: _kNews.asMap().entries.map((e) {
          final n = e.value;
          final last = e.key == _kNews.length - 1;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n.title, style: TextStyle(fontSize: 12, fontWeight: Typo.medium, color: cs.ink, height: 1.45)),
              const SizedBox(height: 5),
              Row(children: [
                Text(n.media, style: TextStyle(fontSize: 10, color: cs.sub)),
                const SizedBox(width: 8),
                Text(n.date,  style: TextStyle(fontSize: 10, color: cs.sub)),
              ]),
            ]),
          );
        }).toList(),
      )),
      const SizedBox(height: 24),
    ]);
  }

  // ── 선수 탭 ───────────────────────────────────────────────────────────────
  Widget _buildPlayers(_C cs, Color tc) {
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      _SectionLabel(label: '선발 로스터', cs: cs),
      _CardWrap(cs: cs, child: Column(
        children: _kPlayers.asMap().entries.map((e) {
          final p = e.value;
          final last = e.key == _kPlayers.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: tc.withOpacity(cs.dark ? 0.18 : 0.08),
                  border: Border.all(color: tc.withOpacity(0.2)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: Text('#${p.no}',
                    style: TextStyle(fontSize: 13, fontWeight: Typo.extra, color: tc))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: TextStyle(fontSize: 14, fontWeight: Typo.extra, color: cs.ink)),
                const SizedBox(height: 4),
                Text(p.pos,  style: TextStyle(fontSize: 11, color: cs.sub)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (p.avg != null)
                  Text(p.avg!,  style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: tc)),
                if (p.era != null)
                  Text('ERA ${p.era!}', style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: tc)),
                const SizedBox(height: 2),
                Text(p.hr  != null ? '${p.hr}HR ${p.rbi}RBI'
                   : p.sv != null ? '${p.w}승 ${p.sv}세'
                   : '',
                    style: TextStyle(fontSize: 10, color: cs.sub)),
              ]),
            ]),
          );
        }).toList(),
      )),
    ]);
  }

  // ── 경기 탭 ───────────────────────────────────────────────────────────────
  Widget _buildGames(_C cs, Color tc) {
    const subLabels = ['최근경기', '월별성적', '상대전적'];
    return Column(children: [
      // 서브탭
      Container(
        decoration: BoxDecoration(color: cs.paper, border: Border(bottom: BorderSide(color: cs.line))),
        child: Row(children: List.generate(subLabels.length, (i) {
          final sel = _gameSub == i;
          return Expanded(child: GestureDetector(
            onTap: () => setState(() => _gameSub = i),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: sel ? tc : Colors.transparent, width: 2)),
              ),
              child: Text(subLabels[i], style: TextStyle(fontSize: 12,
                  fontWeight: sel ? Typo.extra : Typo.medium,
                  color: sel ? tc : cs.sub)),
            ),
          ));
        })),
      ),
      Expanded(child: ListView(padding: const EdgeInsets.all(18), children: [
        if (_gameSub == 0) ..._buildRecentGames(cs, tc),
        if (_gameSub == 1) ..._buildMonthlyStats(cs, tc),
        if (_gameSub == 2) ..._buildH2H(cs, tc),
      ])),
    ]);
  }

  List<Widget> _buildRecentGames(_C cs, Color tc) => _kGames.map((g) {
    final isWin = g.result == 'win';
    final c = isWin ? const Color(0xFF2563EB) : SemColor.live;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.paper, border: Border.all(color: cs.line),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
          child: Text(isWin ? '승' : '패', style: TextStyle(fontSize: 11, fontWeight: Typo.bold, color: c)),
        ),
        const SizedBox(width: 10),
        Text(g.date, style: TextStyle(fontSize: 11, color: cs.sub)),
        Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(g.home, style: TextStyle(fontSize: 12, fontWeight: Typo.bold, color: cs.ink)),
          const SizedBox(width: 8),
          Text('${g.hs} : ${g.as_}', style: TextStyle(fontSize: 14, fontWeight: Typo.extra, color: cs.ink)),
          const SizedBox(width: 8),
          Text(g.away, style: TextStyle(fontSize: 12, fontWeight: Typo.bold, color: cs.ink)),
        ])),
        Text(g.stadium, style: TextStyle(fontSize: 10, color: cs.sub)),
      ]),
    );
  }).toList();

  List<Widget> _buildMonthlyStats(_C cs, Color tc) => [
    Container(
      decoration: BoxDecoration(color: cs.paper, border: Border.all(color: cs.line), borderRadius: BorderRadius.circular(Radii.lg)),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: ['월','승','패','타율','방어율'].map((h) =>
            Expanded(child: Text(h, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub)))).toList(),
        ),
        Divider(height: 1, color: cs.line),
        ..._kMonthly.asMap().entries.map((e) {
          final m = e.value;
          final last = e.key == _kMonthly.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
            child: Row(children: [
              Expanded(child: Text(m.month, style: TextStyle(fontSize: 12, fontWeight: Typo.bold, color: cs.ink))),
              Expanded(child: Text('${m.wins}', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: Typo.bold, color: const Color(0xFF2563EB)))),
              Expanded(child: Text('${m.losses}', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: Typo.bold, color: SemColor.live))),
              Expanded(child: Text(m.avg, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: cs.ink3))),
              Expanded(child: Text(m.era.toStringAsFixed(2), textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: cs.ink3))),
            ]),
          );
        }),
      ]),
    ),
  ];

  List<Widget> _buildH2H(_C cs, Color tc) => [
    Container(
      decoration: BoxDecoration(color: cs.paper, border: Border.all(color: cs.line), borderRadius: BorderRadius.circular(Radii.lg)),
      child: Column(
        children: _kH2H.asMap().entries.map((e) {
          final h = e.value;
          final last = e.key == _kH2H.length - 1;
          final pct = (h.wins / h.games * 100).round();
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
            child: Row(children: [
              TeamLogo(teamCode: h.code, size: 32),
              const SizedBox(width: 10),
              SizedBox(width: 36, child: Text(h.opp,
                  style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: cs.ink))),
              const SizedBox(width: 8),
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: pct / 100,
                  minHeight: 6,
                  backgroundColor: cs.paper2,
                  valueColor: AlwaysStoppedAnimation<Color>(tc),
                ),
              )),
              const SizedBox(width: 8),
              SizedBox(width: 28, child: Text('$pct%',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: Typo.extra, color: tc))),
              const SizedBox(width: 8),
              SizedBox(width: 40, child: Text('${h.wins}승${h.losses}패',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, color: cs.sub))),
            ]),
          );
        }).toList(),
      ),
    ),
  ];

  // ── 커뮤니티 탭 ───────────────────────────────────────────────────────────
  Widget _buildCommunity(_C cs, Color tc) {
    const posts = [
      {'cat':'자유', 'title':'오늘도 응원합니다!',         'author':'팬',    'likes':42,  'comments':8},
      {'cat':'분석', 'title':'이번 시즌 불펜 분석 — 개선점은?', 'author':'야구분석가', 'likes':31, 'comments':15},
      {'cat':'유머', 'title':'오늘 수비 GIF 모음',         'author':'웃긴야구', 'likes':97, 'comments':28},
      {'cat':'자유', 'title':'직관 후기 — 오늘 날씨 최고',  'author':'직관러', 'likes':19,  'comments':6},
    ];
    return ListView(
      padding: const EdgeInsets.all(18),
      children: posts.map((p) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.paper, border: Border.all(color: cs.line),
          borderRadius: BorderRadius.circular(Radii.lg),
          boxShadow: cs.dark ? null : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 2, offset: const Offset(0,1))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 5, children: [
            _SmallChip(label: _kTeam.name.split(' ')[0], color: tc, bg: tc.withOpacity(0.1)),
            _SmallChip(label: p['cat'] as String, color: cs.ink3, bg: cs.paper2, border: cs.line),
          ]),
          const SizedBox(height: 7),
          Text(p['title'] as String, style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: cs.ink, height: 1.45)),
          const SizedBox(height: 8),
          Row(children: [
            Text(p['author'] as String, style: TextStyle(fontSize: 10, color: cs.sub)),
            const Spacer(),
            Text('♡ ${p['likes']}', style: TextStyle(fontSize: 10, color: cs.sub)),
            const SizedBox(width: 10),
            Text('💬 ${p['comments']}', style: TextStyle(fontSize: 10, color: cs.sub)),
          ]),
        ]),
      )).toList(),
    );
  }

  // ── 플로팅 탭바 (_buildMainFloatingNav 기반) ─────────────────────────────
  Widget _buildFloatingNav(_C cs, Color tc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: cs.paper,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(cs.dark ? 0.4 : 0.12),
            blurRadius: 16, offset: const Offset(0, 4),
          )],
        ),
        child: Row(children: List.generate(_tabLabels.length, (i) {
          final sel = _tab == i;
          return Expanded(child: GestureDetector(
            onTap: () => setState(() => _tab = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: sel ? tc.withOpacity(cs.dark ? 0.22 : 0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(_tabIcons[i], size: 18, color: sel ? tc : cs.sub),
                const SizedBox(height: 1),
                Text(_tabLabels[i], style: TextStyle(
                  fontSize: 11,
                  fontWeight: sel ? Typo.bold : Typo.medium,
                  color: sel ? tc : cs.sub,
                )),
              ]),
            ),
          ));
        })),
      ),
    );
  }
}

// ── 공통 소형 위젯 ─────────────────────────────────────────────────────────────

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
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Icon(icon, size: 18, color: Colors.white),
    ),
  );
}

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
        boxShadow: cs.dark ? null : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 2, offset: const Offset(0,1))],
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
