import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static const String baseUrl = 'https://playball.duckdns.org';
  static final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));
  static bool _interceptorAdded = false;

  static const _secure = FlutterSecureStorage();
  static String? _cachedToken;

  static void initInterceptor(Future<void> Function() onLogout) {
    if (_interceptorAdded) return;
    _interceptorAdded = true;
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (err, handler) async {
        if (err.response?.statusCode == 401) {
          final refreshed = await _tryRefresh();
          if (refreshed) {
            final opts = err.requestOptions;
            final token = await getToken();
            opts.headers['Authorization'] = 'Bearer $token';
            try {
              final res = await _dio.fetch(opts);
              return handler.resolve(res);
            } catch (_) {}
          }
          await onLogout();
        }
        return handler.next(err);
      },
    ));
  }

  static Future<bool> tryRefreshToken() => _tryRefresh();

  static Future<bool> _tryRefresh() async {
    final refreshToken = await _secure.read(key: 'refresh_token');
    if (refreshToken == null) return false;
    try {
      final res = await Dio(BaseOptions(baseUrl: baseUrl)).post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final data = res.data as Map<String, dynamic>;
      await _secure.write(key: 'access_token', value: data['access_token'] as String);
      await _secure.write(key: 'refresh_token', value: data['refresh_token'] as String);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ===== 토큰 관리 (Android Keystore / iOS Keychain + 메모리 캐시) =====
  static Future<String?> getToken() async {
    _cachedToken ??= await _secure.read(key: 'access_token');
    return _cachedToken;
  }

  static Future<void> saveToken(String token) async {
    _cachedToken = token;
    await _secure.write(key: 'access_token', value: token);
  }

  static Future<void> saveRefreshToken(String token) async {
    await _secure.write(key: 'refresh_token', value: token);
  }

  static Future<String?> getRefreshToken() async {
    return _secure.read(key: 'refresh_token');
  }

  static Future<void> deleteToken() async {
    _cachedToken = null;
    await _secure.delete(key: 'access_token');
    await _secure.delete(key: 'refresh_token');
  }

  static Future<void> serverLogout(String refreshToken) async {
    await _dio.post('/auth/logout', data: {'refresh_token': refreshToken});
  }

  static Future<Map<String, String>> authHeaders() async {
    final token = await getToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  // ===== 회원 API =====
  static Future<Map<String, dynamic>> register(
      String email, String password, String nickname) async {
    final res = await _dio.post('/auth/register', data: {
      'email': email,
      'password': password,
      'nickname': nickname,
    });
    return res.data;
  }

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    try {
      final res = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      return res.data;
    } catch (e) {
      rethrow;
    }
  }

  static Future<bool> checkEmailAvailable(String email) async {
    final res = await _dio.get('/auth/check-email', queryParameters: {'email': email});
    return res.data['available'] as bool;
  }

  static Future<bool> checkNicknameAvailable(String nickname) async {
    final res = await _dio.get('/auth/check-nickname', queryParameters: {'nickname': nickname});
    return res.data['available'] as bool;
  }

  static Future<Map<String, dynamic>> getMe() async {
    final headers = await authHeaders();
    final res = await _dio.get('/auth/me', options: Options(headers: headers));
    return res.data;
  }

  static Future<Map<String, dynamic>> updateNickname(String nickname) async {
    final headers = await authHeaders();
    final res = await _dio.put('/user/nickname',
        data: {'nickname': nickname}, options: Options(headers: headers));
    return res.data;
  }

  static Future<Map<String, dynamic>> sendEmailCode() async {
    final headers = await authHeaders();
    final res = await _dio.post('/user/email/send-code',
        options: Options(headers: headers));
    return res.data;
  }

  static Future<void> verifyEmailCode(String code) async {
    final headers = await authHeaders();
    await _dio.post('/user/email/verify',
        data: {'code': code}, options: Options(headers: headers));
  }

  // ===== 경기 API =====
  static Future<Map<String, dynamic>> getTodayGames() async {
    final res = await _dio.get('/games/today');
    return res.data;
  }

  static Future<Map<String, dynamic>> getGameDetail(int gameId) async {
    final res = await _dio.get('/games/$gameId');
    return res.data;
  }

  static Future<Map<String, dynamic>> getGamesByDate(String date) async {
    final res = await _dio.get('/games/date/$date');
    return res.data;
  }

  static Future<Map<String, dynamic>> getGameRelay(int gameId) async {
    final res = await _dio.get('/games/$gameId/relay');
    return res.data;
  }

  static Future<Map<String, dynamic>> getGamePreview(int gameId) async {
    final res = await _dio.get('/games/$gameId/preview');
    return res.data;
  }

  static Future<Map<String, dynamic>> getGameRecordDetail(int gameId) async {
    final res = await _dio.get('/games/$gameId/record_detail');
    return res.data;
  }

  static Future<Map<String, dynamic>> getGameRelayAll(int gameId) async {
    final res = await _dio.get('/games/$gameId/relay_all');
    return res.data;
  }

  static Future<Map<String, dynamic>> getGamePitchTypes(int gameId) async {
    final res = await _dio.get('/games/$gameId/pitch-types');
    return res.data;
  }

  static Future<Map<String, dynamic>?> getGameWeather(int gameId) async {
    try {
      final res = await _dio.get('/games/$gameId/weather');
      final w = res.data['weather'];
      return w != null ? Map<String, dynamic>.from(w) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> getGameRoster(int gameId) async {
    final res = await _dio.get('/games/$gameId/roster');
    return res.data;
  }

  // ===== 선수 API =====
  static Future<Map<String, dynamic>> getHitters({
    String sortBy = 'avg',
    int? teamId,
    String? position,
    int limit = 100,
    bool qualified = false,
  }) async {
    final res = await _dio.get('/players/hitters', queryParameters: {
      'sort_by': sortBy,
      'limit': limit,
      if (teamId != null) 'team_id': teamId,
      if (position != null) 'position': position,
      if (qualified) 'qualified': true,
    });
    return res.data;
  }

  static Future<Map<String, dynamic>> getPitchers({
    String sortBy = 'era',
    int? teamId,
    String? throws,
    int limit = 100,
    bool qualified = false,
  }) async {
    final res = await _dio.get('/players/pitchers', queryParameters: {
      'sort_by': sortBy,
      'limit': limit,
      if (teamId != null) 'team_id': teamId,
      if (throws != null) 'throws': throws,
      if (qualified) 'qualified': true,
    });
    return res.data;
  }

  static Future<Map<String, dynamic>> getPlayerRankings({int season = 2026}) async {
    final res = await _dio.get('/players/rankings', queryParameters: {'season': season});
    return res.data;
  }

  static Future<Map<String, dynamic>> getPlayerDetail(int playerId) async {
    final res = await _dio.get('/players/$playerId');
    return res.data;
  }

  static Future<Map<String, dynamic>> getPlayerDaily(int playerId,
      {int season = 2026}) async {
    final res = await _dio.get('/players/$playerId/daily',
        queryParameters: {'season': season});
    return res.data;
  }

  static Future<Map<String, dynamic>> searchPlayers(String query,
      {String? playerType}) async {
    final res = await _dio.get('/players/search', queryParameters: {
      'q': query,
      if (playerType != null) 'player_type': playerType,
    });
    return res.data;
  }

  // ===== 팀 API =====
  static Future<Map<String, dynamic>> getTeams() async {
    final res = await _dio.get('/teams/');
    return res.data;
  }

  static Future<Map<String, dynamic>> getTeamRankings() async {
    final res = await _dio.get('/teams/rankings');
    return res.data;
  }

  static Future<Map<String, dynamic>> getTeamPlayers(int teamId) async {
    final res = await _dio.get('/teams/$teamId/players');
    return res.data;
  }

  static Future<Map<String, dynamic>> getTeamGames(int teamId) async {
    final res = await _dio.get('/teams/$teamId/games');
    return res.data;
  }

  // ===== 유저 API =====
  static Future<Map<String, dynamic>> getFavoriteTeams() async {
    final headers = await authHeaders();
    final res = await _dio.get('/user/favorite-teams',
        options: Options(headers: headers));
    return res.data;
  }

  static Future<void> addFavoriteTeam(int teamId) async {
    final headers = await authHeaders();
    await _dio.post('/user/favorite-teams',
        data: {'team_id': teamId}, options: Options(headers: headers));
  }

  static Future<void> removeFavoriteTeam(int teamId) async {
    final headers = await authHeaders();
    await _dio.delete('/user/favorite-teams/$teamId',
        options: Options(headers: headers));
  }

  static Future<Map<String, dynamic>> getFavoritePlayers() async {
    final headers = await authHeaders();
    final res = await _dio.get('/user/favorite-players',
        options: Options(headers: headers));
    return res.data;
  }

  static Future<void> addFavoritePlayer(int playerId) async {
    final headers = await authHeaders();
    await _dio.post('/user/favorite-players',
        data: {'player_id': playerId}, options: Options(headers: headers));
  }

  static Future<void> removeFavoritePlayer(int playerId) async {
    final headers = await authHeaders();
    await _dio.delete('/user/favorite-players/$playerId',
        options: Options(headers: headers));
  }

  static Future<Map<String, dynamic>> getSettings() async {
    final headers = await authHeaders();
    final res = await _dio.get('/user/settings',
        options: Options(headers: headers));
    return res.data;
  }

  static Future<void> updateSettings(Map<String, dynamic> settings) async {
    final headers = await authHeaders();
    await _dio.put('/user/settings',
        data: settings, options: Options(headers: headers));
  }

  static Future<Map<String, dynamic>> getNotifications({int limit = 30}) async {
    final headers = await authHeaders();
    final res = await _dio.get('/user/notifications',
        queryParameters: {'limit': limit},
        options: Options(headers: headers));
    return res.data;
  }

  static Future<void> readAllNotifications() async {
    final headers = await authHeaders();
    await _dio.post('/user/notifications/read-all',
        options: Options(headers: headers));
  }

  static Future<void> readNotification(int notifId) async {
    final headers = await authHeaders();
    await _dio.patch('/user/notifications/$notifId/read',
        options: Options(headers: headers));
  }

  static Future<Map<String, dynamic>> getStadiumRecord() async {
    final headers = await authHeaders();
    final res = await _dio.get('/user/stadium-record',
        options: Options(headers: headers));
    return res.data;
  }

  static Future<Map<String, dynamic>> updateStadiumRecord(int wins, int losses, int draws) async {
    final headers = await authHeaders();
    final res = await _dio.put('/user/stadium-record',
        data: {'wins': wins, 'losses': losses, 'draws': draws},
        options: Options(headers: headers));
    return res.data;
  }

  // ===== 경기장 API =====
  static Future<Map<String, dynamic>> getStadiums() async {
    final res = await _dio.get('/stadiums/');
    return res.data;
  }

  static Future<Map<String, dynamic>> getStadiumDetail(int stadiumId) async {
    final res = await _dio.get('/stadiums/$stadiumId');
    return res.data;
  }

  static Future<Map<String, dynamic>> getStadiumNearbyFood(int stadiumId, {int radius = 1000}) async {
    final res = await _dio.get('/stadiums/$stadiumId/nearby-food', queryParameters: {'radius': radius});
    return res.data;
  }

  static Future<Map<String, dynamic>> searchFoodPlace(int stadiumId, String q) async {
    final res = await _dio.get('/stadiums/$stadiumId/food-places/search', queryParameters: {'q': q});
    return res.data;
  }

  static Future<Map<String, dynamic>> getCommunityFood(int stadiumId) async {
    final res = await _dio.get('/stadiums/$stadiumId/food-places/community');
    return res.data;
  }

  static Future<Map<String, dynamic>> submitFoodPlace(int stadiumId, Map<String, dynamic> body) async {
    final res = await _dio.post('/stadiums/$stadiumId/food-places', data: body);
    return res.data;
  }

  static Future<Map<String, dynamic>> voteFoodPlace(int placeId) async {
    final res = await _dio.post('/stadiums/food-places/$placeId/vote');
    return res.data;
  }

  // ===== 위젯 API =====
  static Future<Map<String, dynamic>> getLiveScores() async {
    final res = await _dio.get('/widget/live-scores');
    return res.data;
  }

  static Future<Map<String, dynamic>> getMyTeamScore(int teamId) async {
    final res = await _dio.get('/widget/my-team-scores/$teamId');
    return res.data;
  }

  // ===== 커뮤니티 API =====
  static Future<Map<String, dynamic>> getPosts({
    int? teamId,
    String? category,
    String sort = 'latest',
    String? q,
    int page = 1,
  }) async {
    final res = await _dio.get('/community/posts', queryParameters: {
      if (teamId != null) 'team_id': teamId,
      if (category != null) 'category': category,
      if (q != null && q.isNotEmpty) 'q': q,
      'sort': sort,
      'page': page,
    });
    return res.data;
  }

  static Future<void> reportPost(int postId, {String reason = '기타'}) async {
    final headers = await authHeaders();
    await _dio.post('/community/posts/$postId/report',
        data: {'reason': reason}, options: Options(headers: headers));
  }

  static Future<Map<String, dynamic>> getMyPosts({int page = 1}) async {
    final headers = await authHeaders();
    final res = await _dio.get('/community/my-posts',
        queryParameters: {'page': page}, options: Options(headers: headers));
    return res.data;
  }

  static Future<void> sendPasswordResetCode(String email) async {
    await _dio.post('/auth/password/send-code', data: {'email': email});
  }

  static Future<void> resetPassword(String email, String code, String newPassword) async {
    await _dio.post('/auth/password/reset',
        data: {'email': email, 'code': code, 'new_password': newPassword});
  }

  static Future<void> deleteAccount() async {
    final headers = await authHeaders();
    await _dio.delete('/auth/me', options: Options(headers: headers));
  }

  static Future<Map<String, dynamic>> getPostDetail(int postId) async {
    final res = await _dio.get('/community/posts/$postId');
    return res.data;
  }

  static Future<void> createPost(
      String title, String content, String category,
      {int? teamId, String? imageUrl}) async {
    final headers = await authHeaders();
    await _dio.post('/community/posts',
        data: {
          'title': title,
          'content': content,
          'category': category,
          if (teamId != null) 'team_id': teamId,
          if (imageUrl != null) 'image_url': imageUrl,
        },
        options: Options(headers: headers));
  }

  static Future<String> uploadPostImage(String filePath) async {
    final headers = await authHeaders();
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    final res = await _dio.post('/community/posts/upload-image',
        data: formData,
        options: Options(headers: headers));
    return res.data['image_url'] as String;
  }

  static Future<void> toggleLike(int postId) async {
    final headers = await authHeaders();
    await _dio.post('/community/posts/$postId/like',
        options: Options(headers: headers));
  }

  static Future<void> createComment(int postId, String content) async {
    final headers = await authHeaders();
    await _dio.post('/community/posts/$postId/comments',
        data: {'content': content}, options: Options(headers: headers));
  }

  static Future<void> deleteComment(int commentId) async {
    final headers = await authHeaders();
    await _dio.delete('/community/comments/$commentId',
        options: Options(headers: headers));
  }

  // ===== 등록말소 API =====
  static Future<Map<String, dynamic>> getTeamRosterChanges(int teamId, {int days = 30}) async {
    final res = await _dio.get('/teams/$teamId/roster-changes', queryParameters: {'days': days});
    return res.data;
  }

  static Future<Map<String, dynamic>> getTodayRosterChanges() async {
    final res = await _dio.get('/teams/roster-changes/today');
    return res.data;
  }

  static Future<Map<String, dynamic>> getTeamMonthlyStats(int teamId, {int season = 2026}) async {
    final res = await _dio.get('/teams/$teamId/monthly-stats', queryParameters: {'season': season});
    return res.data;
  }

  static Future<Map<String, dynamic>> getTeamHeadToHead(int teamId, {int season = 2026}) async {
    final res = await _dio.get('/teams/$teamId/head-to-head', queryParameters: {'season': season});
    return res.data;
  }

  static Future<Map<String, dynamic>> getTeamBattingOrder(int teamId, {int season = 2026}) async {
    final res = await _dio.get('/teams/$teamId/batting-order', queryParameters: {'season': season});
    return res.data;
  }

  // ===== 캘린더 API =====
  static Future<Map<String, dynamic>> getCalendar(int year, int month) async {
    final res = await _dio.get('/calendar/$year/$month');
    return res.data;
  }

  // ===== FCM API =====
  static Future<Map<String, dynamic>> getPitchLocations(int gameId) async {
    final res = await _dio.get('/games/$gameId/pitch-locations');
    return Map<String, dynamic>.from(res.data);
  }

  static Future<void> registerFcmToken(String token) async {
    try {
      final headers = await authHeaders();
      await _dio.post('/user/push-token',
          data: {'token': token}, options: Options(headers: headers));
    } catch (_) {}
  }

  static Future<void> updatePost(int postId, String title, String content) async {
    final headers = await authHeaders();
    await _dio.put('/community/posts/$postId',
        data: {'title': title, 'content': content},
        options: Options(headers: headers));
  }

  static Future<void> deletePost(int postId) async {
    final headers = await authHeaders();
    await _dio.delete('/community/posts/$postId',
        options: Options(headers: headers));
  }

  static Future<Map<String, dynamic>> getMyComments({int page = 1}) async {
    final headers = await authHeaders();
    final res = await _dio.get('/community/my-comments',
        queryParameters: {'page': page},
        options: Options(headers: headers));
    return Map<String, dynamic>.from(res.data);
  }

  // ===== 투수 구종 통계 =====
  static Future<Map<String, dynamic>> getPlayerPitchStats(int playerId, {int season = 2026}) async {
    final res = await _dio.get('/players/$playerId/pitch-stats', queryParameters: {'season': season});
    return Map<String, dynamic>.from(res.data);
  }

  // ===== 개인 캘린더 이벤트 =====
  static Future<Map<String, dynamic>> getCalendarEvents(int year, int month) async {
    final headers = await authHeaders();
    final res = await _dio.get('/user/calendar-events',
        queryParameters: {'year': year, 'month': month},
        options: Options(headers: headers));
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> createCalendarEvent(
      String date, String title, {String? endDate, String? description, String color = 'blue'}) async {
    final headers = await authHeaders();
    final res = await _dio.post('/user/calendar-events',
        data: {'event_date': date, 'end_date': endDate ?? date, 'title': title, 'description': description, 'color': color},
        options: Options(headers: headers));
    return Map<String, dynamic>.from(res.data);
  }

  static Future<void> deleteCalendarEvent(int eventId) async {
    final headers = await authHeaders();
    await _dio.delete('/user/calendar-events/$eventId', options: Options(headers: headers));
  }

  static Future<Map<String, dynamic>> getStadiumVisits({int limit = 50}) async {
    final headers = await authHeaders();
    final res = await _dio.get('/user/stadium-visits',
        queryParameters: {'limit': limit},
        options: Options(headers: headers));
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> addStadiumVisit(
      int gameId, String result, {String? memo}) async {
    final headers = await authHeaders();
    final res = await _dio.post('/user/stadium-visits',
        data: {'game_id': gameId, 'result': result, 'memo': memo},
        options: Options(headers: headers));
    return Map<String, dynamic>.from(res.data);
  }

  static Future<void> deleteStadiumVisit(int visitId) async {
    final headers = await authHeaders();
    await _dio.delete('/user/stadium-visits/$visitId', options: Options(headers: headers));
  }

  static Future<void> toggleCommentLike(int commentId) async {
    final headers = await authHeaders();
    await _dio.post('/community/comments/$commentId/like',
        options: Options(headers: headers));
  }

  static Future<Map<String, dynamic>> getMyLikes({int page = 1}) async {
    final headers = await authHeaders();
    final res = await _dio.get('/community/my-likes',
        queryParameters: {'page': page},
        options: Options(headers: headers));
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> getMatchupStats(int batterId, int pitcherId) async {
    final res = await _dio.get('/players/matchup',
        queryParameters: {'batter_id': batterId, 'pitcher_id': pitcherId});
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> search(String q) async {
    final res = await _dio.get('/search', queryParameters: {'q': q});
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> getGameHighlights(int gameId) async {
    final res = await _dio.get('/games/$gameId/highlights');
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> getTeamNews(int teamId, {int limit = 20}) async {
    final res = await _dio.get('/news/team/$teamId', queryParameters: {'limit': limit});
    return Map<String, dynamic>.from(res.data);
  }

  static Future<String> uploadProfileImage(String filePath) async {
    final headers = await authHeaders();
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    final res = await _dio.post('/user/profile-image',
        data: formData,
        options: Options(headers: headers));
    return res.data['profile_image'] as String;
  }
}