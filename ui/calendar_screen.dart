// calendar_screen.dart — Option A 디자인 시스템 반영 (2026-06)
import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import '../../utils/team_theme.dart';

// ── 모델 ──────────────────────────────────────────────────────────────────────

enum GameStatus { live, done, upcoming }

class KboGame {
  final String homeCode, homeName, awayCode, awayName, stadium;
  final int? hs, as_;
  final GameStatus status;
  final String? inning, time, homePitcher, awayPitcher, mineCode;
  const KboGame({
    required this.homeCode, required this.homeName,
    required this.awayCode, required this.awayName,
    required this.stadium, required this.status,
    this.hs, this.as_, this.inning, this.time,
    this.homePitcher, this.awayPitcher, this.mineCode,
  });
}

class PersonalEvent {
  final String title;
  final String? desc;
  final Color color;
  const PersonalEvent({required this.title, this.desc, required this.color});
}

// ── 샘플 데이터 ───────────────────────────────────────────────────────────────

const _kMyTeam = 'LG';
const _kToday  = 7;

const Map<int, List<KboGame>> _kGames = {
  7: [
    KboGame(homeCode:'LG', homeName:'LG', awayCode:'HT', awayName:'KIA',
        stadium:'잠실야구장', status:GameStatus.live,
        hs:5, as_:3, inning:'7회말', mineCode:'LG'),
    KboGame(homeCode:'HH', homeName:'한화', awayCode:'SS', awayName:'삼성',
        stadium:'이글스파크', status:GameStatus.upcoming,
        time:'18:30', homePitcher:'류현진', awayPitcher:'원태인'),
  ],
  4: [KboGame(homeCode:'HH', homeName:'한화', awayCode:'SS', awayName:'삼성',
      stadium:'이글스파크', status:GameStatus.done, hs:7, as_:2,
      homePitcher:'류현진', awayPitcher:'원태인')],
  11: [KboGame(homeCode:'LG', homeName:'LG', awayCode:'HT', awayName:'KIA',
      stadium:'잠실야구장', status:GameStatus.done, hs:3, as_:5,
      homePitcher:'양현종', awayPitcher:'임찬규', mineCode:'LG')],
};

const Map<int, List<PersonalEvent>> _kPersonal = {
  7: [PersonalEvent(title:'잠실 직관', desc:'친구와 야구장 약속', color:Color(0xFFC30452))],
  8: [PersonalEvent(title:'잠실 직관', desc:'친구와 야구장 약속', color:Color(0xFFC30452))],
  9: [PersonalEvent(title:'잠실 직관', desc:'친구와 야구장 약속', color:Color(0xFFC30452))],
};

// dots: 경기 수 표시
const Map<int,int> _kDots = {3:3,4:3,5:2,7:2,8:2,10:1,11:3,14:3,17:1,18:3,21:2,24:2,25:2,28:1};
// visit result: true=win, false=loss
const Map<int,bool> _kVisit = {4:true, 11:false};
// event bar (잠실 직관)
const int _kBarStart = 7, _kBarEnd = 9;

// ── 메인 화면 ─────────────────────────────────────────────────────────────────

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  int  _selDay     = _kToday;
  bool _myTeamOnly = false;

  Color get _myColor => teamColor(_kMyTeam);

  // June 2026 시작 = 월요일 (offset 1)
  List<int?> get _cells => List.generate(42, (i) {
    final d = i; // offset=1 이므로 i-1+1 = i
    return (d >= 1 && d <= 30) ? d : null;
  });

  @override
  Widget build(BuildContext context) {
    final cs = _C(context);
    return Scaffold(
      backgroundColor: cs.bg,
      body: SafeArea(
        child: Column(children: [
          _AppBar(myColor:_myColor, myTeamOnly:_myTeamOnly, cs:cs,
            onToggleStar: () => setState(() => _myTeamOnly = !_myTeamOnly)),
          Expanded(child: SingleChildScrollView(child: Column(children: [
            _MonthNav(cs: cs),
            _AttendanceBanner(myColor:_myColor, cs:cs),
            _DowHeader(cs:cs),
            _CalGrid(
              cells:      _cells,
              selDay:     _selDay,
              myColor:    _myColor,
              cs:         cs,
              onDayTap:   (d) => setState(() => _selDay = d),
            ),
            Divider(height:1, color:cs.line),
            _DayDetail(
              selDay:     _selDay,
              myTeamOnly: _myTeamOnly,
              cs:         cs,
            ),
          ]))),
        ]),
      ),
    );
  }
}

