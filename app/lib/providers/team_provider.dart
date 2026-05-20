import 'package:flutter/material.dart';
import '../api/api_service.dart';
import '../models/team.dart';

class TeamProvider extends ChangeNotifier {
  List<Team> _teams = [];
  bool _isLoading = false;

  List<Team> get teams => _teams;
  bool get isLoading => _isLoading;

  Future<void> fetchTeams() async {
    _isLoading = true;
    notifyListeners();

    try {
      final data = await ApiService.getTeams();
      _teams = (data['teams'] as List)
          .map((t) => Team.fromJson(t))
          .toList();
    } catch (e) {
      print('팀 순위 오류: $e');
    }

    _isLoading = false;
    notifyListeners();
  }
}