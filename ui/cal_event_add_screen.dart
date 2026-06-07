// cal_event_add_screen.dart — 캘린더 일정 추가 (Option A 디자인 시스템)
import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';

const _kEventColors = [
  Color(0xFFC30452), Color(0xFF2563EB), Color(0xFF16A34A),
  Color(0xFFD97706), Color(0xFF7C3AED), Color(0xFF0891B2),
];
const _kColorLabels = ['LG 레드','블루','그린','오렌지','퍼플','틸'];

class CalEventAddScreen extends StatefulWidget {
  /// 일정을 추가할 날짜 (기본값: 오늘)
  final DateTime date;
  const CalEventAddScreen({super.key, DateTime? date})
      : date = date ?? const DateTime(2026, 6, 7);

  @override State<CalEventAddScreen> createState() => _CalEventAddScreenState();
}

class _CalEventAddScreenState extends State<CalEventAddScreen> {
  final _titleCtrl = TextEditingController();
  final _memoCtrl  = TextEditingController();

  TimeOfDay _start = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _end   = const TimeOfDay(hour: 22, minute: 0);
  int  _colorIdx   = 1; // 블루 기본
  bool _linkGame   = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  Color get _accent => _kEventColors[_colorIdx];
  String get _timeStr => '${widget.date.year}년 ${widget.date.month}월 ${widget.date.day}일';

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';

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
            _Btn32(border: cs.line2, onTap: () => Navigator.maybePop(context),
              child: Icon(Icons.chevron_left, size: 20, color: cs.ink2)),
            const SizedBox(width: 10),
            Text('일정 추가', style: TextStyle(fontSize: 18, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.4)),
            const Spacer(),
            ElevatedButton(
              onPressed: () => Navigator.maybePop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
                textStyle: TextStyle(fontSize: 13, fontWeight: Typo.extra),
              ),
              child: const Text('저장'),
            ),
          ]),
        ),
        // Content
        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 날짜 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(cs.dark ? 0.18 : 0.07),
                  border: Border.all(color: _accent.withOpacity(cs.dark ? 0.40 : 0.22)),
                  borderRadius: BorderRadius.circular(Radii.lg),
                ),
                child: Row(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: _accent.withOpacity(0.35), blurRadius: 8, offset: const Offset(0,2))],
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('${widget.date.month}월',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white70)),
                      const SizedBox(height: 2),
                      Text('${widget.date.day}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                    ]),
                  ),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_timeStr, style: TextStyle(fontSize: 16, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.3)),
                    const SizedBox(height: 4),
                    Text('일요일 · LG vs KIA 경기일', style: TextStyle(fontSize: 12, color: cs.ink3)),
                  ]),
                ]),
              ),
            ),
            // 제목
            _FormLabel(label: '제목', cs: cs),
            _InputBox(cs: cs, child: Row(children: [
              Icon(Icons.format_list_bulleted, size: 15, color: cs.sub),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: _titleCtrl,
                cursorColor: _accent,
                style: TextStyle(fontSize: 14, color: cs.ink),
                decoration: InputDecoration(
                  hintText: '일정 제목', hintStyle: TextStyle(fontSize: 14, color: cs.sub),
                  border: InputBorder.none, contentPadding: EdgeInsets.zero, isDense: true,
                ),
              )),
            ])),
            // 시간 범위
            _FormLabel(label: '시간', cs: cs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(children: [
                Expanded(child: _TimeBox(time: _start, cs: cs, accent: _accent,
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: _start);
                    if (t != null) setState(() => _start = t);
                  })),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward, size: 16, color: cs.sub),
                ),
                Expanded(child: _TimeBox(time: _end, cs: cs, accent: _accent,
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: _end);
                    if (t != null) setState(() => _end = t);
                  })),
              ]),
            ),
            // 색상 선택
            _FormLabel(label: '색상', cs: cs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(children: [
                ...List.generate(_kEventColors.length, (i) => GestureDetector(
                  onTap: () => setState(() => _colorIdx = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 32, height: 32,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: _kEventColors[i],
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: _kEventColors[i].withOpacity(0.45), blurRadius: 6)],
                    ),
                    transform: i == _colorIdx
                        ? (Matrix4.identity()..scale(1.15))
                        : Matrix4.identity(),
                    child: i == _colorIdx
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                )),
                const SizedBox(width: 4),
                Text(_kColorLabels[_colorIdx], style: TextStyle(fontSize: Typo.caption, color: cs.ink3)),
              ]),
            ),
            // 경기 연결
            _FormLabel(label: '경기 연결', cs: cs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: GestureDetector(
                onTap: () => setState(() => _linkGame = !_linkGame),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: cs.paper,
                    border: Border.all(color: _linkGame ? _accent.withOpacity(0.4) : cs.line),
                    borderRadius: BorderRadius.circular(Radii.lg),
                    boxShadow: cs.dark ? null : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 2, offset: const Offset(0,1))],
                  ),
                  child: Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: _linkGame ? _accent.withOpacity(cs.dark ? 0.22 : 0.1) : cs.paper2,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.sports_baseball_outlined, size: 16,
                          color: _linkGame ? _accent : cs.sub),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('경기 연결', style: TextStyle(fontSize: Typo.body, fontWeight: Typo.bold, color: cs.ink)),
                      const SizedBox(height: 3),
                      Text(_linkGame ? 'LG vs KIA · 18:30 잠실야구장' : '오늘 경기와 연결하기',
                        style: TextStyle(fontSize: 10, color: cs.ink3)),
                    ])),
                    _Toggle(on: _linkGame, color: _accent, cs: cs),
                  ]),
                ),
              ),
            ),
            // 메모
            _FormLabel(label: '메모', cs: cs),
            _InputBox(cs: cs, child: TextField(
              controller: _memoCtrl,
              maxLines: 3,
              cursorColor: _accent,
              style: TextStyle(fontSize: 14, color: cs.ink, height: 1.6),
              decoration: InputDecoration(
                hintText: '메모를 입력하세요',
                hintStyle: TextStyle(fontSize: 14, color: cs.sub, height: 1.6),
                border: InputBorder.none, contentPadding: EdgeInsets.zero, isDense: true,
              ),
            )),
          ]),
        )),
      ])),
    );
  }
}

