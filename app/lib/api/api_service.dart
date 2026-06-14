import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// web 안전 보안저장 래퍼 — web은 flutter_secure_storage(Web Crypto) 실패 잦아
/// SharedPreferences(localStorage)로 폴백. Android/iOS는 secure_storage 그대로.
class _SafeStore {
  static const _s = FlutterSecureStorage();
  static Future<void> write(String key, String value) async {
    if (kIsWeb) {
      try { (await SharedPreferences.getInstance()).setString(key, value); return; }
      catch (e) { debugPrint('_SafeStore.write web: $e'); }
    }
    try { await _s.write(key: key, value: value); }
    catch (e) { debugPrint('_SafeStore.write: $e'); }
  }
  static Future<String?> read(String key) async {
    if (kIsWeb) {
      try { return (await SharedPreferences.getInstance()).getString(key); }
      catch (e) { debugPrint('_SafeStore.read web: $e'); return null; }
    }
    try { return await _s.read(key: key); }
    catch (e) { debugPrint('_SafeStore.read: $e'); return null; }
  }
  static Future<void> delete(String key) async {
    if (kIsWeb) {
      try { (await SharedPreferences.getInstance()).remove(key); return; }
      catch (e) { debugPrint('_SafeStore.delete web: $e'); }
    }
    try { await _s.delete(key: key); }
    catch (e) { debugPrint('_SafeStore.delete: $e'); }
  }
}

enum _RefreshResult { success, authFailed, networkError }

class ApiService {
  static final favoriteTeamsChanged = ValueNotifier<int>(0);
  static final favoritePlayersChanged = ValueNotifier<int>(0);
  static final myTeamData = ValueNotifier<List<Map<String, dynamic>>>([]);
  static const String baseUrl = 'https://playball.duckdns.org';
  static final Dio _dio = _buildDio();

