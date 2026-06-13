// create_post_screen.dart — 게시글 작성 (Option A 디자인 시스템)
import 'dart:io';
import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../api/api_service.dart';
import '../../utils/team_theme.dart';
import '../mypage/phone_verify_screen.dart';

const _kTeams = [
  (id: 1,  code: 'KT', name: 'KT'),
  (id: 2,  code: 'HT', name: 'KIA'),
  (id: 4,  code: 'LT', name: '롯데'),
  (id: 5,  code: 'HH', name: '한화'),
  (id: 6,  code: 'NC', name: 'NC'),
  (id: 7,  code: 'OB', name: '두산'),
  (id: 8,  code: 'WO', name: '키움'),
  (id: 9,  code: 'LG', name: 'LG'),
  (id: 10, code: 'SK', name: 'SSG'),
  (id: 11, code: 'SS', name: '삼성'),
];
const _kCategories = ['자유', '팀별', '분석', '유머'];

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  String _category = '자유';
  int? _selectedTeamId;
  bool _isLoading = false;
  bool _imageUploading = false;
  final List<File> _imageFiles = [];
  final List<String> _uploadedUrls = [];
  static const _maxImages = 10;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Color _accent(BuildContext context) {
    if (_category == '팀별' && _selectedTeamId != null) {
      final t = _kTeams.where((t) => t.id == _selectedTeamId);
      if (t.isNotEmpty) return teamColor(t.first.code);
    }
    return SemColor.brand(context);
  }

  Future<void> _pickImage() async {
    final remaining = _maxImages - _imageFiles.length;
    if (remaining <= 0) return;
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 80, limit: remaining);
    if (picked.isEmpty) return;
    final take = picked.take(remaining).toList();
    setState(() => _imageUploading = true);
    try {
      for (final x in take) {
        final url = await ApiService.uploadPostImage(x.path);
        if (!mounted) return;
        setState(() { _imageFiles.add(File(x.path)); _uploadedUrls.add(url); });
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이미지 업로드 실패')));
    } finally {
      if (mounted) setState(() => _imageUploading = false);
    }
  }

  void _removeImage(int i) {
    setState(() { _imageFiles.removeAt(i); _uploadedUrls.removeAt(i); });
  }

  Future<void> _submit() async {
    if (_isLoading) return; // 더블탭 중복 작성 가드 (06-13)
    if (_titleController.text.trim().isEmpty || _contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('제목과 내용을 입력해주세요')));
      return;
    }
    if (_category == '팀별' && _selectedTeamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('팀을 선택해주세요')));
      return;
    }
    if (_imageUploading) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이미지 업로드 중...')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ApiService.createPost(
        _titleController.text.trim(),
        _contentController.text.trim(),
        _category,
        teamId: _category == '팀별' ? _selectedTeamId : null,
        imageUrls: _uploadedUrls.isNotEmpty ? _uploadedUrls : null,
      );
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'];
      if (detail == 'phone_not_verified' && mounted) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('전화번호 인증 필요'),
            content: const Text('커뮤니티 글쓰기는 전화번호 인증 후 이용 가능합니다.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('인증하기', style: TextStyle(color: SemColor.brand(context))),
              ),
            ],
          ),
        );
        if (ok == true && mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const PhoneVerifyScreen()));
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(detail ?? '게시글 작성 실패. 로그인이 필요합니다')),
        );
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('게시글 작성 실패')));
    }
    setState(() => _isLoading = false);
  }

  // 커서 위치에 '@' 삽입
  void _insertMention() {
    final text = _contentController.text;
    final sel = _contentController.selection;
    final pos = sel.isValid ? sel.start : text.length;
    _contentController.value = TextEditingValue(
      text: text.replaceRange(pos, sel.isValid ? sel.end : pos, '@'),
      selection: TextSelection.collapsed(offset: pos + 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = _C(context);
    final accent = _accent(context);
    // 팀컬러 액센트는 흰 글자, brand(다크=밝은색)는 어두운 글자
    final accentFg = (_category == '팀별' && _selectedTeamId != null)
        ? Colors.white
        : (cs.dark ? const Color(0xFF0F0F12) : Colors.white);
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
            _Btn32(onTap: () => Navigator.maybePop(context), border: cs.line2,
              child: Icon(Icons.chevron_left, size: 20, color: cs.ink2)),
            const SizedBox(width: 10),
            Text('글 작성', style: TextStyle(fontSize: 18, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.4)),
            const Spacer(),
            ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                disabledBackgroundColor: cs.line2,
                foregroundColor: accentFg,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
                textStyle: const TextStyle(fontSize: 13, fontWeight: Typo.extra),
              ),
              child: _isLoading
                  ? SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: accentFg))
                  : const Text('완료'),
            ),
          ]),
        ),
        // Content
        Expanded(child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 카테고리
            _SectionLabel(label: '카테고리', cs: cs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Wrap(spacing: 6, runSpacing: 6, children: _kCategories.map((c) {
                final act = c == _category;
                return GestureDetector(
                  onTap: () => setState(() {
                    _category = c;
                    if (_category != '팀별') _selectedTeamId = null;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: act ? cs.ink : cs.paper,
                      borderRadius: BorderRadius.circular(Radii.pill),
                      border: Border.all(color: act ? cs.ink : cs.line2),
                    ),
                    child: Text(c, style: TextStyle(
                      fontSize: 12, fontWeight: act ? Typo.bold : Typo.medium,
                      color: act ? (cs.dark ? const Color(0xFF0F0F12) : Colors.white) : cs.ink3,
                    )),
                  ),
                );
              }).toList()),
            ),
            // 팀 선택 (팀별 카테고리)
            if (_category == '팀별') ...[
              _SectionLabel(label: '팀 선택', cs: cs),
              SizedBox(
                height: 44,
                child: _fade(ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                  itemCount: _kTeams.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final t = _kTeams[i];
                    final act = _selectedTeamId == t.id;
                    final c = teamColor(t.code);
                    return GestureDetector(
                      onTap: () => setState(() => _selectedTeamId = t.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                        decoration: BoxDecoration(
                          color: act ? c.withValues(alpha: cs.dark ? 0.22 : 0.10) : cs.paper,
                          borderRadius: BorderRadius.circular(Radii.pill),
                          border: Border.all(color: act ? c.withValues(alpha: 0.45) : cs.line2),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          TeamLogo(teamCode: t.code, size: 15),
                          const SizedBox(width: 5),
                          Text(t.name, style: TextStyle(fontSize: 12,
                            fontWeight: act ? Typo.bold : Typo.medium,
                            color: act ? c : cs.ink3)),
                        ]),
                      ),
                    );
                  },
                )),
              ),
            ],
            const SizedBox(height: 16),
            Divider(height: 1, color: cs.line),
            const SizedBox(height: 12),
            // 제목
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: TextField(
                controller: _titleController,
                maxLength: 60,
                style: TextStyle(fontSize: 18, fontWeight: Typo.extra, color: cs.ink),
                cursorColor: accent,
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
                controller: _contentController,
                maxLines: null,
                minLines: 8,
                // 커서가 키보드/툴바에 가리지 않게 자동 스크롤 여유 (06-13)
                scrollPadding: const EdgeInsets.only(bottom: 140),
                style: TextStyle(fontSize: 14, color: cs.ink, height: 1.7),
                cursorColor: accent,
                decoration: InputDecoration(
                  hintText: '야구 팬 여러분과 이야기 나눠보세요…',
                  hintStyle: TextStyle(fontSize: 14, color: cs.sub, height: 1.7),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _MentionHelpRow(),
            ),
            // 이미지 첨부 (다중)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: SizedBox(
                height: 88,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  ..._imageFiles.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.md),
                        child: Image.file(e.value, height: 88, width: 88, fit: BoxFit.cover),
                      ),
                      Positioned(top: 3, right: 3, child: GestureDetector(
                        onTap: () => _removeImage(e.key),
                        child: Container(
                          padding: const EdgeInsets.all(1),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 15, color: Colors.white),
                        ),
                      )),
                    ]),
                  )),
                  if (_imageFiles.length < _maxImages)
                    GestureDetector(
                      onTap: _imageUploading ? null : _pickImage,
                      child: Container(
                        width: 88, height: 88,
                        decoration: BoxDecoration(
                          color: cs.paper2,
                          border: Border.all(color: cs.line2, width: 1.5),
                          borderRadius: BorderRadius.circular(Radii.md),
                        ),
                        child: _imageUploading
                            ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.add_photo_alternate_outlined, size: 20, color: cs.sub),
                                const SizedBox(height: 4),
                                Text('${_imageFiles.length}/$_maxImages', style: TextStyle(fontSize: 10, color: cs.sub)),
                              ]),
                      ),
                    ),
                ]),
              ),
            ),
          ]),
        )),
        // 하단 툴바
        Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
          decoration: BoxDecoration(color: cs.paper, border: Border(top: BorderSide(color: cs.line))),
          child: Row(children: [
            Tooltip(
              message: '이미지 첨부',
              child: _ToolBtn(icon: Icons.image_outlined, cs: cs,
                  onTap: _imageUploading ? null : _pickImage),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: '@ 멘션 삽입',
              child: _ToolBtn(icon: Icons.alternate_email, cs: cs, onTap: _insertMention),
            ),
            if (_uploadedUrls.isNotEmpty) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check_circle, color: Colors.green, size: 16),
              const SizedBox(width: 2),
              Text('${_uploadedUrls.length}', style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w700)),
            ],
            const Spacer(),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _contentController,
              builder: (_, v, _) => Text('${v.text.length} 자',
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
  final VoidCallback? onTap;
  const _ToolBtn({required this.icon, required this.cs, this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(border: Border.all(color: cs.line), borderRadius: BorderRadius.circular(9)),
      child: Icon(icon, size: 18, color: cs.ink3),
    ),
  );
}

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

