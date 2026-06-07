// my_page_screen.dart — Option A 디자인 시스템 반영 (2026-06)
import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import '../../utils/team_theme.dart';

// ── 샘플 / 목업 모델 (실제 앱에서는 API/Provider로 교체) ─────────────────────

class _VisitRecord {
  final String result, date, home, away, memo;
  final int hs, as_;
  const _VisitRecord({required this.result, required this.date, required this.home,
      required this.away, required this.hs, required this.as_, this.memo = ''});
}

class _MyPost {
  final String title, category, date;
  final int likes, comments;
  const _MyPost({required this.title, required this.category,
      required this.likes, required this.comments, required this.date});
}

const _kMyTeamCode = 'LG';
const _kMyTeamName = 'LG 트윈스';
const _kMyTeamRank = 2;
const _kMyTeamWins = 42;
const _kMyTeamLosses = 28;
const _kMyTeamGb = 3.0;
const _kMyTeamForm = ['W','L','W','W','L'];

const _kFavPlayers = [
  {'name':'김도영',  'team':'KIA',  'position':'3루수', 'code':'HT'},
  {'name':'문동주',  'team':'한화', 'position':'투수',  'code':'HH'},
  {'name':'박해민',  'team':'LG',  'position':'외야수', 'code':'LG'},
  {'name':'구자욱',  'team':'삼성', 'position':'외야수', 'code':'SS'},
  {'name':'오스틴',  'team':'LG',  'position':'1루수', 'code':'LG'},
  {'name':'임찬규',  'team':'LG',  'position':'투수',  'code':'LG'},
];

const _kVisits = [
  _VisitRecord(result:'win',  date:'2026.06.07', home:'LG', away:'KIA', hs:5, as_:3, memo:'7회 역전 직관'),
  _VisitRecord(result:'win',  date:'2026.05.22', home:'LG', away:'두산', hs:7, as_:2, memo:'친구랑 잠실'),
  _VisitRecord(result:'loss', date:'2026.05.10', home:'LG', away:'KIA', hs:3, as_:5),
];

const _kMyPosts = [
  _MyPost(title:'오늘 7회말 역전 직관 진짜 소름이었다', category:'자유', likes:42, comments:8,  date:'2026.06.07'),
  _MyPost(title:'LG 불펜 이번 시즌 진짜 미쳤다',         category:'분석', likes:28, comments:14, date:'2026.05.30'),
  _MyPost(title:'임찬규 선발 고정 해주세요',               category:'자유', likes:15, comments:5,  date:'2026.05.18'),
];

// ── 알림 설정 모델 ────────────────────────────────────────────────────────────

class _NotifItem {
  final String key, label, desc;
  const _NotifItem({required this.key, required this.label, required this.desc});
}

class _NotifCat {
  final String icon, label;
  final List<_NotifItem> items;
  const _NotifCat({required this.icon, required this.label, required this.items});
}

const _kNotifCats = [
  _NotifCat(icon:'⚾', label:'경기 알림', items:[
    _NotifItem(key:'gameStart',   label:'경기 시작',  desc:'선발 발표·경기 취소 알림 포함'),
    _NotifItem(key:'scoreChange', label:'득점 변경',  desc:'역전·연장전 포함'),
    _NotifItem(key:'gameEnd',     label:'경기 종료',  desc:'경기 결과 요약 포함'),
    _NotifItem(key:'walkoff',     label:'끝내기 승리', desc:'끝내기 득점으로 승리 시'),
    _NotifItem(key:'myTeamOnly',  label:'마이팀만',   desc:'즐겨찾기 팀 경기에만 알림'),
  ]),
  _NotifCat(icon:'📊', label:'팀 알림', items:[
    _NotifItem(key:'streak',      label:'연승/연패',  desc:'마이팀 5연승·연패 이상 시'),
    _NotifItem(key:'rankChange',  label:'순위 변동',  desc:'마이팀 순위 변동·동률 1위 달성 시'),
    _NotifItem(key:'roster',      label:'1군 등록말소', desc:'마이팀 선수 등록 변경 시'),
  ]),
  _NotifCat(icon:'🏃', label:'선수 알림', items:[
    _NotifItem(key:'milestone',   label:'통산 대기록', desc:'즐겨찾기 선수 기록 달성 시'),
    _NotifItem(key:'playerDaily', label:'오늘의 활약', desc:'즐겨찾기 선수 매일 결과 요약'),
    _NotifItem(key:'playerNews',  label:'선수 뉴스',  desc:'트레이드·은퇴·FA·부상·시상'),
  ]),
  _NotifCat(icon:'💬', label:'커뮤니티', items:[
    _NotifItem(key:'comment', label:'댓글', desc:'내 글에 댓글이 달릴 때'),
  ]),
];

// ── 메인 화면 ─────────────────────────────────────────────────────────────────

