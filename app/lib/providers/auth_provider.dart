import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_service.dart';
import '../models/user.dart';
import '../utils/local_cache.dart';

class AuthProvider extends ChangeNotifier {
  static const _keepLoggedInKey = 'keep_logged_in';

  User? _user;
  bool _isLoggedIn = false;
  bool _isLoading = false;
  bool _keepLoggedIn = false;
  String? _errorMessage;

  User? get user => _user;
  int? get userId => _user?.id;
  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  bool get keepLoggedIn => _keepLoggedIn;
  String? get errorMessage => _errorMessage;

  // 앱 시작 시 로그인 상태 확인
  Future<void> checkLoginStatus() async {
    ApiService.initInterceptor(() async => logout());
    _keepLoggedIn = await _loadKeepLoggedIn();

    final token = await ApiService.getToken();
    if (token != null) {
      if (await _tryLoadUser()) {
        notifyListeners();
        return;
      }
      if (_keepLoggedIn && await ApiService.refreshTokenIfPossible() && await _tryLoadUser()) {
        notifyListeners();
        return;
      }
      _isLoggedIn = false;
      await ApiService.deleteToken();
      notifyListeners();
      return;
    }

    if (_keepLoggedIn) {
      if (await ApiService.refreshTokenIfPossible() && await _tryLoadUser()) {
        notifyListeners();
        return;
      }
    }

    _isLoggedIn = false;
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
      try { await ApiService.serverLogout(prefs); } catch (_) {}
    }
    await setKeepLoggedIn(false);
    await ApiService.deleteToken();
    await LocalCache.clearUser();
    _user = null;
    _isLoggedIn = false;
    notifyListeners();
  }

  Future<bool> _loadKeepLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keepLoggedInKey) ?? false;
  }

  Future<void> setKeepLoggedIn(bool value) async {
    _keepLoggedIn = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keepLoggedInKey, value);
    notifyListeners();
  }

  Future<bool> _tryLoadUser() async {
    try {
      final data = await ApiService.getMe();
      _user = User.fromJson(data);
      _isLoggedIn = true;
      return true;
    } catch (_) {
      return false;
    }
  }
}