class _MentionHelpRow extends StatefulWidget {
  @override
  State<_MentionHelpRow> createState() => _MentionHelpRowState();
}

class _MentionHelpRowState extends State<_MentionHelpRow> {
  bool _expanded = false;

  static const _examples = [
    ('경기', '@경기 5/20 KT LG', '경기 상세로 이동'),
    ('선수', '@선수 강백호', '선수 프로필로 이동'),
    ('팀',  '@팀 두산',     '팀 상세로 이동'),
    ('구장', '@구장 잠실',   '구장 안내로 이동'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Icon(Icons.alternate_email, size: 14, color: SemColor.brand(context)),
              const SizedBox(width: 4),
              Text('@ 링크 명령어 보기', style: TextStyle(fontSize: 12, color: SemColor.brand(context))),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  size: 14, color: SemColor.brand(context)),
            ],
          ),
        ),
        if (_expanded)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: SemColor.brand(context).withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: SemColor.brand(context).withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: _examples.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: SemColor.brand(context).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(e.$1, style: TextStyle(fontSize: 11, color: SemColor.brand(context))),
                    ),
                    const SizedBox(width: 8),
                    Text(e.$2, style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                    const SizedBox(width: 6),
                    Text('→ ${e.$3}', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  ],
                ),
              )).toList(),
            ),
          ),
      ],
    );
  }
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
