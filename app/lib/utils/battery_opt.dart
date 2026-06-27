import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'local_cache.dart';

/// 안드로이드 배터리 최적화/절전(App Standby) 예외 요청 — 앱당 1회.
///
/// 배경: 앱을 수 시간 안 쓰면 안드로이드/삼성이 standby 버킷으로 강등하거나
/// '잠자는 앱'으로 절전시켜 FCM 연결이 끊김 → 푸시가 끊긴다(저녁 경기 알림 미수신 사례).
/// per-app '배터리 제한 없음'만으론 부족 — 배터리 최적화 예외가 필요.
/// 사용자가 허용하면 OS가 절전 대상에서 제외 → 백그라운드 FCM이 안정적으로 유지된다.
Future<void> maybePromptBatteryOptimization(BuildContext context) async {
  if (kIsWeb || !Platform.isAndroid) return;
  if (await LocalCache.hasFlag('batt_opt_prompted')) return;
  try {
    // 이미 예외 처리됐으면 조용히 플래그만 세팅하고 종료
    if (await Permission.ignoreBatteryOptimizations.isGranted) {
      await LocalCache.setFlag('batt_opt_prompted');
      return;
    }
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('알림 안정성 설정'),
        content: const Text(
          '경기·득점 등 백그라운드 푸시 알림을 놓치지 않으려면 '
          '배터리 최적화 예외가 필요해요.\n\n'
          '다음 화면에서 "허용"을 누르면 앱이 절전 상태로 꺼지지 않아 '
          '알림이 안정적으로 도착합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('나중에'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('설정하기'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  } catch (e) {
    debugPrint('battery_opt: $e');
  } finally {
    // 허용/거부/오류 무관하게 1회만 노출 (반복 nag 방지)
    await LocalCache.setFlag('batt_opt_prompted');
  }
}
