import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../game/game_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.getNotifications();
      if (mounted) setState(() { _notifications = data['notifications'] ?? []; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _readAll() async {
    await ApiService.readAllNotifications();
    setState(() {
      for (final n in _notifications) {
        (n as Map)['is_read'] = true;
      }
    });
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

  String _typeIcon(String? type) {
    switch (type) {
      case 'game_start':      return '⚾';
      case 'score_change':    return '🔥';
      case 'comeback':        return '⚡';
      case 'game_end':        return '🏁';
      case 'extra_innings':   return '🔄';
      case 'cancelled':       return '🌧️';
      case 'rank_change':     return '📊';
      case 'winning_streak':  return '🔥';
      case 'losing_streak':   return '😰';
      case 'roster_change':   return '📋';
      case 'new_comment':     return '💬';
      default:                return '🔔';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _readAll,
              child: const Text('모두 읽음'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.notifications_none, size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text('알림이 없습니다', style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
                    itemBuilder: (_, i) {
                      final n = _notifications[i] as Map;
                      final unread = !(n['is_read'] as bool);
                      return InkWell(
                        onTap: () => _onTap(n),
                        child: Container(
                          color: unread
                              ? const Color(0xFF1A237E).withValues(alpha: 0.04)
                              : null,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_typeIcon(n['type'] as String?),
                                  style: const TextStyle(fontSize: 22)),
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
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF1A237E),
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
                                          fontSize: 11, color: Colors.grey[400]),
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
                      );
                    },
                  ),
                ),
    );
  }
}
