// team_detail_screen.dart — Option A 디자인 시스템 반영 (2026-06 최종)
// 선수탭: 타자/투수 2열 + 포지션/구위 필터
// 경기탭: 시리즈 카드(3등분) + 월별 막대차트 + 상대전적 2열 그리드
import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import '../../utils/team_theme.dart';

// ── 모델 ──────────────────────────────────────────────────────────────────────

class _Batter {
  final String name, pos, posType;
  final int no;
  const _Batter({required this.name, required this.pos, required this.posType, required this.no});
}

class _Pitcher {
  final String name, arm, type;
  final int no;
  const _Pitcher({required this.name, required this.arm, required this.type, required this.no});
}

class _GameSeries {
  final String opp, code, stadium, dates;
  final List<_SeriesGame> games;
  const _GameSeries({required this.opp, required this.code, required this.stadium,
      required this.dates, required this.games});
}

class _SeriesGame {
  final String date, result;
  final int hs, as_;
  const _SeriesGame({required this.date, required this.result, required this.hs, required this.as_});
}

class _H2HRecord {
  final String opp, code;
  final int wins, losses, games;
  const _H2HRecord({required this.opp, required this.code,
      required this.wins, required this.losses, required this.games});
}

class _MonthStat {
  final String month, avg;
  final int wins, losses;
  final double era;
  const _MonthStat({required this.month, required this.wins, required this.losses,
      required this.avg, required this.era});
}

class _RosterChange {
  final String type, name, pos, date;
  const _RosterChange({required this.type, required this.name, required this.pos, required this.date});
}

