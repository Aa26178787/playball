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
  File? _imageFile;
  bool _imageUploading = false;
  String? _uploadedImageUrl;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    setState(() { _imageFile = File(picked.path); _uploadedImageUrl = null; _imageUploading = true; });
    try {
      final url = await ApiService.uploadPostImage(picked.path);
      setState(() { _uploadedImageUrl = url; _imageUploading = false; });
    } catch (_) {
      setState(() { _imageFile = null; _imageUploading = false; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이미지 업로드 실패')));
    }
  }

  void _removeImage() {
    setState(() { _imageFile = null; _uploadedImageUrl = null; });
  }

  Future<void> _submit() async {
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
        imageUrl: _uploadedImageUrl,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('게시글 작성'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _submit,
            child: const Text('등록', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: '카테고리', border: OutlineInputBorder()),
              items: ['자유', '팀별', '분석', '유머']
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() {
                _category = v!;
                if (_category != '팀별') _selectedTeamId = null;
              }),
            ),
            if (_category == '팀별') ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _kTeams.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final t = _kTeams[i];
                    final sel = _selectedTeamId == t.id;
                    final tc = teamColor(t.code);
                    return GestureDetector(
                      onTap: () => setState(() => _selectedTeamId = t.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? tc.withValues(alpha: 0.14) : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: sel ? tc : Colors.grey.shade300,
                            width: sel ? 1.6 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TeamLogo(teamCode: t.code, size: 22),
                            const SizedBox(width: 6),
                            Text(t.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                                  color: sel ? tc : Colors.black87,
                                )),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: '제목', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _contentController,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  labelText: '내용',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                  hintText: '@경기, @선수, @팀, @구장 으로 링크를 삽입할 수 있습니다',
                  hintStyle: TextStyle(fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 6),
            _MentionHelpRow(),
            const SizedBox(height: 12),
            // 이미지 첨부
            if (_imageFile != null)
              Stack(
                alignment: Alignment.topRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _imageUploading
                        ? Container(
                            height: 120,
                            width: double.infinity,
                            color: Colors.grey[200],
                            child: const Center(child: CircularProgressIndicator()),
                          )
                        : Image.file(_imageFile!, height: 120, width: double.infinity, fit: BoxFit.cover),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.white),
                    tooltip: '이미지 제거',
                    onPressed: _removeImage,
                  ),
                ],
              ),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _imageUploading ? null : _pickImage,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('이미지 첨부'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: SemColor.brand(context)),
                    foregroundColor: SemColor.brand(context),
                  ),
                ),
                if (_uploadedImageUrl != null)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.check_circle, color: Colors.green, size: 20),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _examples.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
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