class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});
  @override State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  final Map<String, bool> _notifs = {
    for (final cat in _kNotifCats)
      for (final item in cat.items) item.key: true,
  };
  final Set<int> _expanded = {};

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = _C(context);
    final myColor = teamColor(_kMyTeamCode);

    final wins   = _kVisits.where((v) => v.result == 'win').length;
    final losses = _kVisits.where((v) => v.result == 'loss').length;
    final total  = _kVisits.length;
    final winPct = total > 0 ? (wins / total * 100).round() : 0;

    return Scaffold(
      backgroundColor: cs.bg,
      body: SafeArea(
        child: Column(children: [
          _AppBar(cs: cs),
          Expanded(child: ListView(padding: EdgeInsets.zero, children: [
            _buildProfile(cs),
            _buildMyTeam(cs, myColor),
            _buildFavPlayers(cs),
            _buildVisitRecord(cs, wins, losses, winPct),
            _buildMyPosts(cs),
            _buildNotifSettings(cs),
            const SizedBox(height: 8),
            Center(child: TextButton(
              onPressed: () {},
              child: Text('회원탈퇴', style: TextStyle(color: SemColor.live.withOpacity(0.7), fontSize: 12)),
            )),
            const SizedBox(height: 24),
          ])),
        ]),
      ),
    );
  }

  // ── 프로필 ────────────────────────────────────────────────────────────────
  Widget _buildProfile(_C cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDeco(cs),
        child: Row(children: [
          Stack(children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.paper2,
                border: Border.all(color: cs.line2, width: 2),
              ),
              child: Icon(Icons.person_outline, size: 28, color: cs.sub),
            ),
            Positioned(
              bottom: 0, right: 0,
              child: Container(
                width: 20, height: 20,
                decoration: BoxDecoration(
                  color: cs.ink, shape: BoxShape.circle,
                  border: Border.all(color: cs.paper, width: 2),
                ),
                child: Icon(Icons.camera_alt_outlined, size: 10,
                    color: cs.dark ? const Color(0xFF0F0F12) : Colors.white),
              ),
            ),
          ]),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('야구사랑', style: TextStyle(fontSize: 18, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.5)),
              const SizedBox(width: 7),
              Icon(Icons.edit_outlined, size: 14, color: cs.sub),
            ]),
            const SizedBox(height: 5),
            Text('yaball@email.com', style: TextStyle(fontSize: 12, color: cs.ink3)),
            const SizedBox(height: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.check, size: 10, color: Color(0xFF22C55E)),
                const SizedBox(width: 4),
                const Text('이메일 인증 완료',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF22C55E))),
              ]),
            ),
          ])),
        ]),
      ),
    );
  }

  // ── 마이팀 ────────────────────────────────────────────────────────────────
  Widget _buildMyTeam(_C cs, Color myColor) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionLabel(label: '마이팀', cs: cs, action: '팀 상세 →'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: _cardDeco(cs),
          child: Row(children: [
            Stack(children: [
              TeamLogo(teamCode: _kMyTeamCode, size: 48),
              Positioned(
                top: -4, right: -4,
                child: Container(
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                    color: myColor, shape: BoxShape.circle,
                    border: Border.all(color: cs.paper, width: 1.5),
                  ),
                  child: const Center(child: Text('★', style: TextStyle(fontSize: 9, color: Colors.white, height: 1))),
                ),
              ),
            ]),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(_kMyTeamName, style: TextStyle(fontSize: 16, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.4)),
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: myColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text('$_kMyTeamRank위',
                      style: TextStyle(fontSize: 11, fontWeight: Typo.bold, color: myColor)),
                ),
              ]),
              const SizedBox(height: 5),
              Text('$_kMyTeamWins승 $_kMyTeamLosses패 · 승률 ${(_kMyTeamWins / (_kMyTeamWins + _kMyTeamLosses) * 100).toStringAsFixed(1)}% · $_kMyTeamGb GB',
                  style: TextStyle(fontSize: 12, color: cs.ink3)),
            ])),
            Column(children: [
              Row(children: _kMyTeamForm.map((r) => Container(
                width: 16, height: 16, margin: const EdgeInsets.only(left: 2),
                decoration: BoxDecoration(
                  color: r == 'W' ? myColor : cs.track,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(child: Text(r,
                    style: TextStyle(fontSize: 8, fontWeight: Typo.extra,
                        color: r == 'W' ? (cs.dark ? const Color(0xFF0F0F12) : Colors.white) : cs.sub))),
              )).toList()),
              const SizedBox(height: 4),
              Text('최근 5경기', style: TextStyle(fontSize: 9, color: cs.sub)),
            ]),
          ]),
        ),
      ),
    ]);
  }

  // ── 즐겨찾기 선수 ─────────────────────────────────────────────────────────
  Widget _buildFavPlayers(_C cs) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionLabel(label: '즐겨찾기 선수', cs: cs, action: '${_kFavPlayers.length}명 전체'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Container(
          decoration: _cardDeco(cs),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(14),
            child: Row(children: _kFavPlayers.map((p) {
              final c = teamColor(p['code']!);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: c.withOpacity(cs.dark ? 0.18 : 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.withOpacity(0.25)),
                    ),
                    child: Center(child: TeamLogo(teamCode: p['code']!, size: 26)),
                  ),
                  const SizedBox(height: 6),
                  Text(p['name']!, style: TextStyle(fontSize: 11, fontWeight: Typo.bold, color: cs.ink)),
                  const SizedBox(height: 3),
                  Text(p['position']!, style: TextStyle(fontSize: 9, color: cs.sub)),
                ]),
              );
            }).toList()),
          ),
        ),
      ),
    ]);
  }

  // ── 직관 기록 ─────────────────────────────────────────────────────────────
  Widget _buildVisitRecord(_C cs, int wins, int losses, int winPct) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionLabel(label: '직관 기록', cs: cs),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Container(
          decoration: _cardDeco(cs),
          child: Column(children: [
            // 요약
            IntrinsicHeight(
              child: Row(children: [
                _VisitStat(value: '$wins',      label: '승',     color: const Color(0xFF2563EB), cs: cs),
                VerticalDivider(width: 1, color: cs.line),
                _VisitStat(value: '$losses',    label: '패',     color: SemColor.live,           cs: cs),
                VerticalDivider(width: 1, color: cs.line),
                _VisitStat(value: '0',          label: '무',     color: cs.sub,                  cs: cs),
                VerticalDivider(width: 1, color: cs.line),
                _VisitStat(value: '$winPct%',   label: '직관승률', color: teamColor(_kMyTeamCode), cs: cs),
              ]),
            ),
            Divider(height: 1, color: cs.line),
            // 리스트
            ..._kVisits.asMap().entries.map((e) => _VisitTile(v: e.value, cs: cs, last: e.key == _kVisits.length - 1)),
          ]),
        ),
      ),
    ]);
  }

  // ── 내 게시글 ─────────────────────────────────────────────────────────────
  Widget _buildMyPosts(_C cs) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionLabel(label: '내 게시글', cs: cs, action: '전체 보기'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Container(
          decoration: _cardDeco(cs),
          child: Column(children: _kMyPosts.asMap().entries.map((e) {
            final p = e.value;
            final last = e.key == _kMyPosts.length - 1;
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title, style: TextStyle(fontSize: 12, fontWeight: Typo.bold, color: cs.ink, height: 1.45)),
                const SizedBox(height: 6),
                Row(children: [
                  _SmallChip(label: p.category, color: cs.ink3, bg: cs.paper2, cs: cs),
                  const SizedBox(width: 8),
                  Text('♡ ${p.likes}', style: TextStyle(fontSize: 10, color: cs.sub)),
                  const SizedBox(width: 8),
                  Text('💬 ${p.comments}', style: TextStyle(fontSize: 10, color: cs.sub)),
                  const Spacer(),
                  Text(p.date, style: TextStyle(fontSize: 10, color: cs.sub)),
                ]),
              ]),
            );
          }).toList()),
        ),
      ),
    ]);
  }

  // ── 알림 설정 ─────────────────────────────────────────────────────────────
  Widget _buildNotifSettings(_C cs) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionLabel(label: '알림 설정', cs: cs),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Container(
          decoration: _cardDeco(cs),
          child: Column(children: [
            ..._kNotifCats.asMap().entries.map((e) {
              final i = e.key;
              final cat = e.value;
              final isExpanded = _expanded.contains(i);
              final isLast = i == _kNotifCats.length - 1;
              return Column(children: [
                GestureDetector(
                  onTap: () => setState(() => isExpanded ? _expanded.remove(i) : _expanded.add(i)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      border: (!isLast || isExpanded)
                          ? Border(bottom: BorderSide(color: cs.line)) : null,
                    ),
                    child: Row(children: [
                      Text(cat.icon, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 10),
                      Text(cat.label, style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: cs.ink)),
                      const Spacer(),
                      AnimatedRotation(
                        turns: isExpanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(Icons.chevron_right, size: 16, color: cs.sub),
                      ),
                    ]),
                  ),
                ),
                if (isExpanded)
                  ...cat.items.asMap().entries.map((ie) {
                    final ii = ie.key;
                    final item = ie.value;
                    final itemLast = ii == cat.items.length - 1;
                    return Container(
                      padding: const EdgeInsets.only(left: 44, right: 16, top: 11, bottom: 11),
                      decoration: BoxDecoration(
                        border: (!itemLast || !isLast)
                            ? Border(bottom: BorderSide(color: cs.line)) : null,
                      ),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item.label, style: TextStyle(fontSize: 13, fontWeight: Typo.medium, color: cs.ink)),
                          const SizedBox(height: 3),
                          Text(item.desc, style: TextStyle(fontSize: 10, color: cs.sub, height: 1.4)),
                        ])),
                        const SizedBox(width: 12),
                        _AppToggle(
                          on: _notifs[item.key] ?? true,
                          color: teamColor(_kMyTeamCode),
                          track: cs.track,
                          onChanged: (v) => setState(() => _notifs[item.key] = v),
                        ),
                      ]),
                    );
                  }),
              ]);
            }),
            // 다크모드
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.line))),
              child: Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: cs.paper2, borderRadius: BorderRadius.circular(9)),
                  child: Center(child: Text(cs.dark ? '☀️' : '🌙', style: const TextStyle(fontSize: 15))),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('다크 모드', style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: cs.ink))),
                // 실제 앱에서는 ThemeProvider와 연결
                _AppToggle(on: cs.dark, color: teamColor(_kMyTeamCode), track: cs.track, onChanged: (_) {}),
              ]),
            ),
          ]),
        ),
      ),
    ]);
  }

  BoxDecoration _cardDeco(_C cs) => BoxDecoration(
    color: cs.paper, border: Border.all(color: cs.line),
    borderRadius: BorderRadius.circular(Radii.lg),
    boxShadow: cs.dark ? null : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 3, offset: const Offset(0, 1))],
  );
}

