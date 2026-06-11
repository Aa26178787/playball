// share_card.dart — 위젯 → 이미지 캡처 공유 (메가C 성장 루프)
// 사용: showShareCardDialog(context, card: 위젯, filename: 'playball_visit')
// 웹: 파일 공유 미지원 영역 → 공유 버튼 대신 안내 (CLAUDE.md 웹 동반 원칙 고지 케이스)
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

/// 카드 미리보기 다이얼로그 + 이미지 공유.
/// [card]는 고정폭(320~340) 위젯 권장 — pixelRatio 3으로 캡처.
/// [shareText] = 함께 보낼 텍스트 (랜딩 링크 등 — 메가C 유입 루프)
Future<void> showShareCardDialog(BuildContext context,
    {required Widget card, String filename = 'playball', String? shareText}) async {
  final boundaryKey = GlobalKey();
  bool sharing = false;
  await showDialog(
    context: context,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return StatefulBuilder(builder: (ctx, setSt) {
        Future<void> doShare() async {
          if (sharing) return;
          setSt(() => sharing = true);
          try {
            final boundary = boundaryKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
            if (boundary == null) return;
            final ui.Image img = await boundary.toImage(pixelRatio: 3.0);
            final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
            final Uint8List bytes = byteData!.buffer.asUint8List();
            final dir = await getTemporaryDirectory();
            final file = File(
                '${dir.path}/${filename}_${DateTime.now().millisecondsSinceEpoch}.png');
            await file.writeAsBytes(bytes);
            await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')],
                text: shareText ?? 'PlayBall — KBO 라이브 야구');
          } catch (e) {
            debugPrint('share_card: $e');
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('공유 실패 — 다시 시도해주세요')));
            }
          } finally {
            if (ctx.mounted) setSt(() => sharing = false);
          }
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: SingleChildScrollView(
                child: RepaintBoundary(key: boundaryKey, child: card),
              ),
            ),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _DlgBtn(
                label: '닫기',
                bg: isDark ? const Color(0xFF26262C) : Colors.white,
                fg: isDark ? Colors.white : const Color(0xFF111113),
                onTap: () => Navigator.pop(ctx),
              ),
              if (!kIsWeb) ...[
                const SizedBox(width: 10),
                _DlgBtn(
                  label: sharing ? '준비 중…' : '이미지 공유',
                  bg: const Color(0xFF2563EB),
                  fg: Colors.white,
                  icon: Icons.ios_share_rounded,
                  onTap: doShare,
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text('이미지 공유는 앱에서 지원돼요',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? const Color(0xFF9A9AA0) : Colors.white)),
                ),
            ]),
          ]),
        );
      });
    },
  );
}

class _DlgBtn extends StatelessWidget {
  final String label;
  final Color bg, fg;
  final IconData? icon;
  final VoidCallback onTap;
  const _DlgBtn(
      {required this.label, required this.bg, required this.fg,
      this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
          ],
          Text(label,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: fg)),
        ]),
      ),
    );
  }
}
