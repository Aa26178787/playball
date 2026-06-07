// cal_event_add_screen.dart — 캘린더 일정 추가 (Option A 디자인 시스템)
import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import '../../api/api_service.dart';

// 색상 키(DB 6종)와 표시 색 매핑 — 키는 백엔드 그대로, 팔레트만 Option A
const _kEventColorKeys = ['blue', 'red', 'green', 'orange', 'purple', 'gray'];
const _kEventColors = [
  Color(0xFF2563EB), Color(0xFFC30452), Color(0xFF16A34A),
  Color(0xFFD97706), Color(0xFF7C3AED), Color(0xFF0891B2),
];
const _kColorLabels = ['블루', '레드', '그린', '오렌지', '퍼플', '틸'];

class CalEventAddScreen extends StatefulWidget {
  /// 일정을 추가할 날짜
  final DateTime date;

  /// 해당 날짜 KBO 경기 수 (헤더 서브텍스트용)
  final int gameCount;
  const CalEventAddScreen({super.key, required this.date, this.gameCount = 0});

  @override
  State<CalEventAddScreen> createState() => _CalEventAddScreenState();
}

class _CalEventAddScreenState extends State<CalEventAddScreen> {
  final _titleCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();

  late DateTime _start = widget.date;
  late DateTime _end = widget.date;
  int _colorIdx = 0; // 블루 기본
  bool _saving = false;

  // 시간 설정 (off = 종일 일정)
  bool _hasTime = false;
  TimeOfDay _startTime = const TimeOfDay(hour: 18, minute: 30);
  TimeOfDay _endTime = const TimeOfDay(hour: 21, minute: 30);

