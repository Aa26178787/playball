import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import '../../utils/app_theme.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../api/api_service.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  bool _autoLogin = false;
  bool _hasSavedCredentials = false;
  bool _autoLoggingIn = false;

  @override
  void initState() {
    super.initState();
    _checkSavedCredentials();
  }

  Future<void> _checkSavedCredentials() async {
    final creds = await ApiService.getAutoLoginCredentials();
    if (!mounted) return;
    if (creds != null) {
      setState(() {
        _hasSavedCredentials = true;
        _autoLogin = true;
        _emailController.text = creds['email']!;
        _passwordController.text = creds['password']!;
      });
      _autoLoginNow(creds['email']!, creds['password']!);
    }
  }

  Future<void> _autoLoginNow(String email, String password) async {
    setState(() => _autoLoggingIn = true);
    final auth = context.read<AuthProvider>();
    final success = await auth.login(email, password);
    if (!success && mounted) {
      setState(() {
        _autoLoggingIn = false;
        _error = '자동 로그인 실패. 다시 입력해 주세요.';
      });
      await ApiService.clearAutoLoginCredentials();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final auth = context.read<AuthProvider>();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final success = await auth.login(email, password);
    if (success && _autoLogin) {
      await ApiService.saveAutoLoginCredentials(email, password);
    }
    if (!success && mounted) {
      setState(() {
        _error = auth.errorMessage ?? '이메일 또는 비밀번호가 틀렸습니다';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isLoading = auth.isLoading || _autoLoggingIn;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brand = isDark ? AppColors.primaryDark : SemColor.panelDark;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sports_baseball, size: 80, color: brand),
              const SizedBox(height: Space.sm),
              Text(
                'PlayBall',
                style: TextStyle(fontSize: 32, fontWeight: Typo.bold, color: brand),
              ),
              const SizedBox(height: 48),

              // 이메일
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: '이메일',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Space.lg),

              // 비밀번호
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '비밀번호',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Space.xs),

              // 자동 로그인 체크박스
              Row(
                children: [
                  Checkbox(
                    value: _autoLogin,
                    onChanged: (v) => setState(() => _autoLogin = v ?? false),
                    activeColor: SemColor.brand(context),
                  ),
                  const Text('자동 로그인', style: TextStyle(fontSize: Typo.subtitle)),
                  if (_hasSavedCredentials) ...[
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        await ApiService.clearAutoLoginCredentials();
                        if (mounted) setState(() { _hasSavedCredentials = false; _autoLogin = false; });
                      },
                      child: const Text('저장 해제', style: TextStyle(fontSize: Typo.small, color: Colors.grey)),
                    ),
                  ],
                ],
              ),

              // 오류 메시지
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: Typo.body)),
                ),

              // 로그인 버튼
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _login,
                  // bg/fg는 글로벌 theme-aware 버튼 상속 (다크 윤곽소실 방지)
                  child: isLoading
                      ? CircularProgressIndicator(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? SemColor.panelDark : Colors.white)
                      : const Text('로그인', style: TextStyle(fontSize: Typo.title)),
                ),
              ),
              const SizedBox(height: Space.lg),

              // 비밀번호 찾기
              TextButton(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
                child: const Text('비밀번호를 잊으셨나요?', style: TextStyle(color: Colors.grey)),
              ),

              // 회원가입
              TextButton(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const RegisterScreen())),
                child: const Text('계정이 없으신가요? 회원가입'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
