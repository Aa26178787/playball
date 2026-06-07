// food_add_screen.dart — 맛집 제안 (Option A 디자인 시스템)
import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';

const _kStadiums = ['서울','고척','수원','인천','대전','광주','대구','창원','사직'];
const _kFoodCats = ['족발·보쌈','국밥','피자','편의점','중식','일식','치킨','기타'];

class FoodAddScreen extends StatefulWidget {
  const FoodAddScreen({super.key});
  @override State<FoodAddScreen> createState() => _FoodAddScreenState();
}

class _FoodAddScreenState extends State<FoodAddScreen> {
  String  _stadium  = '서울';
  int?    _catIdx;
  bool    _verify   = false;

  final _nameCtrl     = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _memoCtrl     = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  bool get _isValid => _nameCtrl.text.trim().isNotEmpty && _catIdx != null;

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
            Text('맛집 제안', style: TextStyle(fontSize: 18, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.4)),
            const Spacer(),
            // 제출 버튼 — 유효성에 따라 활성/비활성
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _nameCtrl,
              builder: (_, __, ___) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: ElevatedButton(
                  onPressed: _isValid ? () => Navigator.maybePop(context) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isValid ? cs.ink : cs.track,
                    disabledBackgroundColor: cs.track,
                    foregroundColor: _isValid ? (cs.dark ? const Color(0xFF0F0F12) : Colors.white) : cs.sub,
                    disabledForegroundColor: cs.sub,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                    textStyle: TextStyle(fontSize: 13, fontWeight: Typo.extra),
                  ),
                  child: const Text('제출'),
                ),
              ),
            ),
          ]),
        ),
        // Content
        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 구장 선택
            _FormLabel(label: '구장 선택', cs: cs),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                itemCount: _kStadiums.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final s = _kStadiums[i];
                  final act = _stadium == s;
                  return GestureDetector(
                    onTap: () => setState(() => _stadium = s),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: act ? cs.ink : cs.paper,
                        borderRadius: BorderRadius.circular(Radii.pill),
                        border: Border.all(color: act ? cs.ink : cs.line2),
                      ),
                      child: Text(s, style: TextStyle(
                        fontSize: 12, fontWeight: act ? Typo.bold : Typo.medium,
                        color: act ? (cs.dark ? const Color(0xFF0F0F12) : Colors.white) : cs.ink3,
                      )),
                    ),
                  );
                },
              ),
            ),
            // 식당명
            _FormLabel(label: '식당명 *', cs: cs, required: true),
            _InputBox(cs: cs, child: Row(children: [
              Icon(Icons.restaurant_menu_outlined, size: 15, color: cs.sub),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: _nameCtrl,
                onChanged: (_) => setState(() {}),
                style: TextStyle(fontSize: 14, color: cs.ink),
                cursorColor: cs.ink,
                decoration: InputDecoration(
                  hintText: '예) 잠실 왕족발',
                  hintStyle: TextStyle(fontSize: 14, color: cs.sub),
                  border: InputBorder.none, contentPadding: EdgeInsets.zero, isDense: true,
                  suffixIcon: _nameCtrl.text.isNotEmpty
                    ? GestureDetector(onTap: () { _nameCtrl.clear(); setState(() {}); },
                        child: Icon(Icons.close, size: 16, color: cs.sub))
                    : null,
                ),
              )),
            ])),
            // 카테고리
            _FormLabel(label: '카테고리 *', cs: cs, required: true),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Wrap(spacing: 6, runSpacing: 6, children: List.generate(_kFoodCats.length, (i) {
                final act = _catIdx == i;
                return GestureDetector(
                  onTap: () => setState(() => _catIdx = act ? null : i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: act ? cs.ink : cs.paper,
                      borderRadius: BorderRadius.circular(Radii.pill),
                      border: Border.all(color: act ? cs.ink : cs.line2),
                    ),
                    child: Text(_kFoodCats[i], style: TextStyle(
                      fontSize: 12, fontWeight: act ? Typo.bold : Typo.medium,
                      color: act ? (cs.dark ? const Color(0xFF0F0F12) : Colors.white) : cs.ink3,
                    )),
                  ),
                );
              })),
            ),
            // 위치 설명
            _FormLabel(label: '위치 설명', cs: cs),
            _InputBox(cs: cs, child: Row(children: [
              Icon(Icons.location_on_outlined, size: 15, color: cs.sub),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: _locationCtrl,
                style: TextStyle(fontSize: 14, color: cs.ink),
                cursorColor: cs.ink,
                decoration: InputDecoration(
                  hintText: '예) 구장 정문에서 5분 거리',
                  hintStyle: TextStyle(fontSize: 14, color: cs.sub),
                  border: InputBorder.none, contentPadding: EdgeInsets.zero, isDense: true,
                ),
              )),
            ])),
            // 한줄 추천
            _FormLabel(label: '한줄 추천', cs: cs),
            _InputBox(cs: cs, child: TextField(
              controller: _memoCtrl,
              maxLines: 2,
              style: TextStyle(fontSize: 14, color: cs.ink, height: 1.6),
              cursorColor: cs.ink,
              decoration: InputDecoration(
                hintText: '이 맛집의 매력을 한 문장으로 소개해주세요',
                hintStyle: TextStyle(fontSize: 14, color: cs.sub, height: 1.6),
                border: InputBorder.none, contentPadding: EdgeInsets.zero, isDense: true,
              ),
            )),
            // 인증 배지 요청
            _FormLabel(label: '인증 배지 요청', cs: cs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: GestureDetector(
                onTap: () => setState(() => _verify = !_verify),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: cs.paper,
                    border: Border.all(color: _verify ? SemColor.live.withOpacity(0.35) : cs.line),
                    borderRadius: BorderRadius.circular(Radii.lg),
                    boxShadow: cs.dark ? null : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 2, offset: const Offset(0,1))],
                  ),
                  child: Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: _verify ? SemColor.live.withOpacity(0.1) : cs.paper2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _verify ? SemColor.live.withOpacity(0.25) : cs.line),
                      ),
                      child: Icon(Icons.shield_outlined, size: 17,
                          color: _verify ? SemColor.live : cs.sub),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('인증 배지 요청', style: TextStyle(fontSize: Typo.body, fontWeight: Typo.bold, color: cs.ink)),
                      const SizedBox(height: 3),
                      Text('직접 방문 후 영수증 등 인증 자료를 제출해요',
                        style: TextStyle(fontSize: 10, color: cs.ink3)),
                    ])),
                    _Toggle(on: _verify, color: SemColor.live, track: cs.track),
                  ]),
                ),
              ),
            ),
            // 제출 버튼
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _nameCtrl,
                builder: (_, __, ___) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isValid ? () => Navigator.maybePop(context) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isValid ? cs.ink : cs.track,
                      disabledBackgroundColor: cs.track,
                      foregroundColor: _isValid ? (cs.dark ? const Color(0xFF0F0F12) : Colors.white) : cs.sub,
                      disabledForegroundColor: cs.sub,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
                      elevation: 0,
                      textStyle: TextStyle(fontSize: 15, fontWeight: Typo.extra, letterSpacing: -0.3),
                    ),
                    child: Text(_isValid ? '맛집 제안하기 →' : '식당명과 카테고리를 입력해주세요'),
                  ),
                ),
              ),
            ),
          ]),
        )),
      ])),
    );
  }
}

// ── 서브 위젯 ─────────────────────────────────────────────────────────────────

class _Toggle extends StatelessWidget {
  final bool on;
  final Color color, track;
  const _Toggle({required this.on, required this.color, required this.track});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    width: 44, height: 26,
    decoration: BoxDecoration(color: on ? color : track, borderRadius: BorderRadius.circular(13)),
    child: AnimatedAlign(
      duration: const Duration(milliseconds: 200),
      alignment: on ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 20, height: 20, margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0,1))]),
      ),
    ),
  );
}

class _FormLabel extends StatelessWidget {
  final String label;
  final _C cs;
  final bool required;
  const _FormLabel({required this.label, required this.cs, this.required = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
    child: RichText(text: TextSpan(
      text: required ? label.replaceAll(' *', '') : label,
      style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub, letterSpacing: 0.8),
      children: required ? [TextSpan(text: ' *', style: TextStyle(color: SemColor.live))] : [],
    )),
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