  @override
  void dispose() {
    _titleCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  Color get _accent => _kEventColors[_colorIdx];
  String get _dateStr =>
      '${widget.date.year}년 ${widget.date.month}월 ${widget.date.day}일';
  String get _dowStr =>
      '${['월', '화', '수', '목', '금', '토', '일'][widget.date.weekday - 1]}요일';

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // 전역 withClampedTextScaling(min 0.85)과 picker 내부 clamp가 충돌해
  // 'maxScale > minScale' assert 크래시 → 다이얼로그만 linear scaler로 재설정
  Widget _pickerBuilder(BuildContext ctx, Widget? child) {
    final mq = MediaQuery.of(ctx);
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(14) / 14)),
      child: child!,
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: isStart ? DateTime(2020, 1, 1) : _start,
      lastDate: DateTime(2030, 12, 31),
      locale: const Locale('ko', 'KR'),
      builder: _pickerBuilder,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: _pickerBuilder,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await ApiService.createCalendarEvent(
        _dateKey(_start),
        title,
        description: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
        color: _kEventColorKeys[_colorIdx],
        endDate: _end.isAtSameMomentAs(_start) ? null : _dateKey(_end),
        startTime: _hasTime ? _fmtTime(_startTime) : null,
        endTime: _hasTime ? _fmtTime(_endTime) : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('일정 저장 실패. 로그인 상태를 확인해주세요')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = _C(context);
    final multiDay = !_start.isAtSameMomentAs(_end);
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
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _titleCtrl,
              builder: (_, v, _) {
                final valid = v.text.trim().isNotEmpty && !_saving;
                return ElevatedButton(
                  onPressed: valid ? _save : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    disabledBackgroundColor: cs.track,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: cs.sub,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                    textStyle: const TextStyle(fontSize: 13, fontWeight: Typo.extra),
                  ),
                  child: _saving
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('저장'),
                );
              },
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
                  color: _accent.withValues(alpha: cs.dark ? 0.18 : 0.07),
                  border: Border.all(color: _accent.withValues(alpha: cs.dark ? 0.40 : 0.22)),
                  borderRadius: BorderRadius.circular(Radii.lg),
                ),
                child: Row(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))],
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
                    Text(_dateStr, style: TextStyle(fontSize: 16, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.3)),
                    const SizedBox(height: 4),
                    Text(
                      widget.gameCount > 0 ? '$_dowStr · KBO ${widget.gameCount}경기' : _dowStr,
                      style: TextStyle(fontSize: 12, color: cs.ink3)),
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
            // 날짜 범위
            _FormLabel(label: '날짜', cs: cs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(children: [
                Expanded(child: _DateBox(date: _start, cs: cs,
                  onTap: () => _pickDate(isStart: true))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward, size: 16, color: cs.sub),
                ),
                Expanded(child: _DateBox(date: _end, cs: cs,
                  onTap: () => _pickDate(isStart: false))),
              ]),
            ),
            if (multiDay)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                child: Text('${_end.difference(_start).inDays + 1}일간',
                    style: TextStyle(fontSize: Typo.caption, color: cs.sub)),
              ),
            // 시간 설정
            _FormLabel(label: '시간', cs: cs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: GestureDetector(
                onTap: () => setState(() => _hasTime = !_hasTime),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: cs.paper,
                    border: Border.all(color: _hasTime ? _accent.withValues(alpha: 0.4) : cs.line),
                    borderRadius: BorderRadius.circular(Radii.lg),
                    boxShadow: cs.dark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 2, offset: const Offset(0, 1))],
                  ),
                  child: Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: _hasTime ? _accent.withValues(alpha: cs.dark ? 0.22 : 0.1) : cs.paper2,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.access_time_outlined, size: 16,
                          color: _hasTime ? _accent : cs.sub),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('시간 설정', style: TextStyle(fontSize: Typo.body, fontWeight: Typo.bold, color: cs.ink)),
                      const SizedBox(height: 3),
                      Text(_hasTime ? '${_fmtTime(_startTime)} → ${_fmtTime(_endTime)}' : '종일 일정',
                        style: TextStyle(fontSize: 10, color: cs.ink3)),
                    ])),
                    _Toggle(on: _hasTime, color: _accent, cs: cs),
                  ]),
                ),
              ),
            ),
            if (_hasTime)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                child: Row(children: [
                  Expanded(child: _TimeBox(time: _startTime, cs: cs,
                    onTap: () => _pickTime(isStart: true))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward, size: 16, color: cs.sub),
                  ),
                  Expanded(child: _TimeBox(time: _endTime, cs: cs,
                    onTap: () => _pickTime(isStart: false))),
                ]),
              ),
            // 색상 선택
            _FormLabel(label: '색상', cs: cs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(children: [
                ...List.generate(_kEventColors.length, (i) => GestureDetector(
                  onTap: () => setState(() => _colorIdx = i),
                  child: AnimatedScale(
                    scale: i == _colorIdx ? 1.15 : 1.0,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      width: 32, height: 32,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: _kEventColors[i],
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: _kEventColors[i].withValues(alpha: 0.45), blurRadius: 6)],
                      ),
                      child: i == _colorIdx
                          ? const Icon(Icons.check, size: 14, color: Colors.white)
                          : null,
                    ),
                  ),
                )),
                const SizedBox(width: 4),
                Text(_kColorLabels[_colorIdx], style: TextStyle(fontSize: Typo.caption, color: cs.ink3)),
              ]),
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
  final VoidCallback onTap;
  const _TimeBox({required this.time, required this.cs, required this.onTap});

  String get _fmt =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

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
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))]),
      ),
    ),
  );
}

class _DateBox extends StatelessWidget {
  final DateTime date;
  final _C cs;
  final VoidCallback onTap;
  const _DateBox({required this.date, required this.cs, required this.onTap});

  String get _fmt =>
      '${date.month}/${date.day} (${['월', '화', '수', '목', '금', '토', '일'][date.weekday - 1]})';

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(color: cs.paper2, border: Border.all(color: cs.line), borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(children: [
        Icon(Icons.calendar_today_outlined, size: 14, color: cs.sub),
        const SizedBox(width: 8),
        Text(_fmt, style: TextStyle(fontSize: 14, fontWeight: Typo.bold, color: cs.ink)),
      ]),
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