// ── 색상 컨텍스트 헬퍼 ────────────────────────────────────────────────────────

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

// ── 서브 위젯들 ───────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final Color myColor;
  final bool myTeamOnly;
  final _C cs;
  final VoidCallback onToggleStar;
  const _AppBar({required this.myColor, required this.myTeamOnly, required this.cs, required this.onToggleStar});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      decoration: BoxDecoration(color: cs.paper, border: Border(bottom: BorderSide(color: cs.line))),
      child: Row(children: [
        Text('캘린더', style: TextStyle(fontSize: Typo.h2, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.5)),
        const Spacer(),
        _Btn32(
          child: Icon(myTeamOnly ? Icons.star_rounded : Icons.star_outline_rounded, size: 18,
              color: myTeamOnly ? myColor : cs.ink3),
          bg: myTeamOnly ? myColor.withOpacity(0.12) : Colors.transparent,
          border: myTeamOnly ? myColor.withOpacity(0.5) : cs.line2,
          onTap: onToggleStar,
        ),
        const SizedBox(width: 7),
        _Btn32(
          child: Icon(Icons.add, size: 18, color: cs.ink3),
          border: cs.line2,
          onTap: () {},
        ),
      ]),
    );
  }
}

class _MonthNav extends StatelessWidget {
  final _C cs;
  const _MonthNav({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _NavBtn(icon: Icons.chevron_left, cs: cs),
        Text('2026년 6월', style: TextStyle(fontSize: Typo.title, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.3)),
        _NavBtn(icon: Icons.chevron_right, cs: cs),
      ]),
    );
  }
}

class _AttendanceBanner extends StatelessWidget {
  final Color myColor;
  final _C cs;
  const _AttendanceBanner({required this.myColor, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.paper, border: Border.all(color: cs.line),
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: cs.dark ? null : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 2, offset: const Offset(0,1))],
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: myColor.withOpacity(cs.dark ? 0.22 : 0.10), borderRadius: BorderRadius.circular(Radii.sm)),
          child: const Center(child: Text('🏟', style: TextStyle(fontSize: 18))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('직관 승률', style: TextStyle(fontSize: Typo.body, fontWeight: Typo.bold, color: cs.ink)),
            const SizedBox(width: 6),
            Text('67%', style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra, color: myColor)),
          ]),
          const SizedBox(height: 5),
          Row(children: [
            _StatChip(label: '2승', color: const Color(0xFF2563EB)),
            const SizedBox(width: 5),
            _StatChip(label: '1패', color: SemColor.live),
          ]),
        ])),
        Row(children: [
          _TextPill(label: '통계', color: cs.ink3, border: cs.line),
          const SizedBox(width: 5),
          _TextPill(label: '랭킹', color: SemColor.live, border: SemColor.live.withOpacity(0.25)),
        ]),
      ]),
    );
  }
}

class _DowHeader extends StatelessWidget {
  final _C cs;
  const _DowHeader({required this.cs});
  @override
  Widget build(BuildContext context) {
    const days = ['일','월','화','수','목','금','토'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(children: List.generate(7, (i) => Expanded(
        child: Center(child: Text(days[i], style: TextStyle(
          fontSize: Typo.caption, fontWeight: Typo.medium,
          color: i == 0 ? SemColor.live : i == 6 ? const Color(0xFF2563EB) : cs.sub,
        ))),
      ))),
    );
  }
}

