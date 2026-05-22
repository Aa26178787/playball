import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../api/api_service.dart';

class PhoneVerifyScreen extends StatefulWidget {
  final VoidCallback? onVerified;
  const PhoneVerifyScreen({super.key, this.onVerified});

  @override
  State<PhoneVerifyScreen> createState() => _PhoneVerifyScreenState();
}

class _PhoneVerifyScreenState extends State<PhoneVerifyScreen> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  bool _codeSent = false;
  bool _sending = false;
  bool _verifying = false;
  String? _error;

  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) return;
    setState(() { _sending = true; _error = null; });
    try {
      await ApiService.sendPhoneCode(phone);
      setState(() { _codeSent = true; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('인증번호가 발송되었습니다 (5분 내 입력)')));
      }
    } on DioException catch (e) {
      setState(() { _error = e.response?.data?['detail'] ?? 'SMS 발송 실패'; });
    } finally {
      setState(() { _sending = false; });
    }
  }

  Future<void> _verifyCode() async {
    final phone = _phoneCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (phone.isEmpty || code.isEmpty) return;
    setState(() { _verifying = true; _error = null; });
    try {
      await ApiService.verifyPhoneCode(phone, code);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('전화번호 인증 완료')));
        widget.onVerified?.call();
        Navigator.pop(context, true);
      }
    } on DioException catch (e) {
      setState(() { _error = e.response?.data?['detail'] ?? '인증 실패'; });
    } finally {
      setState(() { _verifying = false; });
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('전화번호 인증')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('전화번호 인증 후 커뮤니티 글쓰기가 가능합니다.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: '전화번호 (예: 01012345678)',
                      border: OutlineInputBorder(),
                    ),
                    enabled: !_codeSent,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _sending || _codeSent ? null : _sendCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  ),
                  child: _sending
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_codeSent ? '발송됨' : '발송'),
                ),
              ],
            ),
            if (_codeSent) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: '인증번호 6자리',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _verifying ? null : _verifyCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    ),
                    child: _verifying
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('확인'),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => setState(() { _codeSent = false; _codeCtrl.clear(); }),
                child: const Text('번호 다시 입력'),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }
}
