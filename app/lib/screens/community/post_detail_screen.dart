import 'package:flutter/material.dart';
import '../../widgets/common_widgets.dart';
import '../../utils/design_tokens.dart';
import 'package:provider/provider.dart';
import '../../api/api_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/mention_text.dart';
import '../../utils/web_image.dart';

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
    // pull-to-refresh 시 전체 스피너 재표시 방지 (첫 로드만)
    if (_post == null) setState(() => _isLoading = true);
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

  bool _submittingComment = false; // 더블탭 중복 작성 가드 (06-13 알림 2개 사고)

  Future<void> _submitComment() async {
    if (_commentController.text.trim().isEmpty || _submittingComment) return;
    _submittingComment = true;
    try {
      await ApiService.createComment(
          widget.postId, _commentController.text.trim());
      _commentController.clear();
      _loadPost();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('댓글 작성 실패. 로그인이 필요합니다')),
      );
      }
    } finally {
      _submittingComment = false;
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('수정되었습니다')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('수정 실패')));
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('삭제 실패')));
      }
    }
  }

  Future<void> _deleteComment(int commentId) async {
    try {
      await ApiService.deleteComment(commentId);
      _loadPost();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('삭제 실패')));
      }
    }
  }

  Future<void> _blockAuthor(int userId, {String? name}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('사용자 차단'),
        content: Text('${name != null && name.isNotEmpty ? '$name 님' : '이 사용자'}을 차단하면 작성한 글과 댓글이 보이지 않습니다. 차단할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('차단', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.blockUser(userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('차단했습니다')));
        Navigator.pop(context, true); // 목록 새로고침
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('차단 실패')));
      }
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
        body: const AppErrorView(message: '게시글을 불러오지 못했습니다'),
      );
    }

    final myUserId = context.read<AuthProvider>().userId;
    final postUserId = _post!['user_id'];
    final isMyPost = myUserId != null && myUserId == postUserId;
    final comments = _post!['comments'] as List? ?? [];

    return PopScope(
      canPop: false,
      // 댓글 작성 중 뒤로가기 → 유실 경고 (작성 내용 없으면 즉시 pop)
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (_commentController.text.trim().isEmpty) {
          nav.pop();
          return;
        }
        final leave = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('작성 중인 댓글이 있습니다'),
            content: const Text('나가면 작성한 내용이 사라집니다.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('계속 작성')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('나가기', style: TextStyle(color: Colors.red))),
            ],
          ),
        );
        if (leave == true) nav.pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('게시글'),
        actions: [
          Builder(builder: (ctx) {
            final liked = _post?['liked_by_me'] as bool? ?? false;
            return IconButton(
              icon: Icon(liked ? Icons.favorite : Icons.favorite_border,
                  color: liked ? Colors.red : null),
              tooltip: liked ? '좋아요 취소' : '좋아요',
              onPressed: () async {
                await ApiService.toggleLike(widget.postId);
                _loadPost();
              },
            );
          }),
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
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('신고가 접수되었습니다')));
                    }
                  } catch (e) { debugPrint('post_detail: $e'); }
                }
              } else if (v == 'block') {
                if (postUserId is int) await _blockAuthor(postUserId);
              }
            },
            itemBuilder: (_) => [
              if (isMyPost) ...[
                const PopupMenuItem(value: 'edit', child: Text('수정')),
                const PopupMenuItem(value: 'delete',
                    child: Text('삭제', style: TextStyle(color: Colors.red))),
              ] else ...[
                const PopupMenuItem(value: 'report', child: Text('신고')),
                const PopupMenuItem(value: 'block',
                    child: Text('이 사용자 차단', style: TextStyle(color: Colors.red))),
              ],
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadPost,
              child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _post!['title'] ?? '',
                  style: const TextStyle(fontSize: Typo.h2, fontWeight: Typo.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_post!['author'] ?? ''} | ${(_post!['created_at'] ?? '').toString().length >= 10 ? (_post!['created_at'] as String).substring(0, 10) : ''}',
                  style: TextStyle(color: Colors.grey[600], fontSize: Typo.small),
                ),
                const Divider(),
                MentionText(
                  text: _post!['content'] ?? '',
                  style: const TextStyle(fontSize: Typo.subtitle, height: 1.6),
                ),
                Builder(builder: (_) {
                  final imgs = (_post!['image_urls'] as List?)?.cast<String>()
                      ?? (_post!['image_url'] != null ? <String>[_post!['image_url'] as String] : <String>[]);
                  if (imgs.isEmpty) return const SizedBox.shrink();
                  return Column(children: [
                    const SizedBox(height: 12),
                    ...imgs.map((u) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: netImage(u, fit: BoxFit.cover, width: double.infinity,
                          error: () => const SizedBox.shrink()),
                      ),
                    )),
                  ]);
                }),
                const SizedBox(height: 8),
                Text('❤️ ${_post!['likes'] ?? 0}',
                    style: const TextStyle(color: Colors.red)),
                const Divider(),
                Text('댓글 ${comments.length}개',
                    style: const TextStyle(fontWeight: Typo.bold)),
                const SizedBox(height: 8),
                ...comments.map((c) {
                  final isMyComment = myUserId != null && myUserId == c['user_id'];
                  final likedByMe = c['liked_by_me'] as bool? ?? false;
                  final likesCount = (c['likes_count'] as num?)?.toInt() ?? 0;
                  return ListTile(
                    onLongPress: isMyComment ? null : () {
                      final cid = c['user_id'];
                      if (cid is int) {
                        showModalBottomSheet(
                          context: context,
                          builder: (_) => SafeArea(
                            child: Wrap(children: [
                              ListTile(
                                leading: const Icon(Icons.block, color: Colors.red),
                                title: const Text('이 사용자 차단'),
                                onTap: () {
                                  Navigator.pop(context);
                                  _blockAuthor(cid, name: c['author'] as String?);
                                },
                              ),
                            ]),
                          ),
                        );
                      }
                    },
                    title: MentionText(
                      text: c['content'] ?? '',
                      style: const TextStyle(fontSize: Typo.subtitle),
                    ),
                    subtitle: Text('${c['author'] ?? ''}  ${(c['created_at'] ?? '').toString().length >= 10 ? (c['created_at'] as String).substring(0, 10) : ''}',
                        style: const TextStyle(fontSize: Typo.caption)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            try {
                              await ApiService.toggleCommentLike(c['id']);
                              _loadPost();
                            } catch (e) { debugPrint('post_detail: $e'); }
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(likedByMe ? Icons.favorite : Icons.favorite_border,
                                  size: 16, color: likedByMe ? Colors.red : Colors.grey),
                              if (likesCount > 0) ...[
                                const SizedBox(width: 2),
                                Text('$likesCount', style: const TextStyle(fontSize: Typo.caption, color: Colors.grey)),
                              ],
                            ],
                          ),
                        ),
                        if (isMyComment)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                            tooltip: '댓글 삭제',
                            onPressed: () => _deleteComment(c['id']),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: const InputDecoration(
                      hintText: '댓글을 입력하세요',
                      border: OutlineInputBorder(),
                      isDense: true,
                      // 커서가 박스 상하단을 삐져나가던 것 — 수직 여유 (06-13)
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  tooltip: '댓글 등록',
                  onPressed: _submitComment,
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}
