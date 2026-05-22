import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../api/api_service.dart';
import '../models/user.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  bool _isLoggedIn = false;
  bool _isLoading = false;
  String? _errorMessage;

  User? get user => _user;
  int? get userId => _user?.id;
  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // 앱 시작 시 로그인 상태 확인
  Future<void> checkLoginStatus() async {
    final token = await ApiService.getToken();
    if (token != null) {
      try {
        final data = await ApiService.getMe();
        _user = User.fromJson(data);
        _isLoggedIn = true;
      } catch (e) {
        _isLoggedIn = false;
        await ApiService.deleteToken();
      }
    }
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
    await ApiService.deleteToken();
    _user = null;
    _isLoggedIn = false;
    notifyListeners();
  }
}