// ── 서브 위젯 ─────────────────────────────────────────────────────────────────

class _TimeBox extends StatelessWidget {
  final TimeOfDay time;
  final _C cs;
  final Color accent;
  final VoidCallback onTap;
  const _TimeBox({required this.time, required this.cs, required this.accent, required this.onTap});

  String get _fmt => '${time.hour.toString().padLeft(2,'0')}:${time.minute.toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(color: cs.paper2, border: Border.all(color: cs.line), borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(children: [
        Icon(Icons.access_time_outlined, size: 14, color: cs.sub),
        const SizedBox(width: 8),
        Text(_fmt, style: TextStyle(fontSize: 14, fontWeight: Typo.bold, color: cs.ink)),
      ]),
    ),
  );
}

class _Toggle extends StatelessWidget {
  final bool on;
  final Color color;
  final _C cs;
  const _Toggle({required this.on, required this.color, required this.cs});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    width: 44, height: 26,
    decoration: BoxDecoration(color: on ? color : cs.track, borderRadius: BorderRadius.circular(13)),
    child: AnimatedAlign(
      duration: const Duration(milliseconds: 200),
      alignment: on ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 20, height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0,1))]),
      ),
    ),
  );
}

class _FormLabel extends StatelessWidget {
  final String label;
  final _C cs;
  const _FormLabel({required this.label, required this.cs});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub, letterSpacing: 0.8)),
  );
}

class _InputBox extends StatelessWidget {
  final Widget child;
  final _C cs;
  const _InputBox({required this.child, required this.cs});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: cs.paper2, border: Border.all(color: cs.line), borderRadius: BorderRadius.circular(13)),
      child: child,
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
