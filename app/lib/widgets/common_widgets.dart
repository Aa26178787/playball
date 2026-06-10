import 'package:flutter/material.dart';
import '../utils/web_image.dart';
import '../utils/design_tokens.dart';
import '../utils/team_theme.dart';

/// 통합 에러 위젯 — silent fail 대신 retry 안내
class AppErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  const AppErrorView({
    super.key,
    this.message = '네트워크 연결을 확인해주세요',
    this.onRetry,
    this.icon = Icons.cloud_off_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink3 = isDark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: ink3),
            const SizedBox(height: Space.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: Typo.body, color: ink3, fontWeight: Typo.medium),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: Space.lg),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('다시 시도'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 새로고침 피드백 SnackBar — bottom margin safeArea + floating nav 동적 회피
void showRefreshSnack(BuildContext context, {bool success = true, String? message}) {
  final msg = message ?? (success ? '새로고침 완료' : '새로고침 실패');
  final bottomInset = MediaQuery.of(context).viewPadding.bottom;
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    duration: const Duration(seconds: 1),
    behavior: SnackBarBehavior.floating,
    margin: EdgeInsets.fromLTRB(16, 0, 16, 80 + bottomInset),
    backgroundColor: success ? const Color(0xFF1B5E20) : SemColor.danger,
  ));
}

/// 일관된 선수 프로필 이미지 (실패 시 person + 팀 컬러 fallback)
class PlayerAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? teamCode;
  final double size;

  const PlayerAvatar({
    super.key,
    this.imageUrl,
    this.teamCode,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final color = teamCode != null ? teamColor(teamCode) : Colors.grey;
    Widget fallback() => Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.25),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.person, color: color, size: size * 0.55),
    );
    if (imageUrl == null || imageUrl!.isEmpty) return fallback();
    return Builder(builder: (ctx) {
      final dpr = MediaQuery.of(ctx).devicePixelRatio;
      final cacheSize = (size * dpr).toInt().clamp(80, 800);
      return ClipOval(
        child: netImage(
          imageUrl!,
          width: size, height: size, fit: BoxFit.cover,
          // memCacheWidth만 지정 — width+height 동시 지정 시 비정사각 원본이
          // 정사각으로 강제 디코드되어 가로 왜곡(stretch). 한 축만 줘 비율 보존.
          memCacheWidth: cacheSize,
          error: () => fallback(),
          placeholder: () => fallback(),
        ),
      );
    });
  }
}

/// 통일된 bottom sheet drag handle
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 36, height: 4,
      margin: const EdgeInsets.only(top: 10, bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white24 : Colors.black26,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// 최소 터치 영역 확보 wrapper (44x44 보장)
class TapTarget extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final double minSize;

  const TapTarget({
    super.key,
    required this.child,
    required this.onTap,
    this.minSize = kMinTapTarget,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(minSize / 2),
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minSize, minHeight: minSize),
        child: Center(child: child),
      ),
    );
  }
}
