import 'package:flutter/material.dart';
import '../utils/local_cache.dart';
import '../api/api_service.dart';
import '../utils/design_tokens.dart';

/// #2 온보딩 — 첫 로그인 후 마이팀 미설정 시 SnackBar 안내
class OnboardingHelper {
  static Future<void> maybeShowFirstTimeHint(
    BuildContext context, {
    VoidCallback? onSettingsTap,
  }) async {
    final done = await LocalCache.hasFlag('onboarding_done');
    if (done) return;
    try {
      final teams = await ApiService.getFavoriteTeams();
      if (teams.isEmpty && context.mounted) {
        final bottomInset = MediaQuery.of(context).viewPadding.bottom;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('💡 마이팀을 설정하면 개인화 알림과 마이팀 카드를 받을 수 있어요'),
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(16, 0, 16, 100 + bottomInset),
          backgroundColor: const Color(0xFF111113),
          action: SnackBarAction(
            label: '설정',
            textColor: SemColor.warning,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              onSettingsTap?.call();
            },
          ),
        ));
        await LocalCache.setFlag('onboarding_done');
      }
    } catch (_) {}
  }
}