// ── AppBar ────────────────────────────────────────────────────────────────────
class _AppBar extends StatelessWidget {
  final _C cs;
  const _AppBar({required this.cs});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
    decoration: BoxDecoration(color: cs.paper, border: Border(bottom: BorderSide(color: cs.line))),
    child: Row(children: [
      Text('마이페이지', style: TextStyle(fontSize: Typo.h2, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.5)),
      const Spacer(),
      _Btn32(border: cs.line2, onTap: () {},
        child: Icon(Icons.logout_outlined, size: 17, color: cs.ink3)),
    ]),
  );
}

// ── 공통 소형 위젯 ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  final String? action;
  final _C cs;
  const _SectionLabel({required this.label, required this.cs, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
    child: Row(children: [
      Text(label, style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub, letterSpacing: 0.8)),
      if (action != null) ...[
        const Spacer(),
        GestureDetector(
          onTap: () {},
          child: Text(action!, style: TextStyle(fontSize: 11, color: cs.ink3)),
        ),
      ],
    ]),
  );
}

class _VisitStat extends StatelessWidget {
  final String value, label;
  final Color color;
  final _C cs;
  const _VisitStat({required this.value, required this.label, required this.color, required this.cs});
  @override
  Widget build(BuildContext context) => Expanded(child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Column(children: [
      Text(value, style: TextStyle(fontSize: 18, fontWeight: Typo.extra, color: color)),
      const SizedBox(height: 5),
      Text(label, style: TextStyle(fontSize: 10, color: cs.sub)),
    ]),
  ));
}

