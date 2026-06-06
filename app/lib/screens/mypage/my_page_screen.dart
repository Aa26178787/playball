import 'package:flutter/material.dart';
import '../../utils/design_tokens.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import '../../api/api_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../utils/team_theme.dart';
import '../../utils/local_cache.dart';
import '../player/player_detail_screen.dart';
import '../team/team_detail_screen.dart';
import '../community/post_detail_screen.dart';
import 'phone_verify_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
  bool _settingsLoaded      = false;

  @override
  void initState() {
    super.initState();
    // 캐시 즉시 표시 + API 병렬 갱신 — 캐시 완료를 기다리지 않아도 됨
    // (SharedPreferences 읽기 ~5ms, API ~200ms → 캐시가 항상 먼저 완료)
    _loadFromCache();
    _refreshFromApi();
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
      });
    } catch (_) {}
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
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null) return;
    // ImageCropper 1:1 크롭 UI — 검은 이미지 fix (resize 후 검은 변환 방지)
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      // image_cropper 7.1.0 cropStyle param 없음 — Android UI grid로 1:1 사각 가이드만
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90,
      maxWidth: 512,
      maxHeight: 512,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '프로필 이미지 크롭',
          toolbarColor: SemColor.panelDark,
          toolbarWidgetColor: Colors.white,
          statusBarColor: SemColor.panelDark,  // 상단 status bar 침범 방지
          backgroundColor: Colors.white,
          activeControlsWidgetColor: SemColor.panelDark,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: '프로필 이미지 크롭',
          aspectRatioLockEnabled: true,
        ),
      ],
    );
    if (cropped == null) return;
    setState(() => _uploadingImage = true);
    try {
      final url = await ApiService.uploadProfileImage(cropped.path);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('마이페이지'),
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: _logout,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: SemColor.brand(context), strokeWidth: 2.5))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildProfile(),
                  const SizedBox(height: 16),
                  _buildPhoneVerify(),
                  const SizedBox(height: 16),
                  _buildFavoriteTeams(),
                  const SizedBox(height: 16),
                  _buildFavoritePlayers(),
                  const SizedBox(height: 16),
                  _buildStadiumRecord(),
                  const SizedBox(height: 16),
                  _buildMyPosts(),
                  const SizedBox(height: 16),
                  _buildMyLikes(),
                  const SizedBox(height: 16),
                  _buildMyComments(),
                  const SizedBox(height: 16),
                  _buildNotificationSettings(),
                  const SizedBox(height: 8),
                  Consumer<ThemeProvider>(
                    builder: (ctx, tp, _) => SwitchListTile(
                      title: const Text('다크 모드'),
                      secondary: Icon(tp.isDark ? Icons.dark_mode : Icons.light_mode),
                      value: tp.isDark,
                      onChanged: (_) => tp.toggle(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _deleteAccount,
                    child: const Text('회원탈퇴',
                        style: TextStyle(color: Colors.red, fontSize: 13)),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildProfile() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            GestureDetector(
              onTap: _pickAndUploadImage,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: SemColor.panelDark,
                    backgroundImage: _user?['profile_image'] != null
                        ? CachedNetworkImageProvider(_user!['profile_image'])
                        : null,
                    child: _user?['profile_image'] == null
                        ? const Icon(Icons.person, color: Colors.white, size: 36)
                        : null,
                  ),
                  if (_uploadingImage)
                    const Positioned.fill(
                      child: CircleAvatar(
                        radius: 36,
                        backgroundColor: Colors.black45,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      ),
                    )
                  else
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: SemColor.panelDark,
                          shape: BoxShape.circle,
                          // 다크 배경 + panelDark 배지 윤곽 소실 방지
                          border: Border.all(color: Colors.white, width: 1.2),
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _user?['nickname'] ?? '-',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _editNickname,
                        child: const Icon(Icons.edit, size: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_user?['email'] ?? '',
                      style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneVerify() {
    final verified = _user?['phone_verified'] == true;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(
          Icons.email_outlined,
          color: verified ? Colors.green : Colors.orange,
        ),
        title: Text(verified ? '이메일 인증 완료' : '이메일 미인증'),
        subtitle: Text(verified
            ? (_user?['email'] ?? '')
            : '커뮤니티 글쓰기를 위해 이메일 인증하세요',
            style: const TextStyle(fontSize: 12)),
        trailing: verified
            ? const Icon(Icons.check_circle, color: Colors.green)
            : ElevatedButton(
                onPressed: () async {
                  final ok = await Navigator.push<bool>(context,
                      MaterialPageRoute(builder: (_) => const PhoneVerifyScreen()));
                  if (ok == true) _load();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: SemColor.panelDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('인증하기'),
              ),
      ),
    );
  }

  Widget _buildFavoriteTeams() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('마이팀', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        if (_favoriteTeams.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text('즐겨찾기한 팀이 없습니다', style: TextStyle(color: Colors.grey)),
              ),
            ),
          )
        else
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: _favoriteTeams.asMap().entries.map((e) {
                final t = e.value;
                final code = t['short_name'] ?? '';
                return ListTile(
                  leading: TeamLogo(teamCode: code, size: 36),
                  title: Text(t['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${t['rank'] ?? '-'}위  ${t['wins'] ?? 0}승 ${t['losses'] ?? 0}패'
                    '  승률 ${((t['win_rate'] ?? 0) * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => TeamDetailScreen(team: Map<String, dynamic>.from(t)))),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildFavoritePlayers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('즐겨찾기 선수', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        if (_favoritePlayers.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text('즐겨찾기한 선수가 없습니다', style: TextStyle(color: Colors.grey)),
              ),
            ),
          )
        else
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: _favoritePlayers.map((p) {
                return ListTile(
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundImage: p['profile_image'] != null
                        ? CachedNetworkImageProvider(p['profile_image'])
                        : null,
                    backgroundColor: Colors.grey[200],
                    child: p['profile_image'] == null
                        ? const Icon(Icons.person, size: 20)
                        : null,
                  ),
                  title: Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${p['team'] ?? ''} | ${p['position'] ?? ''}',
                      style: const TextStyle(fontSize: 12)),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => PlayerDetailScreen(
                        playerId: p['id'],
                        initialData: {'name': p['name'], 'team': p['team'], 'profile_image': p['profile_image'], 'position': p['position']},
                      ))),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildStadiumRecord() {
    final wins   = _stadiumVisits.where((v) => v['result'] == 'win').length;
    final losses = _stadiumVisits.where((v) => v['result'] == 'loss').length;
    final draws  = _stadiumVisits.where((v) => v['result'] == 'draw').length;
    final total  = wins + losses + draws;
    final winPct = total > 0 ? (wins / total * 100).toStringAsFixed(1) : '-';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.stadium, size: 18),
                const SizedBox(width: 8),
                const Text('직관 기록', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stadiumStat('승', wins, Colors.blue),
                _stadiumStat('패', losses, Colors.red),
                _stadiumStat('무', draws, Colors.grey),
                Column(children: [
                  Text(winPct == '-' ? '-' : '$winPct%',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const Text('직관 승률', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
              ],
            ),
            if (_stadiumVisits.isNotEmpty) ...[
              const Divider(height: 20),
              ..._stadiumVisits.take(5).map((v) => _buildVisitTile(v)),
            ],
            if (_stadiumVisits.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Text('캘린더에서 직관 기록을 추가해보세요',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisitTile(Map visit) {
    final result = visit['result'] as String;
    final color = result == 'win' ? Colors.blue : result == 'loss' ? Colors.red : Colors.grey;
    final label = result == 'win' ? '승' : result == 'loss' ? '패' : '무';
    final date = (visit['game_date'] as String? ?? '').replaceAll('-', '.').substring(0, 10);
    final home = visit['home_team'] as String? ?? '';
    final away = visit['away_team'] as String? ?? '';
    final hs = visit['home_score'] as int? ?? 0;
    final as_ = visit['away_score'] as int? ?? 0;
    final memo = visit['memo'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Center(child: Text(label,
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$away $as_  :  $hs $home',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                Text(date, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                if (memo != null && memo.isNotEmpty)
                  Text(memo, style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stadiumStat(String label, int value, Color color) {
    return Column(
      children: [
        Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _buildMyPosts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('내 게시글', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        if (_myPosts.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text('작성한 게시글이 없습니다', style: TextStyle(color: Colors.grey)),
              ),
            ),
          )
        else
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: _myPosts.take(5).map((p) {
                return ListTile(
                  title: Text(p['title'] ?? '',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${p['category'] ?? ''}  ❤️${p['likes'] ?? 0}  💬${p['comment_count'] ?? 0}',
                    style: const TextStyle(fontSize: 11)),
                  trailing: Text(
                    (p['created_at'] ?? '').toString().length >= 10
                        ? (p['created_at'] as String).substring(0, 10)
                        : '',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => PostDetailScreen(postId: p['id']))),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildMyLikes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('좋아요한 게시글', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        if (_myLikes.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text('좋아요한 게시글이 없습니다', style: TextStyle(color: Colors.grey)),
              ),
            ),
          )
        else
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: _myLikes.take(5).map((p) {
                return ListTile(
                  leading: const Icon(Icons.favorite, size: 16, color: Colors.red),
                  title: Text(p['title'] ?? '',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${p['author'] ?? ''}  ❤️${p['likes'] ?? 0}  💬${p['comment_count'] ?? 0}',
                    style: const TextStyle(fontSize: 11)),
                  trailing: Text(
                    (p['created_at'] ?? '').toString().length >= 10
                        ? (p['created_at'] as String).substring(0, 10)
                        : '',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => PostDetailScreen(postId: p['id']))),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildMyComments() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('내 댓글', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        if (_myComments.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text('작성한 댓글이 없습니다', style: TextStyle(color: Colors.grey)),
              ),
            ),
          )
        else
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: _myComments.take(5).map((c) {
                return ListTile(
                  title: Text(c['content'] ?? '',
                      style: const TextStyle(fontSize: 14),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    c['post_title'] ?? '',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    (c['created_at'] ?? '').toString().length >= 10
                        ? (c['created_at'] as String).substring(0, 10)
                        : '',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => PostDetailScreen(postId: c['post_id']))),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildNotificationSettings() {
    if (!_settingsLoaded) return const SizedBox.shrink();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('알림 설정',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          _notifCategory(Icons.sports_baseball, '경기 알림', [
            _notifTile('경기 시작', '선발 발표·경기 취소 알림 포함', _notifyGameStart,
                (v) { setState(() => _notifyGameStart = v); _saveSettings(); }),
            _buildBeforeMinutesTile(),
            _notifTile('득점 변경', '역전·연장전 포함', _notifyScoreChange,
                (v) { setState(() => _notifyScoreChange = v); _saveSettings(); }),
            _notifTile('경기 종료', '경기 결과 요약 포함', _notifyGameEnd,
                (v) { setState(() => _notifyGameEnd = v); _saveSettings(); }),
            _notifTile('끝내기 승리', '끝내기 득점으로 승리 시', _notifyWalkoff,
                (v) { setState(() => _notifyWalkoff = v); _saveSettings(); }),
            _notifTile('투수 교체', '선발 조기강판·투수 교체 시', _notifyStarterKo,
                (v) { setState(() => _notifyStarterKo = v); _saveSettings(); }),
            _notifTile(
              '마이팀 경기만',
              _notifyMyTeamOnly ? '즐겨찾기 팀 경기에만 알림' : '모든 경기 알림',
              _notifyMyTeamOnly,
              (v) { setState(() => _notifyMyTeamOnly = v); _saveSettings(); },
            ),
          ]),
          _notifCategory(Icons.leaderboard, '팀 알림', [
            _notifTile('연승/연패', '마이팀 5연승·연패 이상 시', _notifyStreak,
                (v) { setState(() => _notifyStreak = v); _saveSettings(); }),
            _notifTile('순위 변동', '마이팀 순위 변동·동률 1위 달성 시', _notifyRankChange,
                (v) { setState(() => _notifyRankChange = v); _saveSettings(); }),
            _notifTile('선두 추격', '마이팀 1위일 때 2위와 격차 좁혀질 때', _notifyPennantRace,
                (v) { setState(() => _notifyPennantRace = v); _saveSettings(); }),
            _notifTile('팀 선수 대기록', '마이팀 선수 시즌·월간·단일경기 기록 (홈런/타점/탈삼진 등)',
                _notifyTeamMilestone,
                (v) { setState(() => _notifyTeamMilestone = v); _saveSettings(); }),
            _notifTile('1군 등록/말소', '마이팀 선수 등록 변경 시', _notifyRoster,
                (v) { setState(() => _notifyRoster = v); _saveSettings(); }),
          ]),
          _notifCategory(Icons.person_outline, '선수 알림', [
            _notifTile('통산 대기록', '즐겨찾기 선수 통산 기록 달성 시 (홈런·안타·승·세이브 등)',
                _notifyMilestone,
                (v) { setState(() => _notifyMilestone = v); _saveSettings(); }),
            _notifTile('오늘의 활약', '즐겨찾기 선수 매일 출전 결과 요약', _notifyPlayerDaily,
                (v) { setState(() => _notifyPlayerDaily = v); _saveSettings(); }),
            _notifTile('선수 뉴스', '트레이드·방출·은퇴·FA·부상·시상·올스타·연속안타',
                _notifyPlayerNews,
                (v) { setState(() => _notifyPlayerNews = v); _saveSettings(); }),
          ]),
          _notifCategory(Icons.how_to_vote, '올스타 팬투표', [
            _notifTile('투표 기간 알림', '투표 시작·마감 D-3·D-1 + 즐겨찾기 선수 상위권 진입',
                _notifyAllstarVote,
                (v) { setState(() => _notifyAllstarVote = v); _saveSettings(); }),
          ]),
          _notifCategory(Icons.forum, '커뮤니티 알림', [
            _notifTile('댓글', '내 글에 댓글이 달릴 때', _notifyComment,
                (v) { setState(() => _notifyComment = v); _saveSettings(); }),
          ]),
        ],
      ),
    );
  }

  Widget _notifCategory(IconData icon, String title, List<Widget> children) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Icon(icon, size: 20),
        title: Text(title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        childrenPadding: EdgeInsets.zero,
        children: children,
      ),
    );
  }

  Widget _buildBeforeMinutesTile() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 4, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text('알림 시간',
                style: TextStyle(fontSize: 13, color: _notifyGameStart ? null : Colors.grey)),
          ),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 30, label: Text('30분', style: TextStyle(fontSize: 11))),
              ButtonSegment(value: 60, label: Text('1시간', style: TextStyle(fontSize: 11))),
              ButtonSegment(value: 120, label: Text('2시간', style: TextStyle(fontSize: 11))),
            ],
            selected: {_notifyBeforeMinutes},
            onSelectionChanged: _notifyGameStart
                ? (s) { setState(() => _notifyBeforeMinutes = s.first); _saveSettings(); }
                : null,
            style: ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notifTile(
      String title, String? subtitle, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 32, right: 16),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]))
          : null,
      value: value,
      onChanged: onChanged,
    );
  }
}
