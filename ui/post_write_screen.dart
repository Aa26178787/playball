// post_write_screen.dart — 게시글 작성 (Option A 디자인 시스템)
import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import '../../utils/team_theme.dart';

const _kTeams = [
  ['LG','LG'],['KT','KT'],['SK','SSG'],['NC','NC'],['OB','두산'],
  ['HT','KIA'],['LT','롯데'],['SS','삼성'],['HH','한화'],['WO','키움'],
];
const _kCategories = ['자유', '분석', '유머', '응원'];

class PostWriteScreen extends StatefulWidget {
  const PostWriteScreen({super.key});
  @override State<PostWriteScreen> createState() => _PostWriteScreenState();
}

class _PostWriteScreenState extends State<PostWriteScreen> {
  String _selTeam = 'LG';
  int    _selCat  = 0;

  final _titleCtrl = TextEditingController();
  final _bodyCtrl  = TextEditingController();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Color get _tc => teamColor(_selTeam);

  @override
  Widget build(BuildContext context) {
    final cs = _C(context);
    return Scaffold(
      backgroundColor: cs.bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(child: Column(children: [
        // AppBar
        Container(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          decoration: BoxDecoration(color: cs.paper, border: Border(bottom: BorderSide(color: cs.line))),
          child: Row(children: [
            _Btn32(onTap: () => Navigator.maybePop(context), border: cs.line2,
              child: Icon(Icons.chevron_left, size: 20, color: cs.ink2)),
            const SizedBox(width: 10),
            Text('글 작성', style: TextStyle(fontSize: 18, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.4)),
            const Spacer(),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: _tc,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
                textStyle: TextStyle(fontSize: 13, fontWeight: Typo.extra),
              ),
              child: const Text('완료'),
            ),
          ]),
        ),
        // Content
        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 팀 선택
            _SectionLabel(label: '팀 선택', cs: cs),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                itemCount: _kTeams.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final code = _kTeams[i][0], name = _kTeams[i][1];
                  final act = _selTeam == code;
                  final c = teamColor(code);
                  return GestureDetector(
                    onTap: () => setState(() => _selTeam = code),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                      decoration: BoxDecoration(
                        color: act ? c.withOpacity(cs.dark ? 0.22 : 0.10) : cs.paper,
                        borderRadius: BorderRadius.circular(Radii.pill),
                        border: Border.all(color: act ? c.withOpacity(0.45) : cs.line2),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        TeamLogo(teamCode: code, size: 15),
                        const SizedBox(width: 5),
                        Text(name, style: TextStyle(fontSize: 12,
                          fontWeight: act ? Typo.bold : Typo.medium,
                          color: act ? c : cs.ink3)),
                      ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            // 카테고리
            _SectionLabel(label: '카테고리', cs: cs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Wrap(spacing: 6, runSpacing: 6, children: List.generate(_kCategories.length, (i) {
                final act = i == _selCat;
                return GestureDetector(
                  onTap: () => setState(() => _selCat = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: act ? cs.ink : cs.paper,
                      borderRadius: BorderRadius.circular(Radii.pill),
                      border: Border.all(color: act ? cs.ink : cs.line2),
                    ),
                    child: Text(_kCategories[i], style: TextStyle(
                      fontSize: 12, fontWeight: act ? Typo.bold : Typo.medium,
                      color: act ? (cs.dark ? const Color(0xFF0F0F12) : Colors.white) : cs.ink3,
                    )),
                  ),
                );
              })),
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: cs.line),
            const SizedBox(height: 12),
            // 제목
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: TextField(
                controller: _titleCtrl,
                maxLength: 60,
                style: TextStyle(fontSize: 18, fontWeight: Typo.extra, color: cs.ink),
                cursorColor: _tc,
                decoration: InputDecoration(
                  hintText: '제목을 입력하세요',
                  hintStyle: TextStyle(fontSize: 18, fontWeight: Typo.extra, color: cs.sub),
                  border: InputBorder.none,
                  counterStyle: TextStyle(fontSize: 10, color: cs.sub),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            Divider(height: 1, color: cs.line),
            const SizedBox(height: 12),
            // 본문
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: TextField(
                controller: _bodyCtrl,
                maxLines: null,
                minLines: 8,
                style: TextStyle(fontSize: 14, color: cs.ink, height: 1.7),
                cursorColor: _tc,
                decoration: InputDecoration(
                  hintText: '${kTeamDisplayNames[_selTeam] ?? ''} 팬 여러분과 이야기 나눠보세요…',
                  hintStyle: TextStyle(fontSize: 14, color: cs.sub, height: 1.7),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            // 이미지 추가
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  height: 88,
                  decoration: BoxDecoration(
                    color: cs.paper2,
                    border: Border.all(color: cs.line2, width: 1.5,
                        style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_photo_alternate_outlined, size: 20, color: cs.sub),
                    const SizedBox(width: 8),
                    Text('이미지 추가', style: TextStyle(fontSize: 12, color: cs.sub)),
                  ]),
                ),
              ),
            ),
          ]),
        )),
        // 하단 툴바
        Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
          decoration: BoxDecoration(color: cs.paper, border: Border(top: BorderSide(color: cs.line))),
          child: Row(children: [
            _ToolBtn(icon: Icons.image_outlined, cs: cs),
            const SizedBox(width: 4),
            _ToolBtn(icon: Icons.link, cs: cs),
            const SizedBox(width: 4),
            _ToolBtn(icon: Icons.alternate_email, cs: cs),
            const Spacer(),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _bodyCtrl,
              builder: (_, v, __) => Text('${v.text.length} 자',
                style: TextStyle(fontSize: Typo.caption, color: v.text.isNotEmpty ? cs.ink3 : cs.sub)),
            ),
          ]),
        ),
      ])),
    );
  }
}

// ── 소형 위젯 ─────────────────────────────────────────────────────────────────

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final _C cs;
  const _ToolBtn({required this.icon, required this.cs});
  @override
  Widget build(BuildContext context) => Container(
    width: 36, height: 36,
    decoration: BoxDecoration(border: Border.all(color: cs.line), borderRadius: BorderRadius.circular(9)),
    child: Icon(icon, size: 18, color: cs.ink3),
  );
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final _C cs;
  const _SectionLabel({required this.label, required this.cs});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub, letterSpacing: 0.8)),
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
