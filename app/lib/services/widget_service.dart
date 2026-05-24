import 'package:shared_preferences/shared_preferences.dart';

class WidgetService {
  static const _teamKey = 'widget_team_id';

  static Future<void> setTeamId(int? teamId) async {
    final prefs = await SharedPreferences.getInstance();
    if (teamId != null && teamId > 0) {
      await prefs.setInt(_teamKey, teamId);
    } else {
      await prefs.remove(_teamKey);
    }
  }

  static Future<int?> getTeamId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_teamKey);
  }
}
