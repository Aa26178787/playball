import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_service.dart';
import '../../providers/auth_provider.dart';

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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('댓글 작성 실패. 로그인이 필요합니다')),
      );
    }
  }

  Future<void> _editPost() async {
    final titleCtrl = TextEditingController(text: _post!['title']);
    final contentCtrl = TextEditingController(text: _post!['content']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('게시글 수정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: '제목', border: OutlineInputBorder()),
              maxLength: 100,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: contentCtrl,
              decoration: const InputDecoration(labelText: '내용', border: OutlineInputBorder()),
              maxLines: 5,
              maxLength: 2000,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('저장')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.updatePost(widget.postId, titleCtrl.text.trim(), contentCtrl.text.trim());
      _loadPost();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('수정되었습니다')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('수정 실패')));
    }
  }

  Future<void> _deletePost() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('게시글 삭제'),
        content: const Text('삭제하면 복구할 수 없습니다. 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deletePost(widget.postId);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('삭제 실패')));
    }
  }

  Future<void> _deleteComment(int commentId) async {
    try {
      await ApiService.deleteComment(commentId);
      _loadPost();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('삭제 실패')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_post == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('게시글')),
        body: const Center(child: Text('게시글을 불러오지 못했습니다')),
      );
    }

    final myUserId = context.read<AuthProvider>().userId;
    final postUserId = _post!['user_id'];
    final isMyPost = myUserId != null && myUserId == postUserId;
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
              if (v == 'edit') {
                await _editPost();
              } else if (v == 'delete') {
                await _deletePost();
              } else if (v == 'report') {
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
              if (isMyPost) ...[
                const PopupMenuItem(value: 'edit', child: Text('수정')),
                const PopupMenuItem(value: 'delete',
                    child: Text('삭제', style: TextStyle(color: Colors.red))),
              ] else
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
                Text(
                  _post!['title'] ?? '',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_post!['author'] ?? ''} | ${(_post!['created_at'] ?? '').toString().substring(0, 10)}',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                const Divider(),
                Text(_post!['content'] ?? ''),
                if (_post!['image_url'] != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      _post!['image_url'] as String,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text('❤️ ${_post!['likes'] ?? 0}',
                    style: const TextStyle(color: Colors.red)),
                const Divider(),
                Text('댓글 ${comments.length}개',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...comments.map((c) {
                  final isMyComment = myUserId != null && myUserId == c['user_id'];
                  return ListTile(
                    title: Text(c['content'] ?? ''),
                    subtitle: Text('${c['author'] ?? ''}  ${(c['created_at'] ?? '').toString().length >= 10 ? (c['created_at'] as String).substring(0, 10) : ''}',
                        style: const TextStyle(fontSize: 11)),
                    trailing: isMyComment
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                            onPressed: () => _deleteComment(c['id']),
                          )
                        : null,
                  );
                }),
              ],
            ),
          ),
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
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