class _NewsItem {
  final String title, media, date;
  const _NewsItem({required this.title, required this.media, required this.date});
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

const _kBatters = [
  _Batter(name:'홍창기',  pos:'우익수',   posType:'외야', no:52),
  _Batter(name:'오스틴',  pos:'1루수',    posType:'내야', no:40),
  _Batter(name:'박해민',  pos:'중견수',   posType:'외야', no:10),
  _Batter(name:'문성주',  pos:'좌익수',   posType:'외야', no:22),
  _Batter(name:'오지환',  pos:'유격수',   posType:'내야', no:21),
  _Batter(name:'강문성',  pos:'포수',     posType:'포수', no:2),
  _Batter(name:'김범석',  pos:'2루수',    posType:'내야', no:5),
  _Batter(name:'구도혁',  pos:'3루수',    posType:'내야', no:7),
  _Batter(name:'신민재',  pos:'지명타자', posType:'DH',   no:36),
  _Batter(name:'김현수',  pos:'지명타자', posType:'DH',   no:25),
];

const _kPitchers = [
  _Pitcher(name:'임찬규', arm:'우완', type:'선발',   no:30),
  _Pitcher(name:'손주영', arm:'우완', type:'선발',   no:34),
  _Pitcher(name:'유수청', arm:'우완', type:'선발',   no:17),
  _Pitcher(name:'이우찬', arm:'좌완', type:'마무리', no:48),
  _Pitcher(name:'강태우', arm:'좌완', type:'불펜',   no:46),
  _Pitcher(name:'정우영', arm:'우완', type:'불펜',   no:35),
  _Pitcher(name:'이민호', arm:'우완', type:'불펜',   no:55),
  _Pitcher(name:'한자영', arm:'언더', type:'불펜',   no:53),
];

const _kSeries = [
  _GameSeries(opp:'KIA', code:'HT', stadium:'잠실', dates:'06.05~07', games:[
    _SeriesGame(date:'06.07', hs:5, as_:3, result:'win'),
    _SeriesGame(date:'06.06', hs:4, as_:4, result:'draw'),
    _SeriesGame(date:'06.05', hs:3, as_:5, result:'loss'),
  ]),
  _GameSeries(opp:'삼성', code:'SS', stadium:'대구', dates:'06.02~04', games:[
    _SeriesGame(date:'06.04', hs:8, as_:2, result:'win'),
    _SeriesGame(date:'06.03', hs:6, as_:2, result:'win'),
    _SeriesGame(date:'06.02', hs:1, as_:4, result:'loss'),
  ]),
  _GameSeries(opp:'한화', code:'HH', stadium:'대전', dates:'05.30~06.01', games:[
    _SeriesGame(date:'06.01', hs:2, as_:3, result:'loss'),
    _SeriesGame(date:'05.31', hs:7, as_:1, result:'win'),
    _SeriesGame(date:'05.30', hs:5, as_:3, result:'win'),
  ]),
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
        // ── AppBar ──────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          color: tc,
          child: Row(children: [
            _WhiteBtn32(icon: Icons.chevron_left, onTap: () => Navigator.maybePop(context)),
            const SizedBox(width: 10),
            Expanded(child: Text(_kTeam.name,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                    color: Colors.white, letterSpacing: -0.5))),
            _WhiteBtn32(
              icon: _isFav ? Icons.star_rounded : Icons.star_border_rounded,
              onTap: () => setState(() => _isFav = !_isFav),
            ),
          ]),
        ),
        // ── Content ─────────────────────────────────────────────────────────
        Expanded(child: _buildTabContent(cs, tc)),
        // ── 플로팅 탭바 ─────────────────────────────────────────────────────
        _buildFloatingNav(cs, tc),
      ])),
    );
  }

  Widget _buildTabContent(_C cs, Color tc) {
    switch (_tab) {
      case 0: return _buildOverview(cs, tc);
      case 1: return _PlayersTab(tc: tc, cs: cs);
      case 2: return _GamesTab(tc: tc, cs: cs, gameSub: _gameSub,
                  onGameSubChange: (i) => setState(() => _gameSub = i));
      case 3: return _buildCommunity(cs, tc);
      default: return const SizedBox();
    }
  }

  // ── 개요 탭 ───────────────────────────────────────────────────────────────
  Widget _buildOverview(_C cs, Color tc) {
    return ListView(padding: EdgeInsets.zero, children: [
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
            decoration: BoxDecoration(color: cs.paper, border: Border.all(color: cs.line), borderRadius: BorderRadius.circular(Radii.md)),
            child: IntrinsicHeight(child: Row(children: [
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
            ])),
          ),
        ]),
      ),
      _SectionLabel(label: '최근 등록말소', cs: cs),
      _CardWrap(cs: cs, child: Column(
        children: _kRosterChanges.asMap().entries.map((e) {
          final c = e.value;
          final last = e.key == _kRosterChanges.length - 1;
          final color = c.type == '등록' ? const Color(0xFF2563EB) : SemColor.live;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
            child: Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(5)),
                child: Text(c.type, style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: color))),
              const SizedBox(width: 10),
              Expanded(child: Text(c.name, style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: cs.ink))),
              Text(c.pos,  style: TextStyle(fontSize: 11, color: cs.sub)),
              const SizedBox(width: 8),
              Text(c.date, style: TextStyle(fontSize: 10, color: cs.sub)),
            ]),
          );
        }).toList(),
      )),
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
                Text(n.date, style: TextStyle(fontSize: 10, color: cs.sub)),
              ]),
            ]),
          );
        }).toList(),
      )),
      const SizedBox(height: 24),
    ]);
  }

  // ── 커뮤니티 탭 ───────────────────────────────────────────────────────────
  Widget _buildCommunity(_C cs, Color tc) {
    const posts = [
      {'cat':'자유', 'title':'오늘도 응원합니다!',              'author':'팬',      'likes':42,  'comments':8},
      {'cat':'분석', 'title':'이번 시즌 불펜 분석 — 개선점은?', 'author':'야구분석가', 'likes':31, 'comments':15},
      {'cat':'유머', 'title':'오늘 수비 GIF 모음',              'author':'웃긴야구', 'likes':97,  'comments':28},
    ];
    return ListView(padding: const EdgeInsets.all(18), children: posts.map((p) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.paper, border: Border.all(color: cs.line),
          borderRadius: BorderRadius.circular(Radii.lg)),
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
    )).toList());
  }

  // ── 플로팅 탭바 ───────────────────────────────────────────────────────────
  Widget _buildFloatingNav(_C cs, Color tc) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
    child: Container(
      height: 52,
      decoration: BoxDecoration(
        color: cs.paper, borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(cs.dark ? 0.4 : 0.12), blurRadius: 16, offset: const Offset(0, 4))],
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
              Text(_tabLabels[i], style: TextStyle(fontSize: 11,
                  fontWeight: sel ? Typo.bold : Typo.medium, color: sel ? tc : cs.sub)),
            ]),
          ),
        ));
      })),
    ),
  );
}

