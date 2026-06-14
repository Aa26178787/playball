// visit_record_screen.dart — 직관 기록 추가 (Option A 디자인 시스템)
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:in_app_review/in_app_review.dart';
import '../../utils/design_tokens.dart';
import '../../utils/team_theme.dart';
import '../../utils/share_card.dart';
import '../../utils/app_config.dart';
import '../../widgets/share_cards.dart';
import '../../api/api_service.dart';

const _kResults = [
  (value: 'win',  label: '승리',  color: Color(0xFF2563EB)),
  (value: 'loss', label: '패배',  color: SemColor.live),
  (value: 'draw', label: '무승부', color: Color(0xFF6B6B73)),
];

class VisitRecordScreen extends StatefulWidget {
  /// 직관한 경기 (calendar API game map: id, home_team, away_team, *_team_code, stadium, start_time)
  final Map game;
  final DateTime date;
  const VisitRecordScreen({super.key, required this.game, required this.date});

  @override
  State<VisitRecordScreen> createState() => _VisitRecordScreenState();
}

class _VisitRecordScreenState extends State<VisitRecordScreen> {
  final _memoCtrl = TextEditingController();
  String _result = 'win';
  String? _pickedImagePath;
  bool _saving = false;

  @override
  void dispose() {
    _memoCtrl.dispose();
    super.dispose();
  }