  static Dio _buildDio() {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      // Accept-Encoding 수동지정은 native HttpClient용 (web은 브라우저가 관리 — 미설정)
      headers: kIsWeb ? null : {'Accept-Encoding': 'identity'},
    ));
    // web은 dart:io HttpClient 미지원 → 브라우저 기본 어댑터 사용 (IO 어댑터 설정 금지)
    if (!kIsWeb) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.maxConnectionsPerHost = 20;
          return client;
        },
      );
    }
    return dio;
  }
  static bool _interceptorAdded = false;

  static String? _cachedToken;

  // 세션 메모리 캐시 — async 없이 동기 읽기 (shimmer 제거용)
  static final Map<int, Map<String, dynamic>> _gameDetailMem = {};
  static Map<String, dynamic>? getGameDetailMem(int id) => _gameDetailMem[id];
  static void setGameDetailMem(int id, Map<String, dynamic> data) => _gameDetailMem[id] = data;

  // _dedupGet 비활성화 — 첫 호출 hang 시 모든 후속 호출 stuck 버그 회피
  // 직접 _dio.get으로 fallback
  static Future<Response> _dedupGet(String path, {Map<String, dynamic>? query, Options? options}) {
    return _dio.get(path, queryParameters: query, options: options);
  }

  static final Map<int, Map<String, dynamic>> _playerDetailMem = {};
  static Map<String, dynamic>? getPlayerDetailMem(int id) => _playerDetailMem[id];
  static void setPlayerDetailMem(int id, Map<String, dynamic> data) => _playerDetailMem[id] = data;

  // D-B: 동시 in-flight 요청 카운터 + 타이밍 로그 (debug only)
  static int _inFlightCount = 0;

  // ETag/304 — GET 응답의 ETag·바디를 메모리에 보관, 재요청 시 If-None-Match.
  // 서버가 304면 보관 바디로 즉시 응답 (30s 폴링 대역 절감 — 06-13 성능 묶음).
  // 키 = path+query 단위라 엔드포인트 수만큼만 성장 (bounded).
  static final Map<String, String> _etagOf = {};
  static final Map<String, dynamic> _etagBody = {};

  static void initInterceptor(Future<void> Function() onLogout) {
    if (_interceptorAdded) return;
    _interceptorAdded = true;

    // ETag 인터셉터 — 다른 인터셉터(재시도/auth)보다 먼저 304를 소화해야 함
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (opts, handler) {
        if (opts.method == 'GET') {
          final tag = _etagOf[opts.uri.toString()];
          if (tag != null) opts.headers['If-None-Match'] = tag;
        }
        return handler.next(opts);
      },
      onResponse: (res, handler) {
        if (res.requestOptions.method == 'GET') {
          final tag = res.headers.value('etag');
          if (tag != null) {
            final key = res.requestOptions.uri.toString();
            _etagOf[key] = tag;
            _etagBody[key] = res.data;
          }
        }
        return handler.next(res);
      },
      onError: (err, handler) {
        if (err.response?.statusCode == 304) {
          final key = err.requestOptions.uri.toString();
          final body = _etagBody[key];
          if (body != null) {
            return handler.resolve(Response(
              requestOptions: err.requestOptions,
              statusCode: 200,
              data: body,
            ));
          }
        }
        return handler.next(err);
      },
    ));

    if (kDebugMode) {
      _dio.interceptors.add(InterceptorsWrapper(
        onRequest: (opts, handler) {
          _inFlightCount++;
          opts.extra['_sw'] = Stopwatch()..start();
          opts.extra['_inflight_at_start'] = _inFlightCount;
          debugPrint('[Dio→] ${opts.method} ${opts.path} (in-flight: $_inFlightCount)');
          return handler.next(opts);
        },
        onResponse: (res, handler) {
          _inFlightCount = (_inFlightCount - 1).clamp(0, 1 << 30);
          final sw = res.requestOptions.extra['_sw'] as Stopwatch?;
          final ms = sw?.elapsedMilliseconds ?? 0;
          final start = res.requestOptions.extra['_inflight_at_start'] ?? 0;
          debugPrint('[Dio←] ${res.statusCode} ${res.requestOptions.path} ${ms}ms (peak in-flight: $start)');
          return handler.next(res);
        },
        onError: (err, handler) {
          _inFlightCount = (_inFlightCount - 1).clamp(0, 1 << 30);
          final sw = err.requestOptions.extra['_sw'] as Stopwatch?;
          final ms = sw?.elapsedMilliseconds ?? 0;
          debugPrint('[Dio✗] ${err.type} ${err.requestOptions.path} ${ms}ms');
          return handler.next(err);
        },
      ));
    }

    // Retry interceptor: 네트워크 오류 or 5xx 시 1회 재시도
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (err, handler) async {
        final isNetworkError = err.type == DioExceptionType.connectionTimeout ||
            err.type == DioExceptionType.receiveTimeout ||
            err.type == DioExceptionType.connectionError ||
            err.type == DioExceptionType.unknown;
        final is5xx = (err.response?.statusCode ?? 0) >= 500;
        // GET만 재시도 — POST 재전송은 비멱등(댓글 중복 작성 사고 06-13)
        final isGet = err.requestOptions.method.toUpperCase() == 'GET';
        if (isGet && (isNetworkError || is5xx) && err.requestOptions.extra['_retried'] != true) {
          err.requestOptions.extra['_retried'] = true;
          await Future.delayed(const Duration(milliseconds: 300));
          try {
            final res = await _dio.fetch(err.requestOptions);
            return handler.resolve(res);
          } catch (e) {
            return handler.next(e is DioException ? e : err);
          }
        }
        return handler.next(err);
      },
    ));

    // Auth interceptor: 401 시 refresh 후 재시도
    // - refresh 실패 OR refresh 응답 401/403만 → logout
    // - retry fetch 실패 (network/5xx) → logout 안 함 (다음 요청에서 다시 refresh 시도)
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (err, handler) async {
        if (err.response?.statusCode == 401) {
          final result = await _tryRefresh();
          if (result == _RefreshResult.success) {
            final opts = err.requestOptions;
            final token = await getToken();
            opts.headers['Authorization'] = 'Bearer $token';
            try {
              final res = await _dio.fetch(opts);
              return handler.resolve(res);
            } catch (_) {
              // 재시도 실패 = network/5xx 가능성 → 로그아웃 X, 에러만 propagate
              return handler.next(err);
            }
          } else if (result == _RefreshResult.authFailed) {
            // refresh token 무효 → 강제 로그아웃
            await onLogout();
          }
          // _RefreshResult.networkError → 로그아웃 X, 에러만 propagate
        }
        return handler.next(err);
      },
    ));
  }

  static Future<bool> tryRefreshToken() async => (await _tryRefresh()) == _RefreshResult.success;

  // 동시 refresh 요청 dedup용 in-flight Future
  static Future<_RefreshResult>? _refreshFuture;

  static Future<_RefreshResult> _tryRefresh() {
    // 진행중인 refresh 있으면 그 결과 공유 (race condition + refresh token rotation 방지)
    return _refreshFuture ??= _doRefresh()
      ..whenComplete(() => _refreshFuture = null);
  }

  static Future<_RefreshResult> _doRefresh() async {
    final refreshToken = await _SafeStore.read('refresh_token');
    if (refreshToken == null) return _RefreshResult.authFailed;
    try {
      final res = await Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      )).post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final data = res.data as Map<String, dynamic>;
      _cachedToken = data['access_token'] as String;
      await _SafeStore.write('access_token', data['access_token'] as String);
      await _SafeStore.write('refresh_token', data['refresh_token'] as String);
      return _RefreshResult.success;
    } on DioException catch (e) {
      // 401/403 = refresh token 무효, 5xx/network = 일시적 오류
      final status = e.response?.statusCode ?? 0;
      if (status == 401 || status == 403) return _RefreshResult.authFailed;
      return _RefreshResult.networkError;
    } catch (_) {
      return _RefreshResult.networkError;
    }
  }

  // ===== 토큰 관리 (Android Keystore / iOS Keychain + 메모리 캐시) =====
  static Future<String?> getToken() async {
    _cachedToken ??= await _SafeStore.read('access_token');
    return _cachedToken;
  }

  static Future<void> saveToken(String token) async {
    _cachedToken = token;
    await _SafeStore.write('access_token', token);
  }

  static Future<void> saveRefreshToken(String token) async {
    await _SafeStore.write('refresh_token', token);
  }

  static Future<String?> getRefreshToken() async {
    return _SafeStore.read('refresh_token');
  }

  static Future<void> deleteToken() async {
    _cachedToken = null;
    await _SafeStore.delete('access_token');
    await _SafeStore.delete('refresh_token');
  }

  // ===== 자동 로그인 자격증명 =====
  static Future<void> saveAutoLoginCredentials(String email, String password) async {
    await _SafeStore.write('auto_email', email);
    await _SafeStore.write('auto_password', password);
  }

  static Future<Map<String, String>?> getAutoLoginCredentials() async {
    final email = await _SafeStore.read('auto_email');
    final password = await _SafeStore.read('auto_password');
    if (email != null && password != null) return {'email': email, 'password': password};
    return null;
  }

  static Future<void> clearAutoLoginCredentials() async {
    await _SafeStore.delete('auto_email');
    await _SafeStore.delete('auto_password');
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

  static Future<Map<String, String>> optionalAuthHeaders() async {
    try {
      final token = await getToken();
      if (token != null && token.isNotEmpty) {
        return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
      }
    } catch (e) { debugPrint('api_service: $e'); }
    return {'Content-Type': 'application/json'};
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

  /// 온보딩 모드 서버 영속 (pro|casual) — 기기 storage 지워져도 재노출 방지
  static Future<void> setAppMode(String mode) async {
    final headers = await authHeaders();
    await _dio.post('/user/app-mode',
        data: {'mode': mode}, options: Options(headers: headers));
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

  // ===== 불펜 피로도 (최근 7일 등판 신호등) =====
  static Future<Map<String, dynamic>?> getBullpenStatus(int teamId) async {
    try {
      final res = await _dio.get('/teams/$teamId/bullpen-status');
      return Map<String, dynamic>.from(res.data);
    } catch (e) {
      debugPrint('api_service bullpen: $e');
      return null;
    }
  }

  // ===== 승리확률 시계열 (인게임 모델) =====
  static Future<Map<String, dynamic>?> getWinProbSeries(int gameId) async {
    try {
      final res = await _dio.get('/games/$gameId/win-prob-series');
      return Map<String, dynamic>.from(res.data);
    } catch (e) {
      debugPrint('api_service winprob: $e');
      return null;
    }
  }

  // ===== 앱 원격 설정 (강제 업데이트/킬스위치/공지) =====
  static Future<Map<String, dynamic>?> getAppConfig() async {
    try {
      final res = await _dio.get('/app-config');
      return Map<String, dynamic>.from(res.data);
    } catch (e) {
      debugPrint('api_service: $e');
      return null;
    }
  }

  // ===== 경기 API =====
  static Future<Map<String, dynamic>> getTodayGames() async {
    final res = await _dio.get('/games/today');
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> getGameDetail(int gameId) async {
    final res = await _dio.get('/games/$gameId');
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> getGamesByDate(String date) async {
    final res = await _dio.get('/games/date/$date');
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> getGameRelay(int gameId) async {
    final res = await _dedupGet('/games/$gameId/relay');
    return res.data;
  }

  static Future<Map<String, dynamic>> getGamePreview(int gameId) async {
    final res = await _dedupGet('/games/$gameId/preview');
    return res.data;
  }

  static Future<Map<String, dynamic>> getGameRecordDetail(int gameId) async {
    final res = await _dedupGet('/games/$gameId/record_detail');
    return res.data;
  }

  static Future<Map<String, dynamic>> getGameRelayAll(int gameId) async {
    final res = await _dedupGet('/games/$gameId/relay_all');
    return res.data;
  }

  static Future<Map<String, dynamic>> getGamePitchTypes(int gameId) async {
    final res = await _dedupGet('/games/$gameId/pitch-types');
    return res.data;
  }

  static Future<Map<String, dynamic>?> getGameWeather(int gameId) async {
    try {
      final res = await _dedupGet('/games/$gameId/weather');
      final w = res.data['weather'];
      return w != null ? Map<String, dynamic>.from(w) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> getGameRoster(int gameId) async {
    final res = await _dedupGet('/games/$gameId/roster');
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
      'team_id': ?teamId,
      'position': ?position,
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
      'team_id': ?teamId,
      'throws': ?throws,
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
      'player_type': ?playerType,
    });
    return res.data;
  }

  // ===== 팀 API =====
  static Future<Map<String, dynamic>> getTeams() async {
    final res = await _dedupGet('/teams/');
    return res.data;
  }

  static Future<Map<String, dynamic>> getTeamRankings({String period = 'full'}) async {
    final res = await _dedupGet('/teams/rankings', query: {'period': period});
    return res.data;
  }

  static Future<Map<String, dynamic>> getPostseasonOdds() async {
    final res = await _dio.get('/teams/postseason-odds');
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> getTeamAllStats({int season = 2026}) async {
    final res = await _dio.get('/teams/all-stats', queryParameters: {'season': season});
    return res.data;
  }

  static Future<Map<String, dynamic>> getTeamPlayers(int teamId) async {
    final res = await _dio.get('/teams/$teamId/players');
    return res.data;
  }

  static Future<Map<String, dynamic>> getTeamGames(int teamId, {int limit = 18}) async {
    final res = await _dio.get('/teams/$teamId/games', queryParameters: {'limit': limit});
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
    favoritePlayersChanged.value++;
  }

  static Future<void> removeFavoritePlayer(int playerId) async {
    final headers = await authHeaders();
    await _dio.delete('/user/favorite-players/$playerId',
        options: Options(headers: headers));
    favoritePlayersChanged.value++;
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

  static Future<void> deleteNotification(int notifId) async {
    final headers = await authHeaders();
    await _dio.delete('/user/notifications/$notifId',
        options: Options(headers: headers));
  }

  static Future<int> deleteReadNotifications() async {
    final headers = await authHeaders();
    final res = await _dio.delete('/user/notifications/read',
        options: Options(headers: headers));
    return (res.data['deleted'] as num?)?.toInt() ?? 0;
  }

  static Future<int> deleteAllNotifications() async {
    final headers = await authHeaders();
    final res = await _dio.delete('/user/notifications',
        options: Options(headers: headers));
    return (res.data['deleted'] as num?)?.toInt() ?? 0;
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
      'team_id': ?teamId,
      'category': ?category,
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

  static Future<void> blockUser(int userId) async {
    final headers = await authHeaders();
    await _dio.post('/community/users/$userId/block',
        options: Options(headers: headers));
  }

  static Future<void> unblockUser(int userId) async {
    final headers = await authHeaders();
    await _dio.delete('/community/users/$userId/block',
        options: Options(headers: headers));
  }

  static Future<List<Map<String, dynamic>>> getBlocks() async {
    final headers = await authHeaders();
    final res = await _dio.get('/community/blocks',
        options: Options(headers: headers));
    return ((res.data['blocks'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
      {int? teamId, String? imageUrl, List<String>? imageUrls}) async {
    final headers = await authHeaders();
    await _dio.post('/community/posts',
        data: {
          'title': title,
          'content': content,
          'category': category,
          'team_id': ?teamId,
          'image_url': ?imageUrl,
          'image_urls': ?imageUrls,
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

  static Future<Map<String, dynamic>> getTeamSeasonStats(int teamId, {int season = 2026}) async {
    final res = await _dio.get('/teams/$teamId/season-stats', queryParameters: {'season': season});
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
    } catch (e) { debugPrint('api_service: $e'); }
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

  /// 타자 존 히트맵 — 피투구/헛스윙/존별 타율 (throws: '' 전체 / 'R' vs우투 / 'L' vs좌투)
  static Future<Map<String, dynamic>> getBatterZones(int playerId,
      {int season = 2026, String throws = ''}) async {
    final res = await _dio.get('/players/$playerId/batter-zones',
        queryParameters: {'season': season, if (throws.isNotEmpty) 'throws': throws});
    return Map<String, dynamic>.from(res.data);
  }

  /// 피칭 디자인 — 구종별 5x5 존 분포 (stance: '' 전체 / 'R' / 'L')
  static Future<Map<String, dynamic>> getPitchDesign(int playerId,
      {int season = 2026, String stance = ''}) async {
    final res = await _dio.get('/players/$playerId/pitch-design',
        queryParameters: {'season': season, if (stance.isNotEmpty) 'stance': stance});
    return Map<String, dynamic>.from(res.data);
  }

  /// 피칭 존 히트맵 — 존별 피투구 분포 / 피안타율 (stance: '' 전체 / 'R' / 'L')
  static Future<Map<String, dynamic>> getPitcherZones(int playerId,
      {int season = 2026, String stance = ''}) async {
    final res = await _dio.get('/players/$playerId/pitcher-zones',
        queryParameters: {'season': season, if (stance.isNotEmpty) 'stance': stance});
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
      String date, String title, {String? endDate, String? description, String color = 'blue',
      String? startTime, String? endTime}) async {
    final headers = await authHeaders();
    final res = await _dio.post('/user/calendar-events',
        data: {'event_date': date, 'end_date': endDate ?? date, 'title': title, 'description': description, 'color': color,
               'start_time': startTime, 'end_time': endTime},
        options: Options(headers: headers));
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> updateCalendarEvent(
      int eventId, String date, String title, {String? endDate, String? description, String color = 'blue',
      String? startTime, String? endTime}) async {
    final headers = await authHeaders();
    final res = await _dio.put('/user/calendar-events/$eventId',
        data: {'event_date': date, 'end_date': endDate ?? date, 'title': title, 'description': description, 'color': color,
               'start_time': startTime, 'end_time': endTime},
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
      int gameId, String result, {String? memo, String? imageUrl}) async {
    final headers = await authHeaders();
    final res = await _dio.post('/user/stadium-visits',
        data: {'game_id': gameId, 'result': result, 'memo': memo, 'image_url': imageUrl},
        options: Options(headers: headers));
    return Map<String, dynamic>.from(res.data);
  }

  static Future<void> deleteStadiumVisit(int visitId) async {
    final headers = await authHeaders();
    await _dio.delete('/user/stadium-visits/$visitId', options: Options(headers: headers));
  }

  static Future<Map<String, dynamic>> getStadiumStats() async {
    final headers = await authHeaders();
    final res = await _dio.get('/user/stadium-stats', options: Options(headers: headers));
    return Map<String, dynamic>.from(res.data);
  }

  // ML 모델 승리예측 (구 vote 엔드포인트 대체)
  static Future<Map<String, dynamic>> getWinPrediction(int gameId) async {
    final res = await _dio.get('/prediction/game/$gameId');
    return Map<String, dynamic>.from(res.data);
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

  // ===== 인기투표 =====
  static Future<Map<String, dynamic>> getPlayerPopularity({int limit = 20}) async {
    final headers = await authHeaders();
    final res = await _dio.get('/players/popularity',
        queryParameters: {'limit': limit},
        options: Options(headers: headers));
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> votePlayer(int playerId) async {
    final headers = await authHeaders();
    final res = await _dio.post('/players/$playerId/vote',
        options: Options(headers: headers));
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> getPlayerVoteStatus(int playerId) async {
    final headers = await authHeaders();
    final res = await _dio.get('/players/$playerId/vote-status',
        options: Options(headers: headers));
    return Map<String, dynamic>.from(res.data);
  }

  // 인스타 핸들 오류 신고 (계정이 선수 본인이 아닐 때)
  static Future<void> reportInstaHandle(int playerId) async {
    final headers = await authHeaders();
    await _dio.post('/players/$playerId/report-insta',
        options: Options(headers: headers));
  }

  static Future<Map<String, dynamic>> getTeamPopularity() async {
    final headers = await authHeaders();
    final res = await _dio.get('/teams/popularity',
        options: Options(headers: headers));
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> voteTeam(int teamId) async {
    final headers = await authHeaders();
    final res = await _dio.post('/teams/$teamId/vote',
        options: Options(headers: headers));
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> getStadiumRanking({int limit = 30}) async {
    final res = await _dio.get('/user/stadium-ranking', queryParameters: {'limit': limit});
    return Map<String, dynamic>.from(res.data);
  }

  static Future<String> uploadProfileImage(String filePath) async {
    final headers = await authHeaders();
    // cropped 파일 확장자 명시 — 원형 crop = png (transparent 모서리)
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: 'profile.jpg'),
    });
    final res = await _dio.post('/user/profile-image',
        data: formData,
        options: Options(headers: headers));
    return res.data['profile_image'] as String;
  }

  // ===== 포인트/승부예측 (메가B) =====
  static Future<Map<String, dynamic>> predictGame(int gameId, String pick) async {
    final headers = await authHeaders();
    final res = await _dio.post('/games/$gameId/predict',
        data: {'pick': pick}, options: Options(headers: headers));
    return Map<String, dynamic>.from(res.data);
  }

  /// 팬 예측 분포 — 로그인 시 my_pick 포함 (비로그인 호출 가능)
  static Future<Map<String, dynamic>> getFanPredictions(int gameId) async {
    final headers = await authHeaders();
    final res = await _dio.get('/games/$gameId/fan-predictions',
        options: Options(headers: headers));
    return Map<String, dynamic>.from(res.data);
  }

  /// 일일 출석 적립 — 홈 진입 시 사일런트 호출 (실패 무시)
  static Future<void> checkAttendance() async {
    try {
      final headers = await authHeaders();
      await _dio.post('/user/points/attendance', options: Options(headers: headers));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> getMyPoints() async {
    final headers = await authHeaders();
    final res = await _dio.get('/user/points', options: Options(headers: headers));
    return Map<String, dynamic>.from(res.data);
  }

  static Future<Map<String, dynamic>> getPointsLeaderboard() async {
    final res = await _dio.get('/user/points/leaderboard');
    return Map<String, dynamic>.from(res.data);
  }

  /// 홈 부트스트랩 — 오늘 경기+팀순위+이번달 캘린더+앱설정 1콜 (실패 시 null → 개별 폴백)
  static Future<Map<String, dynamic>?> getHomeBootstrap() async {
    try {
      final res = await _dio.get('/home/bootstrap');
      return Map<String, dynamic>.from(res.data);
    } catch (e) {
      debugPrint('api_service bootstrap: $e');
      return null;
    }
  }

  /// 뱃지 — 호출 시 서버 lazy 평가 (신규 충족분 자동 획득)
  static Future<Map<String, dynamic>> getBadges() async {
    final headers = await authHeaders();
    final res = await _dio.get('/user/badges', options: Options(headers: headers));
    return Map<String, dynamic>.from(res.data);
  }

  /// 주간미션 — 완료분 자동 보상 적립
  static Future<Map<String, dynamic>> getWeeklyMissions() async {
    final headers = await authHeaders();
    final res = await _dio.get('/user/missions', options: Options(headers: headers));
    return Map<String, dynamic>.from(res.data);
  }
}