// ── 선수 탭 (2열: 타자 | 투수) ───────────────────────────────────────────────

class _PlayersTab extends StatefulWidget {
  final Color tc;
  final _C cs;
  const _PlayersTab({required this.tc, required this.cs});
  @override State<_PlayersTab> createState() => _PlayersTabState();
}

class _PlayersTabState extends State<_PlayersTab> {
  String _batFilter = '전체';
  String _pitFilter = '전체';

  static const _batFilters = ['전체','포수','내야','외야','DH'];
  static const _pitFilters = ['전체','우완','좌완','언더'];

  List<_Batter> get _filteredBat => _batFilter == '전체'
      ? _kBatters : _kBatters.where((p) => p.posType == _batFilter).toList();

  List<_Pitcher> get _filteredPit => _pitFilter == '전체'
      ? _kPitchers : _kPitchers.where((p) => p.arm == _pitFilter).toList();

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final tc = widget.tc;
    return Row(children: [
      // ── 왼쪽: 타자 ──────────────────────────────────────────────────────
      Expanded(child: Container(
        decoration: BoxDecoration(border: Border(right: BorderSide(color: cs.line))),
        child: Column(children: [
          _ColumnHeader(title: '타자', filters: _batFilters, selected: _batFilter, tc: tc, cs: cs,
              onSelect: (f) => setState(() => _batFilter = f)),
          Expanded(child: ListView.builder(
            itemCount: _filteredBat.length,
            itemBuilder: (_, i) {
              final p = _filteredBat[i];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.line))),
                child: Row(children: [
                  _NumChip(no: p.no, tc: tc, cs: cs),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: cs.ink)),
                    const SizedBox(height: 2),
                    Text(p.pos, style: TextStyle(fontSize: 10, color: cs.sub)),
                  ])),
                ]),
              );
            },
          )),
        ]),
      )),
      // ── 오른쪽: 투수 ────────────────────────────────────────────────────
      Expanded(child: Column(children: [
        _ColumnHeader(title: '투수', filters: _pitFilters, selected: _pitFilter, tc: tc, cs: cs,
            onSelect: (f) => setState(() => _pitFilter = f)),
        Expanded(child: ListView.builder(
          itemCount: _filteredPit.length,
          itemBuilder: (_, i) {
            final p = _filteredPit[i];
            final armColor = p.arm == '우완' ? tc
                : p.arm == '좌완' ? const Color(0xFF2563EB)
                : const Color(0xFF9333EA);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.line))),
              child: Row(children: [
                _NumChip(no: p.no, tc: tc, cs: cs),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: cs.ink)),
                  const SizedBox(height: 3),
                  Row(children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: armColor.withOpacity(0.12), borderRadius: BorderRadius.circular(3)),
                      child: Text(p.arm, style: TextStyle(fontSize: 9, fontWeight: Typo.bold, color: armColor))),
                    const SizedBox(width: 4),
                    Text(p.type, style: TextStyle(fontSize: 9, color: cs.sub)),
                  ]),
                ])),
              ]),
            );
          },
        )),
      ])),
    ]);
  }
}

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

// ── 경기 탭 ───────────────────────────────────────────────────────────────────

class _GamesTab extends StatelessWidget {
  final Color tc;
  final _C cs;
  final int gameSub;
  final ValueChanged<int> onGameSubChange;
  const _GamesTab({required this.tc, required this.cs,
      required this.gameSub, required this.onGameSubChange});

