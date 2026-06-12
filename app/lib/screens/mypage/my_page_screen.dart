import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'photo_crop_screen.dart';
import '../../api/api_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../utils/team_theme.dart';
import '../../utils/local_cache.dart';
import '../player/player_detail_screen.dart';
import '../team/team_detail_screen.dart';
import '../community/post_detail_screen.dart';
import 'phone_verify_screen.dart';
import 'blocked_users_screen.dart';
import 'points_screen.dart';
import '../../utils/app_config.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/web_image.dart';

class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  Map<String, dynamic>? _user;
  List _favoriteTeams = [];
  List _favoritePlayers = [];
  List _myPosts = [];
  List _myComments = [];
  List _myLikes = [];
  List _stadiumVisits = [];
  bool _loading = true;
  bool _uploadingImage = false;

  // 알림 설정
  bool _notifyGameStart    = true;
  bool _notifyScoreChange  = true;
  bool _notifyGameEnd      = true;
  bool _notifyMyTeamOnly   = false;
  bool _notifyStreak        = true;
  bool _notifyRankChange    = true;
  bool _notifyRoster        = true;
  bool _notifyComment       = true;
  bool _notifyPennantRace   = true;
  bool _notifyFavHr         = true;
  bool _notifyWalkoff       = true;
  bool _notifyStarterKo     = true;
  int  _notifyBeforeMinutes = 60;
  bool _notifyMilestone     = true;
  bool _notifyFavLineup     = true;
  bool _notifyPlayerDaily   = true;
  bool _notifyPlayerNews    = true;
  bool _notifyTeamMilestone = true;
  bool _notifyAllstarVote   = true;
  bool _notifyQuiet         = true;
  bool _settingsLoaded      = false;
  final Set<int> _expandedCats = {0}; // 알림 카테고리 펼침 (기본 경기 알림)

  @override
  void initState() {
    super.initState();
    // 캐시 즉시 표시 + API 병렬 갱신 — 캐시 완료를 기다리지 않아도 됨
    // (SharedPreferences 읽기 ~5ms, API ~200ms → 캐시가 항상 먼저 완료)
    _loadFromCache();
    _refreshFromApi();
    // 즐겨찾기 선수/팀 변경 시 실시간 반영 (상세에서 해제 후 복귀 등)
    ApiService.favoritePlayersChanged.addListener(_onFavChanged);
    ApiService.favoriteTeamsChanged.addListener(_onFavChanged);
  }

  @override
  void dispose() {
    ApiService.favoritePlayersChanged.removeListener(_onFavChanged);
    ApiService.favoriteTeamsChanged.removeListener(_onFavChanged);
    super.dispose();
  }

  void _onFavChanged() {
    if (mounted) _refreshFromApi();
  }

  void _applySettings(Map settings) {
    _notifyGameStart     = settings['notify_game_start']     as bool? ?? true;
    _notifyScoreChange   = settings['notify_score_change']   as bool? ?? true;
    _notifyGameEnd       = settings['notify_game_end']       as bool? ?? true;
    _notifyMyTeamOnly    = settings['notify_my_team_only']   as bool? ?? false;
    _notifyStreak        = settings['notify_streak']         as bool? ?? true;
    _notifyRankChange    = settings['notify_rank_change']    as bool? ?? true;
    _notifyRoster        = settings['notify_roster']         as bool? ?? true;
    _notifyComment       = settings['notify_comment']        as bool? ?? true;
    _notifyPennantRace   = settings['notify_pennant_race']   as bool? ?? true;
    _notifyFavHr         = settings['notify_fav_hr']         as bool? ?? true;
    _notifyWalkoff       = settings['notify_walkoff']        as bool? ?? true;
    _notifyStarterKo     = settings['notify_starter_ko']     as bool? ?? true;
    _notifyBeforeMinutes = (settings['notify_before_minutes'] as num?)?.toInt() ?? 60;
    _notifyMilestone     = settings['notify_milestone']      as bool? ?? true;
    _notifyFavLineup     = settings['notify_fav_lineup']     as bool? ?? true;
    _notifyPlayerDaily   = settings['notify_player_daily']   as bool? ?? true;
    _notifyPlayerNews    = settings['notify_player_news']    as bool? ?? true;
    _notifyTeamMilestone = settings['notify_team_milestone'] as bool? ?? true;
    _notifyAllstarVote   = settings['notify_allstar_vote']   as bool? ?? true;
    _notifyQuiet         = settings['notify_quiet']          as bool? ?? true;
  }

  Future<void> _loadFromCache() async {
    final me          = await LocalCache.get('me')               as Map?;
    final favTeams    = await LocalCache.get('favorite_teams')   as List?;
    final favPlayers  = await LocalCache.get('favorite_players') as List?;
    final myPosts     = await LocalCache.get('my_posts')         as List?;
    final myComments  = await LocalCache.get('my_comments')      as List?;
    final myLikes     = await LocalCache.get('my_likes')         as List?;
    final settings    = await LocalCache.get('user_settings')    as Map?;

    if (!mounted) return;
    setState(() {
      if (me != null)         _user           = Map<String, dynamic>.from(me);
      if (favTeams != null)   _favoriteTeams   = favTeams;
      if (favPlayers != null) _favoritePlayers  = favPlayers;
      if (myPosts != null)    _myPosts         = myPosts;
      if (myComments != null) _myComments      = myComments;
      if (myLikes != null)    _myLikes         = myLikes;
      if (settings != null)   { _applySettings(settings); _settingsLoaded = true; }
      _loading = false; // 캐시 비어도 false — API 갱신은 백그라운드에서 처리
    });
  }

  Future<void> _refreshFromApi() async {
    final empty = <String, dynamic>{};
    final results = await Future.wait([
      ApiService.getMe().catchError((_) => empty),
      ApiService.getFavoriteTeams().catchError((_) => empty),
      ApiService.getFavoritePlayers().catchError((_) => empty),
      ApiService.getMyPosts().catchError((_) => empty),
      ApiService.getMyComments().catchError((_) => empty),
      ApiService.getSettings().catchError((_) => empty),
      ApiService.getMyLikes().catchError((_) => empty),
      ApiService.getStadiumVisits(limit: 20).catchError((_) => empty),
    ]);
    if (!mounted) return;

    final me          = results[0] as Map;
    final teamsRes    = results[1] as Map;
    final playersRes  = results[2] as Map;
    final postsRes    = results[3] as Map;
    final commentsRes = results[4] as Map;
    final settingsRes = results[5] as Map;
    final likesRes    = results[6] as Map;
    final visitsRes   = results[7] as Map;

    // API 실패 시 catchError → {} 반환 → isNotEmpty false → 캐시 덮어쓰기 방지
    // (성공 응답은 항상 해당 키를 포함하므로 isNotEmpty = true)
    final teams    = teamsRes.isNotEmpty    ? (teamsRes['teams']        as List? ?? []) : null;
    final players  = playersRes.isNotEmpty  ? (playersRes['players']    as List? ?? []) : null;
    final posts    = postsRes.isNotEmpty    ? (postsRes['posts']        as List? ?? []) : null;
    final comments = commentsRes.isNotEmpty ? (commentsRes['comments']  as List? ?? []) : null;
    final settings = settingsRes.isNotEmpty ? (settingsRes['settings']  as Map?)        : null;
    final likes    = likesRes.isNotEmpty    ? (likesRes['posts']        as List? ?? []) : null;
    final visits   = visitsRes.isNotEmpty   ? (visitsRes['visits']      as List? ?? []) : null;

    if (me.isNotEmpty)   await LocalCache.set('me',              me);
    if (teams != null)    await LocalCache.set('favorite_teams',   teams);
    if (players != null)  await LocalCache.set('favorite_players', players);
    if (posts != null)    await LocalCache.set('my_posts',         posts);
    if (comments != null) await LocalCache.set('my_comments',      comments);
    if (likes != null)    await LocalCache.set('my_likes',         likes);
    if (settings != null) await LocalCache.set('user_settings',    settings);

    setState(() {
      if (me.isNotEmpty)   _user           = me as Map<String, dynamic>;
      if (teams != null)    _favoriteTeams   = teams;
      if (players != null)  _favoritePlayers  = players;
      if (posts != null)    _myPosts         = posts;
      if (comments != null) _myComments      = comments;
      if (likes != null)    _myLikes         = likes;
      if (visits != null)   _stadiumVisits   = visits;
      if (settings != null) { _applySettings(settings); _settingsLoaded = true; }
      _loading = false;
    });
  }

  Future<void> _load() => _refreshFromApi();

  Future<void> _saveSettings() async {
    try {
      await ApiService.updateSettings({
        'notify_game_start':      _notifyGameStart,
        'notify_score_change':    _notifyScoreChange,
        'notify_game_end':        _notifyGameEnd,
        'notify_my_team_only':    _notifyMyTeamOnly,
        'notify_streak':          _notifyStreak,
        'notify_rank_change':     _notifyRankChange,
        'notify_roster':          _notifyRoster,
        'notify_comment':         _notifyComment,
        'notify_pennant_race':    _notifyPennantRace,
        'notify_fav_hr':          _notifyFavHr,
        'notify_walkoff':         _notifyWalkoff,
        'notify_starter_ko':      _notifyStarterKo,
        'notify_before_minutes':  _notifyBeforeMinutes,
        'notify_milestone':       _notifyMilestone,
        'notify_fav_lineup':      _notifyFavLineup,
        'notify_player_daily':    _notifyPlayerDaily,
        'notify_player_news':     _notifyPlayerNews,
        'notify_team_milestone':  _notifyTeamMilestone,
        'notify_allstar_vote':    _notifyAllstarVote,
        'notify_quiet':           _notifyQuiet,
      });
    } catch (e) { debugPrint('my_page: $e'); }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃 하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('로그아웃', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    await context.read<AuthProvider>().logout();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _resetSettings() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('설정 초기화'),
        content: const Text('테마·화면 토글·선수별 핵심 기록·도움말 등 앱 환경설정을 기본값으로 되돌립니다.\n로그인·즐겨찾기·작성 글은 그대로 유지됩니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('초기화', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await LocalCache.resetSettings();
    if (!mounted) return;
    await context.read<ThemeProvider>().reset();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정을 기본값으로 초기화했어요')),
      );
    }
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('회원탈퇴'),
        content: const Text('탈퇴 시 모든 데이터가 삭제되며 복구할 수 없습니다.\n정말 탈퇴하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('탈퇴', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteAccount();
      if (!mounted) return;
      await context.read<AuthProvider>().logout();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('탈퇴 처리 중 오류가 발생했습니다')));
      }
    }
  }

  Future<void> _editNickname() async {
    final ctrl = TextEditingController(text: _user?['nickname'] ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('닉네임 변경'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '새 닉네임 (2~20자)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('변경'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    try {
      final res = await ApiService.updateNickname(result);
      setState(() => _user?['nickname'] = res['nickname']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('닉네임이 변경되었습니다')));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.response?.data?['detail'] ?? '변경 실패')));
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    // 인스타식 인앱 크롭 화면(crop_your_image) — 네이티브 uCrop 미사용(status bar 겹침 회피)
    final bytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => const PhotoCropScreen()),
    );
    if (bytes == null) return;
    setState(() => _uploadingImage = true);
    try {
      // 크롭 bytes → 임시 파일 (업로드는 파일 경로 기반)
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/profile_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await f.writeAsBytes(bytes);
      final url = await ApiService.uploadProfileImage(f.path);
      // 캐시 우회: URL에 timestamp query 붙여 새 cache key
      final bustedUrl = url.contains('?') ? '$url&t=${DateTime.now().millisecondsSinceEpoch}'
                                          : '$url?t=${DateTime.now().millisecondsSinceEpoch}';
      // imageCache 클리어 — 이전 URL 캐시 강제 제거
      CachedNetworkImage.evictFromCache(url);
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      setState(() {
        _user?['profile_image'] = bustedUrl;
        _uploadingImage = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('프로필 이미지가 변경되었습니다')));
      }
    } catch (_) {
      setState(() => _uploadingImage = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미지 업로드 실패')));
      }
    }
  }

  // ── build (Option A 디자인) ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = _C(context);
    final myCode = _favoriteTeams.isNotEmpty ? (_favoriteTeams[0]['short_name'] as String? ?? '') : '';
    final myColor = myCode.isNotEmpty ? teamColor(myCode) : SemColor.brand(context);

    return Scaffold(
      backgroundColor: cs.bg,
      body: SafeArea(
        top: false, // 헤더가 상태바까지 paper — 단차 방지 (06-13)
        child: Column(children: [
          // ── 헤더 (탭 공통 규격) ──
          Container(
            padding: EdgeInsets.fromLTRB(
                18, 8 + MediaQuery.of(context).viewPadding.top, 18, 12),
            decoration: BoxDecoration(color: cs.paper, border: Border(bottom: BorderSide(color: cs.line))),
            child: Row(children: [
              _Btn32(border: cs.line2, onTap: () => Navigator.maybePop(context),
                child: Icon(Icons.chevron_left, size: 20, color: cs.ink2)),
              const SizedBox(width: 10),
              Text('마이페이지', style: TextStyle(fontSize: Typo.h2, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.5)),
              const Spacer(),
              _Btn32(border: cs.line2, onTap: _logout,
                child: Icon(Icons.logout_outlined, size: 17, color: cs.ink3)),
            ]),
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: myColor, strokeWidth: 2.5))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(padding: EdgeInsets.zero, children: [
                      _buildProfile(cs),
                      if (_favoriteTeams.isNotEmpty) _buildMyTeam(cs),
                      _buildFavPlayers(cs),
                      _buildVisitRecord(cs, myColor),
                      _buildCommunityHub(cs),
                      if (_settingsLoaded) _buildNotifSettings(cs, myColor),
                      _buildDarkMode(cs, myColor),
                      _buildUtilCard(cs),
                      const SizedBox(height: 8),
                      Center(child: TextButton(
                        onPressed: _deleteAccount,
                        child: Text('회원탈퇴',
                            style: TextStyle(color: SemColor.live.withValues(alpha: 0.7), fontSize: 12)),
                      )),
                      const SizedBox(height: 24),
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }

  BoxDecoration _cardDeco(_C cs) => BoxDecoration(
    color: cs.paper, border: Border.all(color: cs.line),
    borderRadius: BorderRadius.circular(Radii.lg),
    boxShadow: cs.dark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 3, offset: const Offset(0, 1))],
  );

  Widget _sectionLabel(_C cs, String label, {String? action, VoidCallback? onAction}) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
    child: Row(children: [
      Text(label, style: TextStyle(fontSize: 10, fontWeight: Typo.bold, color: cs.sub, letterSpacing: 0.8)),
      if (action != null) ...[
        const Spacer(),
        GestureDetector(
          onTap: onAction,
          child: Text(action, style: TextStyle(fontSize: 11, color: cs.ink3)),
        ),
      ],
    ]),
  );

  // ── 프로필 (이미지 업로드 + 닉네임 수정 + 이메일 인증 배지) ──
  Widget _buildProfile(_C cs) {
    final verified = _user?['phone_verified'] == true;
    final img = _user?['profile_image'] as String?;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDeco(cs),
        child: Row(children: [
          GestureDetector(
            onTap: _pickAndUploadImage,
            child: Stack(children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: cs.paper2,
                  border: Border.all(color: cs.line2, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: (img != null && img.isNotEmpty)
                    ? netImage(img, width: 64, height: 64, fit: BoxFit.cover,
                        error: () => Icon(Icons.person_outline, size: 28, color: cs.sub))
                    : Icon(Icons.person_outline, size: 28, color: cs.sub),
              ),
              if (_uploadingImage)
                Positioned.fill(child: Container(
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black45),
                  child: const Center(child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
                ))
              else
                Positioned(bottom: 0, right: 0, child: Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(color: cs.ink, shape: BoxShape.circle, border: Border.all(color: cs.paper, width: 2)),
                  child: Icon(Icons.camera_alt_outlined, size: 10, color: cs.dark ? const Color(0xFF0F0F12) : Colors.white),
                )),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: _editNickname,
              child: Row(children: [
                Flexible(child: Text(_user?['nickname'] ?? '-', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 18, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.5))),
                const SizedBox(width: 7),
                Icon(Icons.edit_outlined, size: 14, color: cs.sub),
              ]),
            ),
            const SizedBox(height: 5),
            Text(_user?['email'] ?? '', style: TextStyle(fontSize: 12, color: cs.ink3)),
            const SizedBox(height: 7),
            if (verified)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFF22C55E).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check, size: 10, color: Color(0xFF22C55E)),
                  SizedBox(width: 4),
                  Text('이메일 인증 완료', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF22C55E))),
                ]),
              )
            else
              GestureDetector(
                onTap: () async {
                  final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const PhoneVerifyScreen()));
                  if (ok == true) _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: SemColor.warning.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.error_outline, size: 10, color: SemColor.warning),
                    const SizedBox(width: 4),
                    Text('이메일 인증하기', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: SemColor.warning)),
                  ]),
                ),
              ),
          ])),
        ]),
      ),
    );
  }

  // ── 마이팀 (여러 팀 전부 표시) ──
  Widget _buildMyTeam(_C cs) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel(cs, '마이팀'),
      ..._favoriteTeams.asMap().entries.map((e) {
        final t = e.value as Map;
        final code = t['short_name'] as String? ?? '';
        final tColor = code.isNotEmpty ? teamColor(code) : SemColor.brand(context);
        final wins = t['wins'] ?? 0;
        final losses = t['losses'] ?? 0;
        final rank = t['rank'] ?? '-';
        final winRate = ((t['win_rate'] ?? 0) * 100).toStringAsFixed(1);
        final last = e.key == _favoriteTeams.length - 1;
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, last ? 0 : 8),
          child: GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => TeamDetailScreen(team: Map<String, dynamic>.from(t)))),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: _cardDeco(cs),
              child: Row(children: [
                Stack(clipBehavior: Clip.none, children: [
                  TeamLogo(teamCode: code, size: 48),
                  Positioned(top: -4, right: -4, child: Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(color: tColor, shape: BoxShape.circle, border: Border.all(color: cs.paper, width: 1.5)),
                    child: const Center(child: Text('★', style: TextStyle(fontSize: 9, color: Colors.white, height: 1))),
                  )),
                ]),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(t['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: Typo.extra, color: cs.ink, letterSpacing: -0.4))),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: tColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5)),
                      child: Text('$rank위', style: TextStyle(fontSize: 11, fontWeight: Typo.bold, color: tColor)),
                    ),
                  ]),
                  const SizedBox(height: 5),
                  Text('$wins승 $losses패 · 승률 $winRate%', style: TextStyle(fontSize: 12, color: cs.ink3)),
                ])),
                Icon(Icons.chevron_right, size: 18, color: cs.sub),
              ]),
            ),
          ),
        );
      }),
    ]);
  }

  // ── 즐겨찾기 선수 (가로 스크롤) ──
  Widget _buildFavPlayers(_C cs) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel(cs, '즐겨찾기 선수', action: _favoritePlayers.isEmpty ? null : '${_favoritePlayers.length}명'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Container(
          decoration: _cardDeco(cs),
          child: _favoritePlayers.isEmpty
              ? Padding(padding: const EdgeInsets.all(20),
                  child: Center(child: Text('즐겨찾기한 선수가 없습니다', style: TextStyle(fontSize: 12, color: cs.sub))))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(14),
                  child: Row(children: _favoritePlayers.map((p) {
                    final code = p['team_code'] as String? ?? '';
                    final c = code.isNotEmpty ? teamColor(code) : cs.sub;
                    final img = p['profile_image'] as String?;
                    return GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => PlayerDetailScreen(
                            playerId: p['id'],
                            initialData: {'name': p['name'], 'team': p['team'], 'profile_image': img, 'position': p['position'], 'team_code': code},
                          ))),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: SizedBox(width: 54, child: Column(children: [
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: c.withValues(alpha: cs.dark ? 0.18 : 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: c.withValues(alpha: 0.25)),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: (img != null && img.isNotEmpty)
                                ? netImage(img, width: 44, height: 44, fit: BoxFit.cover,
                                    error: () => Center(child: Icon(Icons.person, size: 22, color: c)))
                                : Center(child: Icon(Icons.person, size: 22, color: c)),
                          ),
                          const SizedBox(height: 6),
                          Text(p['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, fontWeight: Typo.bold, color: cs.ink)),
                          const SizedBox(height: 3),
                          Text(p['position'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 9, color: cs.sub)),
                        ])),
                      ),
                    );
                  }).toList()),
                ),
        ),
      ),
    ]);
  }

  // ── 직관 기록 ──
  Widget _buildVisitRecord(_C cs, Color myColor) {
    final wins = _stadiumVisits.where((v) => v['result'] == 'win').length;
    final losses = _stadiumVisits.where((v) => v['result'] == 'loss').length;
    final draws = _stadiumVisits.where((v) => v['result'] == 'draw').length;
    final total = wins + losses + draws;
    final winPct = total > 0 ? (wins / total * 100).round() : 0;
    final shown = _stadiumVisits.take(5).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel(cs, '직관 기록'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Container(
          decoration: _cardDeco(cs),
          child: Column(children: [
            IntrinsicHeight(child: Row(children: [
              _visitStat(cs, '$wins', '승', const Color(0xFF2563EB)),
              VerticalDivider(width: 1, color: cs.line),
              _visitStat(cs, '$losses', '패', SemColor.live),
              VerticalDivider(width: 1, color: cs.line),
              _visitStat(cs, '$draws', '무', cs.sub),
              VerticalDivider(width: 1, color: cs.line),
              _visitStat(cs, total > 0 ? '$winPct%' : '-', '직관승률', myColor),
            ])),
            if (shown.isEmpty)
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text('캘린더에서 직관 기록을 추가해보세요', style: TextStyle(fontSize: 11, color: cs.sub)))
            else ...[
              Divider(height: 1, color: cs.line),
              ...shown.asMap().entries.map((e) => _visitTile(cs, e.value as Map, e.key == shown.length - 1)),
            ],
          ]),
        ),
      ),
    ]);
  }

  Widget _visitStat(_C cs, String value, String label, Color color) => Expanded(child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Column(children: [
      Text(value, style: TextStyle(fontSize: 18, fontWeight: Typo.extra, color: color)),
      const SizedBox(height: 5),
      Text(label, style: TextStyle(fontSize: 10, color: cs.sub)),
    ]),
  ));

  Widget _visitTile(_C cs, Map v, bool last) {
    final result = v['result'] as String? ?? '';
    final c = result == 'win' ? const Color(0xFF2563EB) : result == 'loss' ? SemColor.live : cs.sub;
    final lb = result == 'win' ? '승' : result == 'loss' ? '패' : '무';
    final rawDate = (v['game_date'] as String? ?? '');
    final date = rawDate.length >= 10 ? rawDate.substring(0, 10).replaceAll('-', '.') : rawDate;
    final home = v['home_team'] as String? ?? '';
    final away = v['away_team'] as String? ?? '';
    final hs = v['home_score'] as int? ?? 0;
    final as_ = v['away_score'] as int? ?? 0;
    final memo = v['memo'] as String?;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
      child: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: c.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Center(child: Text(lb, style: TextStyle(fontSize: 12, fontWeight: Typo.extra, color: c))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$away $as_ : $hs $home',
              style: TextStyle(fontSize: 12, fontWeight: Typo.bold, color: cs.ink, height: 1.4)),
          if (memo != null && memo.isNotEmpty)
            Text(memo, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: cs.sub)),
        ])),
        Text(date, style: TextStyle(fontSize: 10, color: cs.sub)),
      ]),
    );
  }

  // ── 커뮤니티 활동 허브 (06-12 정리) — 글/좋아요/댓글 인라인 펼침 → 진입 행 3개 + 바텀시트
  Widget _buildCommunityHub(_C cs) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel(cs, '커뮤니티 활동'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Container(
          decoration: _cardDeco(cs),
          child: Column(children: [
            _hubRow(cs, Icons.edit_note, '내 게시글', _myPosts.length,
                onTap: () => _showActivitySheet(cs, 'posts'), first: true),
            _hubRow(cs, Icons.favorite_border, '좋아요한 글', _myLikes.length,
                onTap: () => _showActivitySheet(cs, 'likes')),
            _hubRow(cs, Icons.chat_bubble_outline, '내 댓글', _myComments.length,
                onTap: () => _showActivitySheet(cs, 'comments'), last: true),
          ]),
        ),
      ),
    ]);
  }

  Widget _hubRow(_C cs, IconData icon, String label, int? count,
      {required VoidCallback onTap, bool first = false, bool last = false,
      Color? iconColor}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
            border: last ? null : Border(bottom: BorderSide(color: cs.line))),
        child: Row(children: [
          Icon(icon, size: 18, color: iconColor ?? cs.sub),
          const SizedBox(width: 12),
          Expanded(child: Text(label,
              style: TextStyle(fontSize: 13.5, fontWeight: Typo.bold, color: cs.ink))),
          if (count != null && count > 0)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text('$count', style: TextStyle(fontSize: 12, fontWeight: Typo.bold, color: cs.ink3)),
            ),
          Icon(Icons.chevron_right, size: 17, color: cs.sub),
        ]),
      ),
    );
  }

  void _showActivitySheet(_C cs, String type) {
    final (title, items) = switch (type) {
      'posts' => ('내 게시글', _myPosts),
      'likes' => ('좋아요한 글', _myLikes),
      _ => ('내 댓글', _myComments),
    };
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.paper,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.35,
        builder: (ctx, scrollCtrl) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Row(children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: Typo.extra, color: cs.ink)),
              const SizedBox(width: 6),
              Text('${items.length}', style: TextStyle(fontSize: 13, color: cs.sub)),
            ]),
          ),
          Divider(height: 1, color: cs.line),
          Expanded(
            child: items.isEmpty
                ? Center(child: Text('아직 없습니다', style: TextStyle(fontSize: 13, color: cs.sub)))
                : ListView.builder(
                    controller: scrollCtrl,
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final last = i == items.length - 1;
                      if (type == 'comments') {
                        final c = items[i] as Map;
                        return _commentRow(cs, c, last);
                      }
                      final p = items[i] as Map;
                      return _postRow(cs,
                        title: p['title'] ?? '',
                        chip: type == 'likes' ? p['author'] as String? : p['category'] as String?,
                        likes: p['likes'] ?? 0,
                        comments: p['comment_count'] ?? 0,
                        date: _shortDate(p['created_at']),
                        last: last,
                        leadingHeart: type == 'likes',
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => PostDetailScreen(postId: p['id']))),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _commentRow(_C cs, Map c, bool last) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => PostDetailScreen(postId: c['post_id']))),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c['content'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: cs.ink, height: 1.45)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: Text(c['post_title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: cs.sub))),
            const SizedBox(width: 8),
            Text(_shortDate(c['created_at']), style: TextStyle(fontSize: 10, color: cs.sub)),
          ]),
        ]),
      ),
    );
  }

  // ── 기타 (포인트/차단/초기화 단독 카드 3개 → 통합 카드)
  Widget _buildUtilCard(_C cs) {
    final showPoints = AppConfig.enabled('points');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel(cs, '기타'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Container(
          decoration: _cardDeco(cs),
          child: Column(children: [
            if (showPoints)
              _hubRow(cs, Icons.stars_rounded, '내 포인트 · 랭킹', null,
                  iconColor: const Color(0xFFD97706),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const PointsScreen())),
                  first: true),
            _hubRow(cs, Icons.block, '차단한 사용자', null,
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const BlockedUsersScreen())),
                first: !showPoints),
            _hubRow(cs, Icons.restart_alt, '설정 초기화', null,
                onTap: _resetSettings, last: true),
          ]),
        ),
      ),
    ]);
  }

  Widget _postRow(_C cs, {required String title, String? chip, required int likes,
      required int comments, required String date, required bool last,
      bool leadingHeart = false, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (leadingHeart) ...[
              Icon(Icons.favorite, size: 13, color: SemColor.live),
              const SizedBox(width: 6),
            ],
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: Typo.bold, color: cs.ink, height: 1.45))),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            if (chip != null && chip.isNotEmpty) ...[
              _SmallChip(label: chip, color: cs.ink3, bg: cs.paper2, border: cs.line),
              const SizedBox(width: 8),
            ],
            Text('♡ $likes', style: TextStyle(fontSize: 10, color: cs.sub)),
            const SizedBox(width: 8),
            Text('💬 $comments', style: TextStyle(fontSize: 10, color: cs.sub)),
            const Spacer(),
            Text(date, style: TextStyle(fontSize: 10, color: cs.sub)),
          ]),
        ]),
      ),
    );
  }

  String _shortDate(dynamic v) {
    final s = (v ?? '').toString();
    return s.length >= 10 ? s.substring(0, 10).replaceAll('-', '.') : s;
  }

  // ── 알림 설정 (Option A 접이식 카테고리) ──
  Widget _buildNotifSettings(_C cs, Color myColor) {
    final cats = <Map<String, dynamic>>[
      {'icon': '⚾', 'label': '경기 알림', 'items': [
        {'label': '경기 시작', 'desc': '선발 발표·경기 취소 알림 포함', 'value': _notifyGameStart,
         'on': (bool v) { _notifyGameStart = v; }},
        {'label': '득점 변경', 'desc': '역전·연장전 포함', 'value': _notifyScoreChange,
         'on': (bool v) { _notifyScoreChange = v; }},
        {'label': '경기 종료', 'desc': '경기 결과 요약 포함', 'value': _notifyGameEnd,
         'on': (bool v) { _notifyGameEnd = v; }},
        {'label': '끝내기 승리', 'desc': '끝내기 득점으로 승리 시', 'value': _notifyWalkoff,
         'on': (bool v) { _notifyWalkoff = v; }},
        {'label': '투수 교체', 'desc': '선발 조기강판·투수 교체 시', 'value': _notifyStarterKo,
         'on': (bool v) { _notifyStarterKo = v; }},
        {'label': '마이팀 경기만', 'desc': _notifyMyTeamOnly ? '즐겨찾기 팀 경기에만 알림' : '모든 경기 알림',
         'value': _notifyMyTeamOnly, 'on': (bool v) { _notifyMyTeamOnly = v; }},
      ]},
      {'icon': '📊', 'label': '팀 알림', 'items': [
        {'label': '연승/연패', 'desc': '마이팀 5연승·연패 이상 시', 'value': _notifyStreak,
         'on': (bool v) { _notifyStreak = v; }},
        {'label': '순위 변동', 'desc': '마이팀 순위 변동·동률 1위 달성 시', 'value': _notifyRankChange,
         'on': (bool v) { _notifyRankChange = v; }},
        {'label': '선두 추격', 'desc': '마이팀 1위일 때 2위와 격차 좁혀질 때', 'value': _notifyPennantRace,
         'on': (bool v) { _notifyPennantRace = v; }},
        {'label': '팀 선수 대기록', 'desc': '마이팀 선수 시즌·월간·단일경기 기록', 'value': _notifyTeamMilestone,
         'on': (bool v) { _notifyTeamMilestone = v; }},
        {'label': '1군 등록/말소', 'desc': '마이팀 선수 등록 변경 시', 'value': _notifyRoster,
         'on': (bool v) { _notifyRoster = v; }},
      ]},
      {'icon': '🏃', 'label': '선수 알림', 'items': [
        {'label': '통산 대기록', 'desc': '즐겨찾기 선수 통산 기록 달성 시', 'value': _notifyMilestone,
         'on': (bool v) { _notifyMilestone = v; }},
        {'label': '오늘의 활약', 'desc': '즐겨찾기 선수 매일 출전 결과 요약', 'value': _notifyPlayerDaily,
         'on': (bool v) { _notifyPlayerDaily = v; }},
        {'label': '선수 뉴스', 'desc': '트레이드·방출·은퇴·FA·부상·시상', 'value': _notifyPlayerNews,
         'on': (bool v) { _notifyPlayerNews = v; }},
        {'label': '올스타 팬투표', 'desc': '투표 시작·마감 임박 + 즐겨찾기 선수 상위권', 'value': _notifyAllstarVote,
         'on': (bool v) { _notifyAllstarVote = v; }},
      ]},
      {'icon': '⚙️', 'label': '일반', 'items': [
        {'label': '댓글', 'desc': '내 글에 댓글이 달릴 때', 'value': _notifyComment,
         'on': (bool v) { _notifyComment = v; }},
        {'label': '심야 푸시 끄기', 'desc': '23:30~07:30 푸시 중단 (알림함엔 저장)', 'value': _notifyQuiet,
         'on': (bool v) { _notifyQuiet = v; }},
      ]},
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel(cs, '알림 설정'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Container(
          decoration: _cardDeco(cs),
          child: Column(children: cats.asMap().entries.map((e) {
            final i = e.key;
            final cat = e.value;
            final items = cat['items'] as List;
            final expanded = _expandedCats.contains(i);
            final isLast = i == cats.length - 1;
            return Column(children: [
              GestureDetector(
                onTap: () => setState(() => expanded ? _expandedCats.remove(i) : _expandedCats.add(i)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  decoration: BoxDecoration(
                    border: (!isLast || expanded) ? Border(bottom: BorderSide(color: cs.line)) : null,
                  ),
                  child: Row(children: [
                    Text(cat['icon'] as String, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 10),
                    Text(cat['label'] as String, style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: cs.ink)),
                    const Spacer(),
                    // 접힌 상태에서도 켜짐 현황 보이게 (중구난방 정리 06-12)
                    Builder(builder: (_) {
                      final onCnt = items.where((it) => it['value'] == true).length;
                      return Text('$onCnt/${items.length}',
                          style: TextStyle(fontSize: 11, fontWeight: Typo.bold,
                              color: onCnt == 0 ? cs.sub : myColor));
                    }),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.chevron_right, size: 16, color: cs.sub),
                    ),
                  ]),
                ),
              ),
              if (expanded)
                ...items.asMap().entries.map((ie) {
                  final ii = ie.key;
                  final item = ie.value as Map;
                  final itemLast = ii == items.length - 1;
                  final showBefore = item['label'] == '경기 시작';
                  return Column(children: [
                    Container(
                      padding: const EdgeInsets.only(left: 44, right: 16, top: 11, bottom: 11),
                      decoration: BoxDecoration(
                        border: (!itemLast || !isLast || showBefore) ? Border(bottom: BorderSide(color: cs.line)) : null,
                      ),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item['label'] as String, style: TextStyle(fontSize: 13, fontWeight: Typo.medium, color: cs.ink)),
                          const SizedBox(height: 3),
                          Text(item['desc'] as String, style: TextStyle(fontSize: 10, color: cs.sub, height: 1.4)),
                        ])),
                        const SizedBox(width: 12),
                        _AppToggle(
                          on: item['value'] as bool,
                          color: myColor,
                          track: cs.track,
                          onChanged: (v) { setState(() => (item['on'] as Function)(v)); _saveSettings(); },
                        ),
                      ]),
                    ),
                    // 경기 시작 ON 시 알림 시간 선택 노출
                    if (showBefore && _notifyGameStart)
                      _buildBeforeMinutes(cs, myColor, itemLast && isLast),
                  ]);
                }),
            ]);
          }).toList()),
        ),
      ),
    ]);
  }

  Widget _buildBeforeMinutes(_C cs, Color myColor, bool last) {
    Widget chip(int v, String label) {
      final sel = _notifyBeforeMinutes == v;
      return GestureDetector(
        onTap: () { setState(() => _notifyBeforeMinutes = v); _saveSettings(); },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: sel ? myColor : cs.paper2,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: sel ? myColor : cs.line),
          ),
          child: Text(label, style: TextStyle(fontSize: 11, fontWeight: sel ? Typo.bold : Typo.medium,
              color: sel ? Colors.white : cs.sub)),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.only(left: 44, right: 16, top: 4, bottom: 12),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.line))),
      child: Row(children: [
        Text('알림 시간', style: TextStyle(fontSize: 12, color: cs.ink3)),
        const Spacer(),
        chip(30, '30분'), const SizedBox(width: 6),
        chip(60, '1시간'), const SizedBox(width: 6),
        chip(120, '2시간'),
      ]),
    );
  }

  // ── 다크 모드 ──
  Widget _buildDarkMode(_C cs, Color myColor) {
    final tp = context.watch<ThemeProvider>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel(cs, '화면'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: _cardDeco(cs),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: cs.paper2, borderRadius: BorderRadius.circular(9)),
              child: Icon(tp.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined, size: 17, color: cs.ink3),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('다크 모드', style: TextStyle(fontSize: 13, fontWeight: Typo.bold, color: cs.ink))),
            _AppToggle(on: tp.isDark, color: myColor, track: cs.track, onChanged: (_) => tp.toggle()),
          ]),
        ),
      ),
    ]);
  }
}

