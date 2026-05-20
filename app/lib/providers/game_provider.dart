import 'package:flutter/material.dart';
import '../api/api_service.dart';
import '../models/game.dart';

class GameProvider extends ChangeNotifier {
  List<Game> _todayGames = [];
  bool _isLoading = false;
  String? _error;

  List<Game> get todayGames => _todayGames;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchTodayGames() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await ApiService.getTodayGames();
      _todayGames = (data['games'] as List)
          .map((g) => Game.fromJson(g))
          .toList();
    } catch (e) {
      _error = '경기 정보를 불러오지 못했습니다';
    }

    _isLoading = false;
    notifyListeners();
  }
}