  @override
  Widget build(BuildContext context) {
    const subLabels = ['최근경기', '월별성적', '상대전적'];
    return Column(children: [
      Container(
        decoration: BoxDecoration(color: cs.paper, border: Border(bottom: BorderSide(color: cs.line))),
        child: Row(children: List.generate(subLabels.length, (i) {
          final sel = gameSub == i;
          return Expanded(child: GestureDetector(
            onTap: () => onGameSubChange(i),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11), alignment: Alignment.center,
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: sel ? tc : Colors.transparent, width: 2))),
              child: Text(subLabels[i], style: TextStyle(fontSize: 12,
                  fontWeight: sel ? Typo.extra : Typo.medium, color: sel ? tc : cs.sub)),
            ),
          ));
        })),
      ),
      Expanded(child: ListView(padding: const EdgeInsets.all(18), children: [
        if (gameSub == 0) ..._buildRecentGames(),
        if (gameSub == 1) ..._buildMonthly(),
        if (gameSub == 2) ..._buildH2H(),
      ])),
    ]);
  }

  // ── 최근경기: 연속결과 스트립 + 시리즈 카드(3등분) ───────────────────────
  List<Widget> _buildRecentGames() {
    final allGames = _kSeries.expand((s) => s.games).toList();
    return [
      // 연속결과 스트립
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(color: cs.paper, border: Border.all(color: cs.line),
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Text('최근', style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub)),
          const SizedBox(width: 8),
          ...allGames.map((g) {
            final isWin = g.result == 'win', isDraw = g.result == 'draw';
            final c = isWin ? tc : isDraw ? cs.sub : SemColor.live;
            return Expanded(child: Container(
              height: 28, margin: const EdgeInsets.only(left: 3),
              decoration: BoxDecoration(
                color: isWin ? tc.withOpacity(cs.dark ? 0.25 : 0.12)
                    : isDraw ? cs.paper2 : SemColor.live.withOpacity(cs.dark ? 0.22 : 0.08),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: isWin ? tc.withOpacity(0.4)
                    : isDraw ? cs.line2 : SemColor.live.withOpacity(0.3)),
              ),
              child: Center(child: Text(isWin ? '승' : isDraw ? '무' : '패',
                  style: TextStyle(fontSize: 11, fontWeight: Typo.extra, color: c))),
            ));
          }),
        ]),
      ),
      // 시리즈 카드들
      ..._kSeries.map((s) => _SeriesCard(series: s, tc: tc, cs: cs)),
    ];
  }

  // ── 월별성적: 요약칩 + 막대차트 + 테이블 ─────────────────────────────────
  List<Widget> _buildMonthly() {
    final totalW = _kMonthly.fold(0, (s, m) => s + m.wins);
    final totalL = _kMonthly.fold(0, (s, m) => s + m.losses);
    final maxG = _kMonthly.map((m) => m.wins + m.losses).reduce((a, b) => a > b ? a : b);

    return [
      // 요약 칩
      Row(children: [
        _SummaryChip(value: '$totalW승', color: const Color(0xFF2563EB), cs: cs),
        const SizedBox(width: 8),
        _SummaryChip(value: '$totalL패', color: SemColor.live, cs: cs),
        const SizedBox(width: 8),
        _SummaryChip(value: _kMonthly.last.avg, color: tc, cs: cs, label: '시즌 타율'),
      ]),
      const SizedBox(height: 14),
      // 막대 차트
      Container(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
        decoration: BoxDecoration(color: cs.paper, border: Border.all(color: cs.line),
            borderRadius: BorderRadius.circular(Radii.lg)),
        child: Column(children: [
          Text('월별 승/패', style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub, letterSpacing: 0.8)),
          const SizedBox(height: 14),
          SizedBox(
            height: 120,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: _kMonthly.map((m) {
              final total = m.wins + m.losses;
              final pct = total > 0 ? (m.wins / total * 100).round() : 0;
              final winH = (m.wins / maxG * 100).roundToDouble();
              final lossH = (m.losses / maxG * 100).roundToDouble();
              return Expanded(child: Column(children: [
                Text('$pct%', style: TextStyle(fontSize: 10, fontWeight: Typo.bold,
                    color: pct >= 50 ? tc : SemColor.live)),
                const SizedBox(height: 4),
                Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (m.wins > 0) Container(
                    height: winH * 0.9,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: tc.withOpacity(cs.dark ? 0.75 : 0.85),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                    child: Center(child: Text('${m.wins}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white))),
                  ),
                  if (m.losses > 0) Container(
                    height: lossH * 0.9,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: SemColor.live.withOpacity(cs.dark ? 0.65 : 0.75),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
                    ),
                    child: Center(child: Text('${m.losses}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white))),
                  ),
                ])),
                const SizedBox(height: 6),
                Text(m.month, style: TextStyle(fontSize: 11, fontWeight: Typo.bold, color: cs.ink)),
              ]));
            }).toList()),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _LegendDot(color: tc, label: '승'),
            const SizedBox(width: 14),
            _LegendDot(color: SemColor.live.withOpacity(0.8), label: '패'),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      // 타율/방어율 테이블
      Container(
        decoration: BoxDecoration(color: cs.paper, border: Border.all(color: cs.line),
            borderRadius: BorderRadius.circular(Radii.lg)),
        child: Column(children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: ['월','팀타율','방어율'].map((h) => Expanded(child: Text(h,
                textAlign: h == '월' ? TextAlign.left : TextAlign.center,
                style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub)))).toList())),
          Divider(height: 1, color: cs.line),
          ..._kMonthly.asMap().entries.map((e) {
            final m = e.value;
            final last = e.key == _kMonthly.length - 1;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
              child: Row(children: [
                Expanded(child: Text(m.month, style: TextStyle(fontSize: 12, fontWeight: Typo.bold, color: cs.ink))),
                Expanded(child: Text(m.avg, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.ink3))),
                Expanded(child: Text(m.era.toStringAsFixed(2), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.ink3))),
              ]),
            );
          }),
        ]),
      ),
    ];
  }

  // ── 상대전적: 원형 게이지 + 2열 카드 그리드 ─────────────────────────────
  List<Widget> _buildH2H() {
    final totalW = _kH2H.fold(0, (s, h) => s + h.wins);
    final totalL = _kH2H.fold(0, (s, h) => s + h.losses);
    final totalG = totalW + totalL;
    final overallPct = totalG > 0 ? (totalW / totalG * 100).round() : 0;

    return [
      // 전체 요약
      Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: cs.paper, border: Border.all(color: cs.line),
            borderRadius: BorderRadius.circular(Radii.lg)),
        child: Row(children: [
          SizedBox(width: 64, height: 64, child: Stack(children: [
            CustomPaint(size: const Size(64, 64),
                painter: _RingPainter(pct: overallPct / 100, color: tc, bg: cs.paper2)),
            Center(child: Text('$overallPct%',
                style: TextStyle(fontSize: 14, fontWeight: Typo.extra, color: tc))),
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
        children: _kH2H.map((h) {
          final pct = (h.wins / h.games * 100).round();
          final isWinning = h.wins >= h.losses;
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.paper,
              border: Border.all(color: isWinning ? tc.withOpacity(0.3) : cs.line),
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                TeamLogo(teamCode: h.code, size: 28),
                const SizedBox(width: 7),
                Text(h.opp, style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: cs.ink)),
              ]),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text('${h.wins}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF2563EB))),
                Text('승', style: TextStyle(fontSize: 11, color: cs.sub)),
                const SizedBox(width: 6),
                Text('${h.losses}', style: TextStyle(fontSize: 20, fontWeight: Typo.extra, color: SemColor.live)),
                Text('패', style: TextStyle(fontSize: 11, color: cs.sub)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(
                value: pct / 100, minHeight: 5, backgroundColor: cs.paper2,
                valueColor: AlwaysStoppedAnimation<Color>(isWinning ? tc : SemColor.live),
              )),
              const SizedBox(height: 4),
              Text('$pct%', style: TextStyle(fontSize: 11, fontWeight: Typo.bold,
                  color: isWinning ? tc : SemColor.live)),
            ]),
          );
        }).toList(),
      ),
    ];
  }
}

