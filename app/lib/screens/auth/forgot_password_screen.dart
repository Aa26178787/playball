import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import 'package:dio/dio.dart';
import '../../api/api_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _pwConfirmCtrl = TextEditingController();

  int _step = 0; // 0=이메일입력, 1=코드입력, 2=완료
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      await ApiService.sendPasswordResetCode(email);
      if (mounted) setState(() => _step = 1);
    } on DioException catch (e) {
      if (mounted) setState(() => _error = e.response?.data?['detail'] ?? '발송 실패');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final pw = _pwCtrl.text;
    if (pw != _pwConfirmCtrl.text) {
      setState(() => _error = '비밀번호가 일치하지 않습니다');
      return;
    }
    if (pw.length < 8) {
      setState(() => _error = '비밀번호는 8자 이상이어야 합니다');
      return;
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(pw)) {
      setState(() => _error = '비밀번호에 영문자를 포함해야 합니다');
      return;
    }
    if (!RegExp(r'[0-9]').hasMatch(pw)) {
      setState(() => _error = '비밀번호에 숫자를 포함해야 합니다');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ApiService.resetPassword(
          _emailCtrl.text.trim(), _codeCtrl.text.trim(), pw);
      setState(() => _step = 2);
    } on DioException catch (e) {
      setState(() => _error = e.response?.data?['detail'] ?? '재설정 실패');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('비밀번호 찾기')),
      body: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: _step == 2 ? _buildDone() : _buildForm(),
      ),
    );
  }

  Widget _buildDone() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 72),
        const SizedBox(height: Space.lg),
        const Text('비밀번호가 변경되었습니다', style: TextStyle(fontSize: Typo.lg, fontWeight: Typo.bold)),
        const SizedBox(height: Space.xl),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: const Text('로그인 화면으로'),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 진행 표시
        Row(
          children: [
            _stepDot(0, '이메일'),
            const Expanded(child: Divider()),
            _stepDot(1, '인증+재설정'),
          ],
        ),
        const SizedBox(height: Space.xxl),

        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          enabled: _step == 0,
          decoration: const InputDecoration(
            labelText: '가입한 이메일',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),

        if (_step == 0) ...[
          const SizedBox(height: Space.lg),
          ElevatedButton(
            onPressed: _loading ? null : _sendCode,
            style: _btnStyle(),
            child: _loading
                ? CircularProgressIndicator(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? SemColor.panelDark : Colors.white,
                    strokeWidth: 2)
                : const Text('인증번호 발송'),
          ),
        ],

        if (_step == 1) ...[
          const SizedBox(height: Space.lg),
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: Typo.h2, letterSpacing: 8, fontWeight: Typo.bold),
            decoration: const InputDecoration(
              labelText: '인증번호 6자리',
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _pwCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: '새 비밀번호',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                tooltip: _obscure ? '비밀번호 표시' : '비밀번호 숨기기',
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _pwConfirmCtrl,
            obscureText: _obscure,
            decoration: const InputDecoration(
              labelText: '새 비밀번호 확인',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: Space.lg),
          ElevatedButton(
            onPressed: _loading ? null : _resetPassword,
            style: _btnStyle(Colors.green),
            child: _loading
                ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                : const Text('비밀번호 변경'),
          ),
          TextButton(
            onPressed: _loading ? null : () => setState(() { _step = 0; _error = null; }),
            child: const Text('이메일 다시 입력'),
          ),
        ],

        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red)),
          ),
      ],
    );
  }

  Widget _stepDot(int step, String label) {
    final active = _step >= step;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 활성 = theme-aware 액센트(다크 시 밝은 톤 — panelDark는 다크 배경서 윤곽소실)
    final accent = SemColor.brand(context);
    final onAccent = isDark ? SemColor.panelDark : Colors.white;
    return Column(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: active ? accent : Colors.grey[300],
          child: Text('${step + 1}',
              style: TextStyle(color: active ? onAccent : Colors.grey, fontSize: Typo.small)),
        ),
        const SizedBox(height: Space.xs),
        Text(label, style: TextStyle(fontSize: Typo.caption, color: active ? accent : Colors.grey)),
      ],
    );
  }

  // color 지정 시 그 색(+흰 글씨), 미지정 시 글로벌 theme-aware 버튼 상속(다크 윤곽소실 방지)
  ButtonStyle _btnStyle([Color? color]) => ElevatedButton.styleFrom(
    backgroundColor: color,
    foregroundColor: color != null ? Colors.white : null,
    minimumSize: const Size.fromHeight(48),
  );
}
