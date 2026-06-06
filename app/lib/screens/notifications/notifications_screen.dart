import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../utils/local_cache.dart';
import '../game/game_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List _notifications = [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = false; });
    try {
      final data = await ApiService.getNotifications();
      if (mounted) setState(() { _notifications = data['notifications'] ?? []; _loading = false; _error = false; });
      if (mounted && _notifications.isNotEmpty) _maybeShowSwipeHint();
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  /// 스와이프 삭제 발견성 — 첫 방문 1회 힌트
  Future<void> _maybeShowSwipeHint() async {
    if (await LocalCache.hasFlag('hint_notif_swipe')) return;
    await LocalCache.setFlag('hint_notif_swipe');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('💡 알림을 왼쪽으로 밀면 삭제할 수 있어요'),
      duration: Duration(seconds: 4),
    ));
  }

  Future<void> _readAll() async {
    try {
      await ApiService.readAllNotifications();
      if (mounted) {
        setState(() {
          for (final n in _notifications) {
            (n as Map)['is_read'] = true;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('처리 실패. 다시 시도해주세요')));
      }
    }
  }

  Future<void> _deleteRead() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('읽은 알림 삭제'),
        content: const Text('읽은 알림을 모두 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final n = await ApiService.deleteReadNotifications();
      if (mounted) {
        setState(() => _notifications.removeWhere((x) => (x['is_read'] as bool) == true));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$n개 삭제')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제 실패')));
    }
  }

  /// API 삭제 성공 여부 반환 — Dismissible confirmDismiss에서 사용.
  /// 실패 시 false → 위젯 dismiss 안 됨 (리스트-트리 불일치 크래시 방지)
  Future<bool> _deleteOne(int id) async {
    try {
      await ApiService.deleteNotification(id);
      return true;
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제 실패')));
      return false;
    }
  }

  Future<void> _onTap(Map n) async {
    if (!(n['is_read'] as bool)) {
      await ApiService.readNotification(n['id'] as int);
      setState(() => n['is_read'] = true);
    }
    final gameId = n['game_id'];
    if (gameId != null && mounted) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => GameDetailScreen(gameId: gameId as int),
      ));
    }
  }

  /// emoji는 기기별 렌더 상이 + 디자인 톤 이탈 → Material icon + 타입색
  (IconData, Color) _typeIcon(String? type) {
    switch (type) {
      case 'game_start':      return (Icons.sports_baseball, const Color(0xFF1976D2));
      case 'score_change':    return (Icons.local_fire_department, const Color(0xFFE53935));
      case 'comeback':        return (Icons.bolt, const Color(0xFFFFA000));
      case 'game_end':        return (Icons.flag, const Color(0xFF455A64));
      case 'extra_innings':   return (Icons.update, const Color(0xFF7B1FA2));
      case 'cancelled':       return (Icons.umbrella, const Color(0xFF607D8B));
      case 'rank_change':     return (Icons.leaderboard, const Color(0xFF1976D2));
      case 'winning_streak':  return (Icons.trending_up, const Color(0xFFE53935));
      case 'losing_streak':   return (Icons.trending_down, const Color(0xFF607D8B));
      case 'roster_change':   return (Icons.swap_horiz, const Color(0xFF00897B));
      case 'new_comment':     return (Icons.chat_bubble_outline, const Color(0xFF1976D2));
      default:                return (Icons.notifications, const Color(0xFF6B6B73));
    }
  }

  String _relativeTime(String createdAt) {
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return '방금';
      if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
      if (diff.inHours < 24) return '${diff.inHours}시간 전';
      return '${diff.inDays}일 전';
    } catch (_) {
      return createdAt.length >= 10 ? createdAt.substring(5, 10) : createdAt;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _notifications.any((n) => !(n['is_read'] as bool));
    final hasRead = _notifications.any((n) => (n['is_read'] as bool));
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림'),
        actions: [
          if (hasUnread)
            TextButton(onPressed: _readAll, child: const Text('모두 읽음')),
          if (hasRead)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                if (v == 'delete_read') _deleteRead();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete_read', child: Text('읽은 알림 삭제')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off, size: 56, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text('알림을 불러오지 못했습니다', style: TextStyle(color: Colors.grey[500])),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('다시 시도'),
                      ),
                    ],
                  ),
                )
              : _notifications.isEmpty
              ? RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: [
                      SizedBox(
                        height: 400,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.notifications_none, size: 56, color: Colors.grey),
                              const SizedBox(height: 12),
                              Text('알림이 없습니다', style: TextStyle(color: Colors.grey[500])),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _notifications.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
                    itemBuilder: (_, i) {
                      final n = _notifications[i] as Map;
                      final unread = !(n['is_read'] as bool);
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      return Dismissible(
                        key: ValueKey('notif_${n['id']}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: const Color(0xFFE53935),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: const Icon(Icons.delete_outline, color: Colors.white),
                        ),
                        confirmDismiss: (_) => _deleteOne(n['id'] as int),
                        onDismissed: (_) => setState(() => _notifications.removeWhere((x) => x['id'] == n['id'])),
                        child: InkWell(
                        onTap: () => _onTap(n),
                        child: Container(
                          color: unread
                              ? (isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.black.withValues(alpha: 0.04))
                              : null,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Builder(builder: (_) {
                                final (icon, color) = _typeIcon(n['type'] as String?);
                                return Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: isDark ? 0.18 : 0.10),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(icon, size: 19, color: color),
                                );
                              }),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            n['title'] as String,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: unread
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                        if (unread)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: isDark ? Colors.white : Colors.black,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      n['body'] as String? ?? '',
                                      style: TextStyle(
                                          fontSize: 13, color: Colors.grey[600]),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _relativeTime(n['created_at'] as String),
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                              if (n['game_id'] != null)
                                const Icon(Icons.chevron_right,
                                    size: 18, color: Colors.grey),
                            ],
                          ),
                        ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