class _VisitTile extends StatelessWidget {
  final _VisitRecord v;
  final _C cs;
  final bool last;
  const _VisitTile({required this.v, required this.cs, required this.last});
  @override
  Widget build(BuildContext context) {
    final c = v.result == 'win' ? const Color(0xFF2563EB) : v.result == 'loss' ? SemColor.live : cs.sub;
    final lb = v.result == 'win' ? '승' : v.result == 'loss' ? '패' : '무';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
      child: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: c.withOpacity(0.12), shape: BoxShape.circle),
          child: Center(child: Text(lb, style: TextStyle(fontSize: 12, fontWeight: Typo.extra, color: c))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${v.away} ${v.as_} : ${v.hs} ${v.home}',
              style: TextStyle(fontSize: 12, fontWeight: Typo.bold, color: cs.ink, height: 1.4)),
          if (v.memo.isNotEmpty)
            Text(v.memo, style: TextStyle(fontSize: 10, color: cs.sub)),
        ])),
        Text(v.date, style: TextStyle(fontSize: 10, color: cs.sub)),
      ]),
    );
  }
}

class _SmallChip extends StatelessWidget {
  final String label;
  final Color color, bg;
  final _C cs;
  const _SmallChip({required this.label, required this.color, required this.bg, required this.cs});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.xs), border: Border.all(color: cs.line)),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: Typo.medium, color: color)),
  );
}

class _AppToggle extends StatelessWidget {
  final bool on;
  final Color color, track;
  final ValueChanged<bool> onChanged;
  const _AppToggle({required this.on, required this.color, required this.track, required this.onChanged});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onChanged(!on),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 40, height: 24,
      decoration: BoxDecoration(color: on ? color : track, borderRadius: BorderRadius.circular(12)),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 20, height: 20, margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0,1))]),
        ),
      ),
    ),
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