// ── 공통 소형 위젯 ─────────────────────────────────────────────────────────────
class _SmallChip extends StatelessWidget {
  final String label;
  final Color color, bg;
  final Color? border;
  const _SmallChip({required this.label, required this.color, required this.bg, this.border});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: bg, borderRadius: BorderRadius.circular(Radii.xs),
      border: border != null ? Border.all(color: border!) : null,
    ),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: Typo.medium, color: color)),
  );
}

class _AppToggle extends StatelessWidget {
  final bool on;
  final Color color, track;
  final ValueChanged<bool> onChanged;
  const _AppToggle({required this.on, required this.color, required this.track, required this.onChanged});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onChanged(!on),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 40, height: 24,
      decoration: BoxDecoration(color: on ? color : track, borderRadius: BorderRadius.circular(12)),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 20, height: 20, margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))]),
        ),
      ),
    ),
  );
}

class _Btn32 extends StatelessWidget {
  final Widget child;
  final Color border;
  final VoidCallback onTap;
  const _Btn32({required this.child, required this.border, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(border: Border.all(color: border), borderRadius: BorderRadius.circular(10)),
      child: child,
    ),
  );
}

// ── 색상 헬퍼 ─────────────────────────────────────────────────────────────────
class _C {
  final Color bg, paper, paper2, ink, ink2, ink3, sub, line, line2, track;
  final bool dark;
  _C(BuildContext ctx)
    : dark   = Theme.of(ctx).brightness == Brightness.dark,
      bg     = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF0F0F12) : const Color(0xFFFAFAFB),
      paper  = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF18181C) : Colors.white,
      paper2 = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6),
      ink    = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFFF4F4F5) : const Color(0xFF111113),
      ink2   = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFFC9C9D1) : const Color(0xFF3F3F46),
      ink3   = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73),
      sub    = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF71717A) : const Color(0xFF9A9AA2),
      line   = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF26262C) : const Color(0xFFEDEDF0),
      line2  = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF33333A) : const Color(0xFFE0E0E4),
      track  = Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF2C2C33) : const Color(0xFFE8E8EC);
}