class _CalGrid extends StatelessWidget {
  final List<int?> cells;
  final int selDay;
  final Color myColor;
  final _C cs;
  final ValueChanged<int> onDayTap;
  const _CalGrid({required this.cells, required this.selDay, required this.myColor, required this.cs, required this.onDayTap});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var row = 0; row < 6; row++) {
      final week = cells.sublist(row * 7, row * 7 + 7);
      if (week.every((d) => d == null)) continue;
      rows.add(_EventBar(week: week, myColor: myColor, cs: cs));
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: List.generate(7, (col) {
          final d = week[col];
          if (d == null) return const Expanded(child: SizedBox(height: 46));
          return Expanded(child: GestureDetector(
            onTap: () => onDayTap(d),
            child: _DayCell(d: d, col: col, selDay: selDay, myColor: myColor, cs: cs),
          ));
        })),
      ));
    }
    return Column(children: rows);
  }
}

class _EventBar extends StatelessWidget {
  final List<int?> week;
  final Color myColor;
  final _C cs;
  const _EventBar({required this.week, required this.myColor, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        height: 18,
        child: Row(children: List.generate(7, (col) {
          final d = week[col];
          final inBar = d != null && d >= _kBarStart && d <= _kBarEnd;
          if (!inBar) return const Expanded(child: SizedBox());
          final isFirst = col == 0 || (week[col - 1] ?? 0) < _kBarStart;
          final isLast  = col == 6 || (week[col + 1] ?? 32) > _kBarEnd;
          return Expanded(child: Container(
            height: 14,
            margin: EdgeInsets.only(top: 2, bottom: 2, left: isFirst ? 1 : 0, right: isLast ? 1 : 0),
            decoration: BoxDecoration(
              color: myColor.withOpacity(cs.dark ? 0.72 : 0.85),
              borderRadius: BorderRadius.only(
                topLeft:     isFirst ? const Radius.circular(5) : Radius.zero,
                bottomLeft:  isFirst ? const Radius.circular(5) : Radius.zero,
                topRight:    isLast  ? const Radius.circular(5) : Radius.zero,
                bottomRight: isLast  ? const Radius.circular(5) : Radius.zero,
              ),
            ),
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.only(left: isFirst ? 5 : 0),
            child: isFirst ? const Text('잠실 직관',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
              overflow: TextOverflow.clip, softWrap: false) : null,
          ));
        })),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final int d, col, selDay;
  final Color myColor;
  final _C cs;
  const _DayCell({required this.d, required this.col, required this.selDay, required this.myColor, required this.cs});

  @override
  Widget build(BuildContext context) {
    final isSel   = d == selDay;
    final isToday = d == _kToday;
    final visit   = _kVisit[d];
    final hasDots = _kDots.containsKey(d);

    final bg = isSel   ? cs.ink
             : isToday ? myColor.withOpacity(cs.dark ? 0.25 : 0.12)
             : Colors.transparent;
    final border = visit != null && !isSel
        ? (visit ? const Color(0xFF2563EB).withOpacity(0.5) : SemColor.live.withOpacity(0.45))
        : Colors.transparent;
    final numColor = isSel   ? Colors.white
                   : isToday ? myColor
                   : col == 0 ? SemColor.live
                   : col == 6 ? const Color(0xFF2563EB)
                   : cs.ink2;

    return Container(
      height: 46, margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('$d', style: TextStyle(
          fontSize: Typo.caption,
          fontWeight: isSel || isToday ? Typo.extra : Typo.medium,
          color: numColor,
        )),
        if (hasDots) ...[
          const SizedBox(height: 3),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(
            (_kDots[d]! > 3 ? 3 : _kDots[d]!),
            (_) => Container(
              width: 4, height: 4, margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(shape: BoxShape.circle,
                color: isSel ? Colors.white.withOpacity(0.65) : cs.sub),
            ),
          )),
        ],
      ]),
    );
  }
}

class _DayDetail extends StatelessWidget {
  final int selDay;
  final bool myTeamOnly;
  final _C cs;
  const _DayDetail({required this.selDay, required this.myTeamOnly, required this.cs});

