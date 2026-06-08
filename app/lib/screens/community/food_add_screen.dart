// food_add_screen.dart — 맛집 제안 (Option A 디자인 시스템)
// 카카오 장소 검색 기반: 검색 → 선택 → 한줄 추천 → 제출
import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import '../../api/api_service.dart';

const _kStadiums = [
  (id: 1, name: '서울'),
  (id: 2, name: '고척'),
  (id: 3, name: '수원'),
  (id: 4, name: '인천'),
  (id: 5, name: '대전'),
  (id: 6, name: '광주'),
  (id: 7, name: '대구'),
  (id: 8, name: '창원'),
  (id: 9, name: '사직'),
];

class FoodAddScreen extends StatefulWidget {
  final int initialStadiumId;
  const FoodAddScreen({super.key, this.initialStadiumId = 1});

  @override
  State<FoodAddScreen> createState() => _FoodAddScreenState();
}

class _FoodAddScreenState extends State<FoodAddScreen> {
  late int _stadiumId = widget.initialStadiumId;
  final _searchCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  List _results = [];
  bool _searching = false;
  Map? _selected;
  bool _submitting = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  bool get _isValid => _selected != null && !_submitting;

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty || _searching) return;
    setState(() { _searching = true; _results = []; _selected = null; });
    try {
      final data = await ApiService.searchFoodPlace(_stadiumId, q);
      if (mounted) setState(() { _results = data['places'] ?? []; _searching = false; });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _submit() async {
    if (!_isValid) return;
    setState(() => _submitting = true);
    try {
      await ApiService.submitFoodPlace(_stadiumId, {
        'kakao_place_id': _selected!['id'],
        'name': _selected!['name'],
        'category': _selected!['category'],
        'address': _selected!['address'],
        'phone': _selected!['phone'],
        'url': _selected!['url'],
        'memo': _memoCtrl.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        final msg = e.toString().contains('409') ? '이미 등록된 장소입니다' : '제안 실패. 로그인 상태를 확인해주세요';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = _C(context);
    final fg = cs.dark ? const Color(0xFF0F0F12) : Colors.white;
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
            ElevatedButton(
              onPressed: _isValid ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.ink,
                disabledBackgroundColor: cs.track,
                foregroundColor: fg,
                disabledForegroundColor: cs.sub,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
                textStyle: const TextStyle(fontSize: 13, fontWeight: Typo.extra),
              ),
              child: const Text('제출'),
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
              child: _fade(ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                itemCount: _kStadiums.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final s = _kStadiums[i];
                  final act = _stadiumId == s.id;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _stadiumId = s.id;
                      _results = [];
                      _selected = null;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: act ? cs.ink : cs.paper,
                        borderRadius: BorderRadius.circular(Radii.pill),
                        border: Border.all(color: act ? cs.ink : cs.line2),
                      ),
                      child: Text(s.name, style: TextStyle(
                        fontSize: 12, fontWeight: act ? Typo.bold : Typo.medium,
                        color: act ? fg : cs.ink3,
                      )),
                    ),
                  );
                },
              )),
            ),
            // 식당 검색
            _FormLabel(label: '식당 검색 *', cs: cs, required: true),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(children: [
                Expanded(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  decoration: BoxDecoration(color: cs.paper2, border: Border.all(color: cs.line), borderRadius: BorderRadius.circular(13)),
                  child: Row(children: [
                    Icon(Icons.restaurant_menu_outlined, size: 15, color: cs.sub),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _search(),
                      style: TextStyle(fontSize: 14, color: cs.ink),
                      cursorColor: cs.ink,
                      decoration: InputDecoration(
                        hintText: '예) 잠실 왕족발',
                        hintStyle: TextStyle(fontSize: 14, color: cs.sub),
                        border: InputBorder.none, isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    )),
                    if (_searchCtrl.text.isNotEmpty)
                      GestureDetector(
                        onTap: () { _searchCtrl.clear(); setState(() {}); },
                        child: Icon(Icons.close, size: 16, color: cs.sub),
                      ),
                  ]),
                )),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _searching ? null : _search,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    decoration: BoxDecoration(
                      color: cs.ink,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: _searching
                        ? SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                        : Text('검색', style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: fg)),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Text('구장 2km 이내 음식점만 등록 가능합니다',
                  style: TextStyle(fontSize: Typo.caption, color: cs.sub)),
            ),
            // 검색 결과 / 선택된 가게
            if (_selected != null) ...[
              _FormLabel(label: '선택한 가게', cs: cs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: SemColor.live.withValues(alpha: cs.dark ? 0.10 : 0.05),
                    border: Border.all(color: SemColor.live.withValues(alpha: 0.30)),
                    borderRadius: BorderRadius.circular(Radii.lg),
                  ),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: SemColor.live.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.check, size: 17, color: SemColor.live),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_selected!['name'] as String? ?? '',
                          style: TextStyle(fontSize: Typo.body, fontWeight: Typo.bold, color: cs.ink)),
                      const SizedBox(height: 3),
                      Text(_selected!['category'] as String? ?? '',
                          style: TextStyle(fontSize: 10, color: cs.ink3)),
                    ])),
                    IconButton(
                      icon: Icon(Icons.close, size: 16, color: cs.sub),
                      tooltip: '선택 해제',
                      onPressed: () => setState(() => _selected = null),
                      padding: EdgeInsets.zero,
                    ),
                  ]),
                ),
              ),
              // 한줄 추천
              _FormLabel(label: '한줄 추천', cs: cs),
              _InputBox(cs: cs, child: TextField(
                controller: _memoCtrl,
                maxLines: 2,
                maxLength: 60,
                style: TextStyle(fontSize: 14, color: cs.ink, height: 1.6),
                cursorColor: cs.ink,
                decoration: InputDecoration(
                  hintText: '이 맛집의 매력을 한 문장으로 소개해주세요',
                  hintStyle: TextStyle(fontSize: 14, color: cs.sub, height: 1.6),
                  border: InputBorder.none, contentPadding: EdgeInsets.zero, isDense: true,
                  counterStyle: TextStyle(fontSize: 10, color: cs.sub),
                ),
              )),
            ] else if (_results.isNotEmpty) ...[
              _FormLabel(label: '검색 결과', cs: cs),
              ...List.generate(_results.length, (i) {
                final p = _results[i] as Map;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selected = p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: cs.paper,
                        border: Border.all(color: cs.line),
                        borderRadius: BorderRadius.circular(Radii.md),
                      ),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p['name'] as String? ?? '',
                              style: TextStyle(fontSize: Typo.body, fontWeight: Typo.bold, color: cs.ink)),
                          const SizedBox(height: 3),
                          Text(p['category'] as String? ?? '',
                              style: TextStyle(fontSize: 10, color: cs.ink3)),
                        ])),
                        Icon(Icons.add, size: 18, color: cs.ink3),
                      ]),
                    ),
                  ),
                );
              }),
            ],
            // 제출 버튼
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isValid ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.ink,
                    disabledBackgroundColor: cs.track,
                    foregroundColor: fg,
                    disabledForegroundColor: cs.sub,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
                    elevation: 0,
                    textStyle: const TextStyle(fontSize: 15, fontWeight: Typo.extra, letterSpacing: -0.3),
                  ),
                  child: _submitting
                      ? SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: cs.sub))
                      : Text(_selected != null ? '맛집 제안하기 →' : '가게를 검색해 선택해주세요'),
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

// 가로 스크롤 스트립 — 양 끝 그라디언트 페이드
Widget _fade(Widget child) => ShaderMask(
  shaderCallback: (rect) => const LinearGradient(
    begin: Alignment.centerLeft, end: Alignment.centerRight,
    colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
    stops: [0.0, 0.04, 0.96, 1.0],
  ).createShader(rect),
  blendMode: BlendMode.dstIn,
  child: child,
);

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
      children: required ? [const TextSpan(text: ' *', style: TextStyle(color: SemColor.live))] : [],
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
