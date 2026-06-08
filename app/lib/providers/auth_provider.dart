import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../api/api_service.dart';
import '../models/user.dart';
import '../utils/local_cache.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  bool _isLoggedIn = false;
  bool _isLoading = false;
  bool _isInitializing = true;
  String? _errorMessage;

  User? get user => _user;
  int? get userId => _user?.id;
  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  String? get errorMessage => _errorMessage;

  // 앱 시작 시 로그인 상태 확인
  Future<void> checkLoginStatus() async {
    ApiService.initInterceptor(() async => logout());

    // access token 없으면 refresh로 먼저 시도
    var token = await ApiService.getToken();
    if (token == null) {
      final refreshed = await ApiService.tryRefreshToken();
      if (refreshed) token = await ApiService.getToken();
    }

    if (token != null) {
      try {
        final data = await ApiService.getMe();
        _user = User.fromJson(data);
        _isLoggedIn = true;
      } catch (e) {
        if (e is DioException) {
          final status = e.response?.statusCode;
          if (status == 401 || status == 403) {
            // 인증 오류만 토큰 삭제 + 로그아웃
            await ApiService.deleteToken();
            _isLoggedIn = false;
          } else {
            // 네트워크 오류 등 → 토큰 유효하다고 가정, 로그인 유지
            _isLoggedIn = true;
          }
        } else {
          _isLoggedIn = false;
        }
      }
    }
    _isInitializing = false;
    notifyListeners();
  }

  // 회원가입
  Future<bool> register(String email, String password, String nickname) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await ApiService.register(email, password, nickname);
      await ApiService.saveToken(data['access_token']);
      if (data['refresh_token'] != null) await ApiService.saveRefreshToken(data['refresh_token']);
      _user = User(
        id: data['user_id'],
        email: email,
        nickname: data['nickname'],
      );
      _isLoggedIn = true;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      if (e is DioException) {
        _errorMessage = e.response?.data?['detail'] ?? '회원가입에 실패했습니다';
      } else {
        _errorMessage = '회원가입에 실패했습니다';
      }
      notifyListeners();
      return false;
    }
  }

  // 로그인
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await ApiService.login(email, password);
      await ApiService.saveToken(data['access_token']);
      if (data['refresh_token'] != null) await ApiService.saveRefreshToken(data['refresh_token']);
      _user = User(
        id: data['user_id'],
        email: email,
        nickname: data['nickname'],
      );
      _isLoggedIn = true;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      if (e is DioException) {
        _errorMessage = e.response?.data?['detail'] ?? '로그인에 실패했습니다';
      } else {
        _errorMessage = '로그인에 실패했습니다';
      }
      notifyListeners();
      return false;
    }
  }

  // 로그아웃
  Future<void> logout() async {
    final prefs = await ApiService.getRefreshToken();
    if (prefs != null) {
      try { await ApiService.serverLogout(prefs); } catch (e) { debugPrint('auth_provider: $e'); }
    }
    await ApiService.deleteToken();
    await ApiService.clearAutoLoginCredentials();
    await LocalCache.clearUser();
    _user = null;
    _isLoggedIn = false;
    notifyListeners();
  }
}