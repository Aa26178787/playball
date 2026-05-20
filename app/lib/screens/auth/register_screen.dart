import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../api/api_service.dart';
import '../home/home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  String? _error;
  bool? _emailAvailable;
  bool? _nicknameAvailable;
  bool _checkingEmail = false;
  bool _checkingNickname = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _checkEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() => _checkingEmail = true);
    try {
      final available = await ApiService.checkEmailAvailable(email);
      if (mounted) setState(() { _emailAvailable = available; _checkingEmail = false; });
    } catch (_) {
      if (mounted) setState(() => _checkingEmail = false);
    }
  }

  Future<void> _checkNickname() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) return;
    setState(() => _checkingNickname = true);
    try {
      final available = await ApiService.checkNicknameAvailable(nickname);
      if (mounted) setState(() { _nicknameAvailable = available; _checkingNickname = false; });
    } catch (_) {
      if (mounted) setState(() => _checkingNickname = false);
    }
  }

  Future<void> _register() async {
    if (_emailAvailable == false || _nicknameAvailable == false) return;
    final auth = context.read<AuthProvider>();
    final success = await auth.register(
      _emailController.text.trim(),
      _passwordController.text.trim(),
      _nicknameController.text.trim(),
    );

    if (success && mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } else {
      setState(() {
        _error = auth.errorMessage ?? '회원가입에 실패했습니다';
      });
    }
  }

  Widget _checkStatus(bool? available, bool checking) {
    if (checking) return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
    if (available == null) return const SizedBox.shrink();
    return Icon(available ? Icons.check_circle : Icons.cancel,
        color: available ? Colors.green : Colors.red, size: 20);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 24),

              // 닉네임
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nicknameController,
                      onChanged: (_) => setState(() => _nicknameAvailable = null),
                      decoration: InputDecoration(
                        labelText: '닉네임',
                        prefixIcon: const Icon(Icons.person),
                        border: const OutlineInputBorder(),
                        suffixIcon: Padding(
                          padding: const EdgeInsets.all(12),
                          child: _checkStatus(_nicknameAvailable, _checkingNickname),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _checkingNickname ? null : _checkNickname,
                    child: const Text('중복확인'),
                  ),
                ],
              ),
              if (_nicknameAvailable != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _nicknameAvailable! ? '사용 가능한 닉네임입니다' : '이미 사용 중인 닉네임입니다',
                    style: TextStyle(
                        fontSize: 12,
                        color: _nicknameAvailable! ? Colors.green : Colors.red),
                  ),
                ),
              const SizedBox(height: 16),

              // 이메일
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) => setState(() => _emailAvailable = null),
                      decoration: InputDecoration(
                        labelText: '이메일',
                        prefixIcon: const Icon(Icons.email),
                        border: const OutlineInputBorder(),
                        suffixIcon: Padding(
                          padding: const EdgeInsets.all(12),
                          child: _checkStatus(_emailAvailable, _checkingEmail),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _checkingEmail ? null : _checkEmail,
                    child: const Text('중복확인'),
                  ),
                ],
              ),
              if (_emailAvailable != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _emailAvailable! ? '사용 가능한 이메일입니다' : '이미 사용 중인 이메일입니다',
                    style: TextStyle(
                        fontSize: 12,
                        color: _emailAvailable! ? Colors.green : Colors.red),
                  ),
                ),
              const SizedBox(height: 16),

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
              const SizedBox(height: 8),

              // 오류 메시지
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              const SizedBox(height: 16),

              // 회원가입 버튼
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: auth.isLoading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                  ),
                  child: auth.isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('회원가입', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}