  @override
  Widget build(BuildContext context) {
    final games = (_kGames[selDay] ?? [])
        .where((g) => !myTeamOnly || g.mineCode == _kMyTeam).toList();
    final personal = _kPersonal[selDay] ?? [];

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (games.isNotEmpty) ...[
          _SectionLabel(label: 'KBO 경기', cs: cs),
          const SizedBox(height: 10),
          ...games.map((g) => _GameTile(game: g, cs: cs)),
        ],
        if (personal.isNotEmpty) ...[
          const SizedBox(height: 14),
          _SectionLabel(label: '개인 일정', cs: cs),
          const SizedBox(height: 10),
          ...personal.map((e) => _PersonalTile(event: e, cs: cs)),
        ],
        if (games.isEmpty && personal.isEmpty)
          Center(child: Padding(
            padding: const EdgeInsets.only(top: 36),
            child: Text('$selDay일 경기 및 일정 없음', style: TextStyle(fontSize: Typo.body, color: cs.sub)),
          )),
      ]),
    );
  }
}

// ── 게임 타일 ─────────────────────────────────────────────────────────────────

class _GameTile extends StatelessWidget {
  final KboGame game;
  final _C cs;
  const _GameTile({required this.game, required this.cs});

  @override
  Widget build(BuildContext context) {
    final tc      = game.mineCode != null ? teamColor(game.mineCode) : null;
    final isLive  = game.status == GameStatus.live;
    final isDone  = game.status == GameStatus.done;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tc != null ? tc.withOpacity(cs.dark ? 0.12 : 0.06) : cs.paper,
        border: Border.all(color: tc != null ? tc.withOpacity(cs.dark ? 0.45 : 0.28) : cs.line),
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: tc == null && !cs.dark
            ? [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 2, offset: const Offset(0,1))]
            : null,
      ),
      child: Column(children: [
        // 헤더
        Row(children: [
          _Capsule(child: Row(children: [
            Container(width:5, height:5, decoration: BoxDecoration(shape:BoxShape.circle, color:cs.line2)),
            const SizedBox(width:5),
            Text(game.stadium, style: TextStyle(fontSize:10, fontWeight:Typo.medium, color:cs.ink3)),
          ]), bg: cs.paper2),
          const Spacer(),
          if (tc != null) ...[
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal:7, vertical:3),
              decoration: BoxDecoration(color:tc, borderRadius: BorderRadius.circular(Radii.xs)),
              child: const Text('마이팀', style: TextStyle(fontSize:9, fontWeight:FontWeight.w800, color:Colors.white)),
            ),
          ],
          _StatusBadge(isLive: isLive, isDone: isDone, time: game.time, cs: cs),
        ]),
        const SizedBox(height: 12),
        // 팀 vs 스코어
        Row(children: [
          Expanded(child: _TeamCol(code: game.homeCode, name: game.homeName, role: '홈', cs: cs)),
          SizedBox(width:80, child: Center(child: isLive || isDone
            ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${game.hs}', style: TextStyle(fontSize:28, fontWeight:Typo.extra, color:cs.ink)),
                Padding(padding: const EdgeInsets.symmetric(horizontal:9),
                  child: Text(':', style: TextStyle(fontSize:24, fontWeight:FontWeight.w300, color:cs.line2))),
                Text('${game.as_}', style: TextStyle(fontSize:28, fontWeight:Typo.extra, color:cs.ink)),
              ])
            : Text(game.time ?? '예정', style: TextStyle(fontSize:18, fontWeight:Typo.extra, color:cs.ink3)),
          )),
          Expanded(child: _TeamCol(code: game.awayCode, name: game.awayName, role: '원정', cs: cs)),
        ]),
        // 투수
        if (game.homePitcher != null) ...[
          const SizedBox(height:12),
          Divider(height:1, color: tc != null ? tc.withOpacity(0.15) : cs.line),
          const SizedBox(height:10),
          Row(children: [
            Expanded(child: Center(child: Text(game.homePitcher!, style: TextStyle(fontSize:Typo.caption, fontWeight:Typo.bold, color:cs.ink3)))),
            Text(isDone ? '승·패' : '선발', style: TextStyle(fontSize:9, color:cs.sub)),
            Expanded(child: Center(child: Text(game.awayPitcher ?? '', style: TextStyle(fontSize:Typo.caption, fontWeight:Typo.bold, color:cs.ink3)))),
          ]),
        ],
      ]),
    );
  }
}