  Color get _accent => _kResults.firstWhere((r) => r.value == _result).color;
  String get _dateStr =>
      '${widget.date.year}년 ${widget.date.month}월 ${widget.date.day}일';
  String get _dowStr =>
      '${['월', '화', '수', '목', '금', '토', '일'][widget.date.weekday - 1]}요일';

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xfile != null && mounted) setState(() => _pickedImagePath = xfile.path);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      String? imageUrl;
      if (_pickedImagePath != null) {
        try {
          imageUrl = await ApiService.uploadPostImage(_pickedImagePath!);
        } catch (e) { debugPrint('visit_record: $e'); }
      }
      final gameId = widget.game['id'] as int;
      final memo = _memoCtrl.text.trim();
      final res = await ApiService.addStadiumVisit(
        gameId, _result,
        memo: memo.isEmpty ? null : memo,
        imageUrl: imageUrl,
      );
      // 메가C: 저장 직후 공유 카드 제안 → 닫힌 뒤 승리면 인앱 리뷰 (OS가 빈도 제어)
      if (mounted && AppConfig.enabled('share')) {
        await showShareCardDialog(
          context,
          filename: 'playball_visit',
          card: VisitShareCard(
            homeCode: widget.game['home_team_code'] as String? ?? '',
            awayCode: widget.game['away_team_code'] as String? ?? '',
            homeName: widget.game['home_team'] as String? ?? '',
            awayName: widget.game['away_team'] as String? ?? '',
            result: _result,
            dateStr: _dateStr,
            stadium: widget.game['stadium'] as String? ?? '',
            memo: memo,
          ),
        );
      }
      if (_result == 'win' && !kIsWeb) {
        try {
          final review = InAppReview.instance;
          if (await review.isAvailable()) review.requestReview();
        } catch (e) { debugPrint('visit_record review: $e'); }
      }
      if (mounted) {
        Navigator.pop(context, {
          'id': res['id'],
          'game_id': gameId,
          'result': _result,
          'memo': memo,
          'image_url': imageUrl,
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('직관 기록 저장 실패. 로그인 상태를 확인해주세요')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = _C(context);
    final homeCode = widget.game['home_team_code'] as String? ?? '';
    final awayCode = widget.game['away_team_code'] as String? ?? '';
    final stadium = widget.game['stadium'] as String? ?? '';
    final startTime = widget.game['start_time'] as String? ?? '';

    return Scaffold(
      backgroundColor: cs.bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(top: false, child: Column(children: [
        // AppBar — 상태바까지 paper (단차 방지, 06-13)
        Container(
          padding: EdgeInsets.fromLTRB(
              18, 8 + MediaQuery.of(context).viewPadding.top, 18, 12),
          decoration: BoxDecoration(color: cs.paper, border: Border(bottom: BorderSide(color: cs.line))),
          child: Row(children: [
            _Btn32(border: cs.line2, onTap: () => Navigator.maybePop(context),
              child: Icon(Icons.chevron_left, size: 20, color: cs.ink2)),
            const SizedBox(width: 10),
            Text('직관 기록', style: TextStyle(fontSize: 18, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.4)),
            const Spacer(),
            ElevatedButton(
              onPressed: _saving ? null : _save,
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
            ),
          ]),
        ),
        // Content
        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 경기 헤더
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
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_dateStr, style: TextStyle(fontSize: 16, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.3)),
                    const SizedBox(height: 4),
                    Text('$_dowStr${stadium.isNotEmpty ? ' · $stadium' : ''}${startTime.isNotEmpty ? ' $startTime' : ''}',
                        style: TextStyle(fontSize: 12, color: cs.ink3)),
                  ])),
                ]),
              ),
            ),
            // 경기
            _FormLabel(label: '경기', cs: cs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: cs.paper, border: Border.all(color: cs.line),
                  borderRadius: BorderRadius.circular(Radii.lg),
                  boxShadow: cs.dark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 2, offset: const Offset(0, 1))],
                ),
                child: Row(children: [
                  Expanded(child: Column(children: [
                    TeamLogo(teamCode: homeCode, size: 38),
                    const SizedBox(height: 6),
                    Text(widget.game['home_team'] as String? ?? '',
                        style: TextStyle(fontSize: Typo.body, fontWeight: Typo.extra, color: cs.ink),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 2),
                    Text('홈', style: TextStyle(fontSize: 10, color: cs.sub)),
                  ])),
                  Text('VS', style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.extra, color: cs.sub)),
                  Expanded(child: Column(children: [
                    TeamLogo(teamCode: awayCode, size: 38),
                    const SizedBox(height: 6),
                    Text(widget.game['away_team'] as String? ?? '',
                        style: TextStyle(fontSize: Typo.body, fontWeight: Typo.extra, color: cs.ink),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 2),
                    Text('원정', style: TextStyle(fontSize: 10, color: cs.sub)),
                  ])),
                ]),
              ),
            ),
            // 경기 결과
            _FormLabel(label: '경기 결과', cs: cs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(children: _kResults.map((r) {
                final act = _result == r.value;
                return Expanded(child: GestureDetector(
                  onTap: () => setState(() => _result = r.value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: EdgeInsets.only(right: r == _kResults.last ? 0 : 8),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: act ? r.color : r.color.withValues(alpha: cs.dark ? 0.14 : 0.08),
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(color: act ? r.color : r.color.withValues(alpha: 0.3)),
                    ),
                    child: Center(child: Text(r.label, style: TextStyle(
                      fontSize: Typo.body,
                      fontWeight: act ? Typo.extra : Typo.medium,
                      color: act ? Colors.white : r.color,
                    ))),
                  ),
                ));
              }).toList()),
            ),
            // 메모
            _FormLabel(label: '메모', cs: cs),
            _InputBox(cs: cs, child: TextField(
              controller: _memoCtrl,
              maxLines: 3,
              cursorColor: _accent,
              style: TextStyle(fontSize: 14, color: cs.ink, height: 1.6),
              decoration: InputDecoration(
                hintText: '직관 후기를 입력하세요',
                hintStyle: TextStyle(fontSize: 14, color: cs.sub, height: 1.6),
                border: InputBorder.none, contentPadding: EdgeInsets.zero, isDense: true,
              ),
            )),
            // 사진
            _FormLabel(label: '사진', cs: cs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _pickedImagePath != null
                  ? Stack(
                      alignment: Alignment.topRight,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.md),
                          child: Image.file(File(_pickedImagePath!),
                              height: 160, width: double.infinity, fit: BoxFit.cover),
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel, color: Colors.white),
                          tooltip: '사진 제거',
                          onPressed: () => setState(() => _pickedImagePath = null),
                        ),
                      ],
                    )
                  : GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 88,
                        decoration: BoxDecoration(
                          color: cs.paper2,
                          border: Border.all(color: cs.line2, width: 1.5),
                          borderRadius: BorderRadius.circular(Radii.md),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 20, color: cs.sub),
                          const SizedBox(width: 8),
                          Text('사진 추가 (선택)', style: TextStyle(fontSize: 12, color: cs.sub)),
                        ]),
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
      sub    = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF8E8E98) : const Color(0xFF9A9AA2),
      line   = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0),
      line2  = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF33333A) : const Color(0xFFE0E0E4),
      track  = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF2C2C33) : const Color(0xFFE8E8EC);
}
