import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../api/api_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailCtrl      = TextEditingController();
  final _nicknameCtrl   = TextEditingController();
  final _pwCtrl         = TextEditingController();
  final _pwConfirmCtrl  = TextEditingController();

  bool? _emailAvailable;
  bool? _nicknameAvailable;
  bool _checkingEmail    = false;
  bool _checkingNickname = false;
  bool _obscure          = true;
  bool _agreedTerms      = false;
  String? _error;

  // 클라이언트 유효성
  String? get _emailError {
    final v = _emailCtrl.text.trim();
    if (v.isEmpty) return null;
    if (!v.contains('@') || !v.contains('.')) return '올바른 이메일 형식이 아닙니다';
    return null;
  }

  String? get _nicknameError {
    final v = _nicknameCtrl.text.trim();
    if (v.isEmpty) return null;
    if (v.length < 2) return '닉네임은 2자 이상이어야 합니다';
    if (v.length > 20) return '닉네임은 20자 이하여야 합니다';
    return null;
  }

  String? get _pwError {
    final v = _pwCtrl.text;
    if (v.isEmpty) return null;
    if (v.length < 8) return '8자 이상이어야 합니다';
    if (!RegExp(r'[A-Za-z]').hasMatch(v)) return '영문자를 포함해야 합니다';
    if (!RegExp(r'[0-9]').hasMatch(v)) return '숫자를 포함해야 합니다';
    return null;
  }

  // 0=취약 1=보통 2=강함
  int get _pwStrength {
    final v = _pwCtrl.text;
    if (v.length < 8) return 0;
    int score = 0;
    if (RegExp(r'[A-Za-z]').hasMatch(v)) score++;
    if (RegExp(r'[0-9]').hasMatch(v)) score++;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(v)) score++;
    if (v.length >= 12) score++;
    if (score <= 1) return 0;
    if (score == 2) return 1;
    return 2;
  }

  String? get _pwConfirmError {
    if (_pwConfirmCtrl.text.isEmpty) return null;
    if (_pwCtrl.text != _pwConfirmCtrl.text) return '비밀번호가 일치하지 않습니다';
    return null;
  }

  bool get _canRegister =>
      _emailAvailable == true &&
      _nicknameAvailable == true &&
      _emailError == null &&
      _nicknameError == null &&
      _pwError == null &&
      _pwConfirmError == null &&
      _pwCtrl.text.isNotEmpty &&
      _pwConfirmCtrl.text.isNotEmpty &&
      _agreedTerms;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nicknameCtrl.dispose();
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkEmail() async {
    if (_emailError != null || _emailCtrl.text.trim().isEmpty) return;
    setState(() => _checkingEmail = true);
    try {
      final ok = await ApiService.checkEmailAvailable(_emailCtrl.text.trim());
      if (mounted) setState(() { _emailAvailable = ok; _checkingEmail = false; });
    } catch (_) {
      if (mounted) setState(() => _checkingEmail = false);
    }
  }

  Future<void> _checkNickname() async {
    if (_nicknameError != null || _nicknameCtrl.text.trim().isEmpty) return;
    setState(() => _checkingNickname = true);
    try {
      final ok = await ApiService.checkNicknameAvailable(_nicknameCtrl.text.trim());
      if (mounted) setState(() { _nicknameAvailable = ok; _checkingNickname = false; });
    } catch (_) {
      if (mounted) setState(() => _checkingNickname = false);
    }
  }

  Future<void> _register() async {
    if (!_canRegister) return;
    setState(() => _error = null);
    final auth = context.read<AuthProvider>();
    final success = await auth.register(
      _emailCtrl.text.trim(),
      _pwCtrl.text,
      _nicknameCtrl.text.trim(),
    );
    if (!success && mounted) {
      setState(() => _error = auth.errorMessage ?? '회원가입에 실패했습니다');
    }
  }

  Widget _availIcon(bool? available, bool checking) {
    if (checking) {
      return const SizedBox(width: 18, height: 18,
        child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (available == null) return const SizedBox.shrink();
    return Icon(available ? Icons.check_circle : Icons.cancel,
        color: available ? Colors.green : Colors.red, size: 20);
  }

  Widget _buildStrengthMeter() {
    final s = _pwStrength;
    final labels = ['취약', '보통', '강함'];
    final colors = [Colors.red, Colors.orange, Colors.green];
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (s + 1) / 3,
            backgroundColor: Colors.grey[200],
            color: colors[s],
            minHeight: 6,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text(labels[s], style: TextStyle(fontSize: 11, color: colors[s], fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _hint(String? msg, bool? ok) {
    if (msg == null && ok == null) return const SizedBox.shrink();
    final text = msg ?? (ok == true ? '사용 가능합니다' : '이미 사용 중입니다');
    final color = (msg != null || ok == false) ? Colors.red : Colors.green;
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
      child: Text(text, style: TextStyle(fontSize: 12, color: color)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),

              // ── 닉네임 ──
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _nicknameCtrl,
                    maxLength: 20,
                    onChanged: (_) => setState(() => _nicknameAvailable = null),
                    decoration: InputDecoration(
                      labelText: '닉네임 (2~20자)',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: const OutlineInputBorder(),
                      counterText: '',
                      errorText: _nicknameError,
                      suffixIcon: Padding(padding: const EdgeInsets.all(12),
                          child: _availIcon(_nicknameAvailable, _checkingNickname)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: (_checkingNickname || _nicknameError != null) ? null : _checkNickname,
                  style: _smallBtn(),
                  child: const Text('중복확인'),
                ),
              ]),
              _hint(_nicknameError != null ? null : null,
                    _nicknameError == null ? _nicknameAvailable : null),
              const SizedBox(height: 14),

              // ── 이메일 ──
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => setState(() => _emailAvailable = null),
                    decoration: InputDecoration(
                      labelText: '이메일',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: const OutlineInputBorder(),
                      errorText: _emailError,
                      suffixIcon: Padding(padding: const EdgeInsets.all(12),
                          child: _availIcon(_emailAvailable, _checkingEmail)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: (_checkingEmail || _emailError != null) ? null : _checkEmail,
                  style: _smallBtn(),
                  child: const Text('중복확인'),
                ),
              ]),
              _hint(null, _emailError == null ? _emailAvailable : null),
              const SizedBox(height: 14),

              // ── 비밀번호 ──
              TextField(
                controller: _pwCtrl,
                obscureText: _obscure,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '비밀번호 (8자 이상, 영문+숫자)',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  errorText: _pwError,
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                    tooltip: _obscure ? '비밀번호 표시' : '비밀번호 숨기기',
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              if (_pwCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 6),
                _buildStrengthMeter(),
              ],
              const SizedBox(height: 14),

              // ── 비밀번호 확인 ──
              TextField(
                controller: _pwConfirmCtrl,
                obscureText: _obscure,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '비밀번호 확인',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  errorText: _pwConfirmError,
                  suffixIcon: _pwConfirmCtrl.text.isNotEmpty
                      ? Icon(
                          _pwConfirmError == null ? Icons.check_circle : Icons.cancel,
                          color: _pwConfirmError == null ? Colors.green : Colors.red,
                          size: 20,
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 20),

              // ── 이용약관 ──
              Row(children: [
                Checkbox(
                  value: _agreedTerms,
                  onChanged: (v) => setState(() => _agreedTerms = v ?? false),
                  activeColor: SemColor.brand(context),
                ),
                const Expanded(
                  child: Text(
                    '서비스 이용약관 및 개인정보 처리방침에 동의합니다',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ]),
              const SizedBox(height: 8),

              // ── 오류 ──
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),

              // ── 가입 조건 안내 ──
              if (!_canRegister && _emailCtrl.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _emailAvailable != true
                        ? '이메일 중복확인을 해주세요'
                        : _nicknameAvailable != true
                            ? '닉네임 중복확인을 해주세요'
                            : !_agreedTerms
                                ? '이용약관에 동의해주세요'
                                : '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ),

              // ── 회원가입 버튼 ──
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: (auth.isLoading || !_canRegister) ? null : _register,
                  style: ElevatedButton.styleFrom(
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                  child: auth.isLoading
                      ? CircularProgressIndicator(
                          color: isDark ? SemColor.panelDark : Colors.white, strokeWidth: 2)
                      : const Text('회원가입', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // bg/fg는 글로벌 elevatedButtonTheme(theme-aware) 상속 — 다크모드 윤곽소실 방지
  ButtonStyle _smallBtn() => ElevatedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
    textStyle: const TextStyle(fontSize: 13),
  );
}
