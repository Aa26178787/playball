import 'package:flutter/material.dart';
import '../../api/api_service.dart';

class PostDetailScreen extends StatefulWidget {
  final int postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  Map<String, dynamic>? _post;
  bool _isLoading = true;
  final _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPost();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadPost() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getPostDetail(widget.postId);
      setState(() {
        _post = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitComment() async {
    if (_commentController.text.trim().isEmpty) return;
    try {
      await ApiService.createComment(
          widget.postId, _commentController.text.trim());
      _commentController.clear();
      _loadPost();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('댓글 작성 실패. 로그인이 필요합니다')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    if (_post == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('게시글')),
        body: const Center(child: Text('게시글을 불러오지 못했습니다')),
      );
    }

    final comments = _post!['comments'] as List? ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('게시글'),
        actions: [
          IconButton(
            icon: const Icon(Icons.favorite_border),
            onPressed: () async {
              await ApiService.toggleLike(widget.postId);
              _loadPost();
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'report') {
                final reason = await showDialog<String>(
                  context: context,
                  builder: (_) => SimpleDialog(
                    title: const Text('신고 사유'),
                    children: ['스팸', '욕설/혐오', '불법정보', '기타'].map((r) =>
                      SimpleDialogOption(
                        child: Text(r),
                        onPressed: () => Navigator.pop(context, r),
                      )).toList(),
                  ),
                );
                if (reason != null) {
                  try {
                    await ApiService.reportPost(widget.postId, reason: reason);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('신고가 접수되었습니다')));
                  } catch (_) {}
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'report', child: Text('신고')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 제목
                Text(
                  _post!['title'] ?? '',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_post!['author'] ?? ''} | ${_post!['created_at'] ?? ''}',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                const Divider(),
                // 내용
                Text(_post!['content'] ?? ''),
                const SizedBox(height: 8),
                Text('❤️ ${_post!['likes'] ?? 0}',
                    style: const TextStyle(color: Colors.red)),
                const Divider(),
                // 댓글
                Text('댓글 ${comments.length}개',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...comments.map((c) => ListTile(
                      title: Text(c['content'] ?? ''),
                      subtitle: Text(c['author'] ?? ''),
                    )),
              ],
            ),
          ),
          // 댓글 입력
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: const InputDecoration(
                      hintText: '댓글을 입력하세요',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _submitComment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}