// ── 시리즈 카드 (3등분) ───────────────────────────────────────────────────────

class _SeriesCard extends StatelessWidget {
  final _GameSeries series;
  final Color tc;
  final _C cs;
  const _SeriesCard({required this.series, required this.tc, required this.cs});

  Color _resultColor(String r) =>
      r == 'win' ? tc : r == 'draw' ? cs.sub : SemColor.live;

  @override
  Widget build(BuildContext context) {
    final wins   = series.games.where((g) => g.result == 'win').length;
    final losses = series.games.where((g) => g.result == 'loss').length;
    final draws  = series.games.where((g) => g.result == 'draw').length;
    final isWinning = wins > losses;
    final label  = wins == series.games.length ? '스윕승'
        : losses == series.games.length ? '스윕패'
        : wins > losses ? '위닝' : wins < losses ? '루징' : '스플릿';
    final labelColor = isWinning ? tc : wins < losses ? SemColor.live : cs.sub;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.paper,
        border: Border.all(color: isWinning ? tc.withOpacity(0.3) : cs.line),
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: cs.dark ? null : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 2, offset: const Offset(0,1))],
      ),
      child: Column(children: [
        // 헤더
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.line))),
          child: Row(children: [
            Text('${series.dates} · ${series.stadium}',
                style: TextStyle(fontSize: 11, color: cs.sub)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: labelColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
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
              TeamLogo(teamCode: series.code, size: 44),
              const SizedBox(height: 7),
              Text('vs ${series.opp}', style: TextStyle(fontSize: 13, fontWeight: Typo.extra, color: cs.ink)),
            ]),
          )),
          VerticalDivider(width: 1, color: cs.line),
          // ② 경기별 스코어
          Expanded(child: Column(children: series.games.asMap().entries.map((e) {
            final g = e.value;
            final last = e.key == series.games.length - 1;
            final isWin = g.result == 'win', isDraw = g.result == 'draw';
            final rc = _resultColor(g.result);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
              child: Row(children: [
                SizedBox(width: 30, child: Text(g.date, style: TextStyle(fontSize: 10, color: cs.sub))),
                Expanded(child: Text('${g.hs} : ${g.as_}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, fontWeight: Typo.extra, color: cs.ink))),
                Container(width: 18, height: 18,
                  decoration: BoxDecoration(color: rc, borderRadius: BorderRadius.circular(5)),
                  child: Center(child: Text(isWin ? '승' : isDraw ? '무' : '패',
                      style: TextStyle(fontSize: 10, fontWeight: Typo.extra,
                          color: cs.dark ? const Color(0xFF0F0F12) : Colors.white)))),
              ]),
            );
          }).toList())),
          VerticalDivider(width: 1, color: cs.line),
          // ③ 시리즈 요약
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: series.games.map((g) {
                return Container(
                  width: 14, height: 14, margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(color: _resultColor(g.result), borderRadius: BorderRadius.circular(4)),
                );
              }).toList()),
              const SizedBox(height: 8),
              Text('$wins승$losses패${draws > 0 ? "${draws}무" : ""}',
                  style: TextStyle(fontSize: 18, fontWeight: Typo.extra, color: labelColor)),
              const SizedBox(height: 4),
              Text('${series.games.length}연전', style: TextStyle(fontSize: 10, color: cs.sub)),
            ]),
          )),
        ])),
      ]),
    );
  }
}