class _TeamCol extends StatelessWidget {
  final String code, name, role;
  final _C cs;
  const _TeamCol({required this.code, required this.name, required this.role, required this.cs});
  @override
  Widget build(BuildContext context) => Column(children: [
    TeamLogo(teamCode: code, size: 44),
    const SizedBox(height: 7),
    Text(name, style: TextStyle(fontSize: 14, fontWeight: Typo.extra, color: cs.ink)),
    const SizedBox(height: 3),
    Text(role, style: TextStyle(fontSize: 10, color: cs.sub)),
  ]);
}

class _StatusBadge extends StatelessWidget {
  final bool isLive, isDone;
  final String? time;
  final _C cs;
  const _StatusBadge({required this.isLive, required this.isDone, this.time, required this.cs});
  @override
  Widget build(BuildContext context) {
    if (isLive) return _Capsule(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width:5, height:5, margin: const EdgeInsets.only(right:5),
          decoration: BoxDecoration(shape:BoxShape.circle, color:SemColor.live)),
        const Text('LIVE', style: TextStyle(fontSize:10, fontWeight:FontWeight.w800, color:SemColor.live)),
      ]),
      bg: SemColor.live.withOpacity(0.1),
    );
    return _Capsule(
      child: Text(isDone ? '종료' : (time ?? '예정'),
        style: TextStyle(fontSize:10, fontWeight:Typo.bold,
          color: isDone ? cs.ink3 : const Color(0xFF2563EB))),
      bg: cs.paper2,
    );
  }
}

// ── 개인 일정 타일 ────────────────────────────────────────────────────────────

class _PersonalTile extends StatelessWidget {
  final PersonalEvent event;
  final _C cs;
  const _PersonalTile({required this.event, required this.cs});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: cs.paper, border: Border.all(color: event.color.withOpacity(0.28)),
      borderRadius: BorderRadius.circular(Radii.md),
    ),
    child: Row(children: [
      Container(
        width: 4,
        decoration: BoxDecoration(
          color: event.color,
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(Radii.md)),
        ),
      ),
      Expanded(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal:14, vertical:11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(event.title, style: TextStyle(fontSize:Typo.body, fontWeight:Typo.bold, color:cs.ink)),
          if (event.desc != null) ...[
            const SizedBox(height:4),
            Text(event.desc!, style: TextStyle(fontSize:Typo.caption, color:cs.ink3, height:1.4)),
          ],
        ]),
      )),
      IconButton(icon: Icon(Icons.close, size:16, color:cs.sub), onPressed: () {}, padding: EdgeInsets.zero),
      const SizedBox(width:4),
    ]),
  );
}

// ── 공통 소형 위젯 ────────────────────────────────────────────────────────────

class _Btn32 extends StatelessWidget {
  final Widget child;
  final Color border;
  final Color? bg;
  final VoidCallback onTap;
  const _Btn32({required this.child, required this.border, this.bg, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width:32, height:32,
      decoration: BoxDecoration(
        color: bg ?? Colors.transparent, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: child,
    ),
  );
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final _C cs;
  const _NavBtn({required this.icon, required this.cs});
  @override
  Widget build(BuildContext context) => Container(
    width:34, height:34,
    decoration: BoxDecoration(border: Border.all(color: cs.line2), borderRadius: BorderRadius.circular(10)),
    child: Icon(icon, color: cs.ink3, size:20),
  );
}

class _Capsule extends StatelessWidget {
  final Widget child;
  final Color bg;
  const _Capsule({required this.child, required this.bg});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal:9, vertical:5),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.pill)),
    child: child,
  );
}

class _StatChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatChip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal:8, vertical:3),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(Radii.xs)),
    child: Text(label, style: TextStyle(fontSize:10, fontWeight:Typo.medium, color:color)),
  );
}

class _TextPill extends StatelessWidget {
  final String label;
  final Color color, border;
  const _TextPill({required this.label, required this.color, required this.border});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal:10, vertical:6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(Radii.pill),
      border: Border.all(color: border.withOpacity(0.4)),
    ),
    child: Text(label, style: TextStyle(fontSize:Typo.caption, fontWeight:Typo.medium, color:color)),
  );
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final _C cs;
  const _SectionLabel({required this.label, required this.cs});
  @override
  Widget build(BuildContext context) => Text(label,
    style: TextStyle(fontSize:10, fontWeight:Typo.bold, color:cs.sub, letterSpacing:0.8));
}
