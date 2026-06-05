import 'package:flutter/material.dart';
import '../utils/local_cache.dart';
import '../api/api_service.dart';

/// #2 온보딩 — 첫 로그인 후 마이팀 미설정 시 SnackBar 안내
class OnboardingHelper {
  static Future<void> maybeShowFirstTimeHint(BuildContext context) async {
    final done = await LocalCache.hasFlag('onboarding_done');
    if (done) return;
    try {
      final teams = await ApiService.getFavoriteTeams();
      if (teams.isEmpty && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('💡 마이팀을 설정하면 개인화 알림과 마이팀 카드를 받을 수 있어요'),
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          backgroundColor: const Color(0xFF111113),
          action: SnackBarAction(
            label: '설정',
            textColor: const Color(0xFFFFA000),
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              // 마이페이지로 이동 — Navigator는 호출처에서 처리
            },
          ),
        ));
        await LocalCache.setFlag('onboarding_done');
      }
    } catch (_) {}
  }
}
