import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/web_image.dart';
import '../../api/api_service.dart';

/// 차단한 사용자 목록 + 차단 해제.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<Map<String, dynamic>> _blocks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await ApiService.getBlocks();
      if (mounted) setState(() { _blocks = b; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unblock(int userId) async {
    try {
      await ApiService.unblockUser(userId);
      if (mounted) {
        setState(() => _blocks.removeWhere((e) => e['user_id'] == userId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('차단을 해제했습니다')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('해제 실패')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('차단한 사용자')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _blocks.isEmpty
              ? Center(child: Text('차단한 사용자가 없습니다',
                  style: TextStyle(color: Theme.of(context).hintColor)))
              : ListView.separated(
                  itemCount: _blocks.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final b = _blocks[i];
                    final img = b['profile_image'] as String?;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: (img != null && img.isNotEmpty)
                            ? CachedNetworkImageProvider(webSafeImageUrl(img)) : null,
                        child: (img == null || img.isEmpty)
                            ? const Icon(Icons.person) : null,
                      ),
                      title: Text(b['nickname'] as String? ?? '알 수 없음'),
                      trailing: OutlinedButton(
                        onPressed: () => _unblock(b['user_id'] as int),
                        child: const Text('차단 해제'),
                      ),
                    );
                  },
                ),
    );
  }
}
