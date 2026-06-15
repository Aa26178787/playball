import 'package:flutter/material.dart';

import '../../utils/design_tokens.dart';

/// 회원가입 완료 화면 — 가입 직후 1회 표시 (자동 로그인 완료 상태로 진입).
/// '시작하기' = 루트(홈)로 복귀.
class RegisterDoneScreen extends StatefulWidget {
  final String nickname;
  const RegisterDoneScreen({super.key, required this.nickname});

  @override
  State<RegisterDoneScreen> createState() => _RegisterDoneScreenState();
}

class _RegisterDoneScreenState extends State<RegisterDoneScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fade = CurvedAnimation(
        parent: _ctrl, curve: const Interval(0.3, 1, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF4F4F5) : SemColor.panelDark;
    final sub = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B6B73);
    final brand = isDark ? const Color(0xFFE5E5E7) : SemColor.panelDark;

    return PopScope(
      canPop: false, // back으로 가입 폼 복귀 방지 — 시작하기로만 진행
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 3),
                ScaleTransition(
                  scale: _scale,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 56, color: Color(0xFF16A34A)),
                  ),
                ),
                const SizedBox(height: 28),
                FadeTransition(
                  opacity: _fade,
                  child: Column(children: [
                    Text('회원가입 완료!',
                        style: TextStyle(
                            fontSize: Typo.h1,
                            fontWeight: Typo.extra,
                            color: ink)),
                    const SizedBox(height: 10),
                    Text('${widget.nickname}님, 환영합니다',
                        style: TextStyle(
                            fontSize: Typo.subtitle,
                            fontWeight: Typo.medium,
                            color: sub)),
                    const SizedBox(height: 6),
                    Text('마이팀을 설정하면 맞춤 경기 알림을 받을 수 있어요',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: Typo.body, color: sub)),
                  ]),
                ),
                const Spacer(flex: 4),
                FadeTransition(
                  opacity: _fade,
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brand,
                        foregroundColor: isDark ? Colors.black : Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: () =>
                          Navigator.of(context).popUntil((r) => r.isFirst),
                      child: const Text('시작하기',
                          style: TextStyle(
                              fontSize: Typo.title, fontWeight: Typo.extra)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