// ── 원형 게이지 CustomPainter ─────────────────────────────────────────────────

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
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -1.5707963267948966, // -π/2
      pct * 6.283185307179586, // pct * 2π
      false, paint,
    );
  }

  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ── 공통 소형 위젯 ─────────────────────────────────────────────────────────────

class _NumChip extends StatelessWidget {
  final int no;
  final Color tc;
  final _C cs;
  const _NumChip({required this.no, required this.tc, required this.cs});
  @override
  Widget build(BuildContext context) => Container(
    width: 30, height: 30,
    decoration: BoxDecoration(
      color: tc.withOpacity(cs.dark ? 0.18 : 0.08),
      border: Border.all(color: tc.withOpacity(0.2)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Center(child: Text('#$no', style: TextStyle(fontSize: 10, fontWeight: Typo.extra, color: tc))),
  );
}

class _WhiteBtn32 extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _WhiteBtn32({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(width: 32, height: 32,
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withOpacity(0.3))),
      child: Icon(icon, size: 18, color: Colors.white)),
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
      decoration: BoxDecoration(color: cs.paper, border: Border.all(color: cs.line),
          borderRadius: BorderRadius.circular(Radii.lg)),
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
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.xs),
        border: border != null ? Border.all(color: border!) : null),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: color)),
  );
}

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
