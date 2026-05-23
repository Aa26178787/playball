import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../api/api_service.dart';
import '../mypage/phone_verify_screen.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  String _category = '자유';
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
        imageUrl: _uploadedImageUrl,
      );
      if (mounted) Navigator.pop(context);
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
                child: const Text('인증하기', style: TextStyle(color: Color(0xFF1A237E))),
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
              value: _category,
              decoration: const InputDecoration(labelText: '카테고리', border: OutlineInputBorder()),
              items: ['자유', '팀별', '분석', '유머']
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
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
                ),
              ),
            ),
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
                    side: const BorderSide(color: Color(0xFF1A237E)),
                    foregroundColor: const Color(0xFF1A237E),
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
