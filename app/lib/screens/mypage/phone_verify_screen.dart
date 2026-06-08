import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import 'package:dio/dio.dart';
import '../../api/api_service.dart';

class PhoneVerifyScreen extends StatefulWidget {
  final VoidCallback? onVerified;
  const PhoneVerifyScreen({super.key, this.onVerified});

  @override
  State<PhoneVerifyScreen> createState() => _PhoneVerifyScreenState();
}

class _PhoneVerifyScreenState extends State<PhoneVerifyScreen> {
  final _codeCtrl = TextEditingController();

  String? _sentToEmail;
  bool _sending = false;
  bool _verifying = false;
  String? _error;

  Future<void> _sendCode() async {
    setState(() { _sending = true; _error = null; });
    try {
      final res = await ApiService.sendEmailCode();
      setState(() => _sentToEmail = res['email'] ?? '이메일');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('인증번호를 $_sentToEmail로 발송했습니다 (5분 유효)')));
      }
    } on DioException catch (e) {
      final detail = e.response?.data?['detail'] ?? '발송 실패';
      setState(() => _error = detail);
      if (e.response?.statusCode == 429) {
        setState(() => _sentToEmail = null);
      }
    } finally {
      setState(() => _sending = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = '6자리 인증번호를 입력하세요');
      return;
    }
    setState(() { _verifying = true; _error = null; });
    try {
      await ApiService.verifyEmailCode(code);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이메일 인증 완료')));
        widget.onVerified?.call();
        Navigator.pop(context, true);
      }
    } on DioException catch (e) {
      setState(() => _error = e.response?.data?['detail'] ?? '인증 실패');
    } finally {
      setState(() => _verifying = false);
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('이메일 인증')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.mark_email_unread_outlined,
                size: 56, color: SemColor.brand(context)),
            const SizedBox(height: 16),
            const Text(
              '가입한 이메일로 인증번호를 발송합니다.\n인증 후 커뮤니티 글쓰기가 가능합니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 32),
            if (_sentToEmail == null) ...[
              ElevatedButton.icon(
                onPressed: _sending ? null : _sendCode,
                icon: _sending
                    ? SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? SemColor.panelDark : Colors.white))
                    : const Icon(Icons.send),
                label: Text(_sending ? '발송 중...' : '인증번호 발송'),
                // bg/fg는 글로벌 theme-aware 버튼 상속 (다크 윤곽소실 방지)
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ] else ...[
              Text('인증번호 발송: $_sentToEmail',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  hintText: '------',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _verifying ? null : _verifyCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _verifying
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('인증 확인', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _sending ? null : _sendCode,
                child: const Text('인증번호 재발송'),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }
}
