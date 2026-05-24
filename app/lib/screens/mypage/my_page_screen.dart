import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../api/api_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../utils/team_theme.dart';
import '../player/player_detail_screen.dart';
import '../team/team_detail_screen.dart';
import '../community/post_detail_screen.dart';
import 'phone_verify_screen.dart';

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
  bool _loading = true;
  bool _uploadingImage = false;

  // 알림 설정
  bool _notifyGameStart   = true;
  bool _notifyScoreChange = true;
  bool _notifyGameEnd     = true;
  bool _notifyMyTeamOnly  = false;
  bool _notifyStreak       = true;
  bool _notifyRankChange   = true;
  bool _notifyRoster       = true;
  bool _notifyComment      = true;
  bool _notifyPennantRace  = true;
  bool _notifyFavHr        = true;
  bool _notifyWalkoff      = true;
  bool _notifyStarterKo    = true;
  bool _settingsLoaded     = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiService.getMe(),
        ApiService.getFavoriteTeams(),
        ApiService.getFavoritePlayers(),
        ApiService.getMyPosts(),
        ApiService.getMyComments(),
        ApiService.getSettings(),
        ApiService.getMyLikes(),
      ]);
      if (mounted) {
        final settings = (results[5] as Map)['settings'] as Map?;
        setState(() {
          _user = results[0];
          _favoriteTeams = (results[1] as Map)['teams'] ?? [];
          _favoritePlayers = (results[2] as Map)['players'] ?? [];
          _myPosts = (results[3] as Map)['posts'] ?? [];
          _myComments = (results[4] as Map)['comments'] ?? [];
          _myLikes = (results[6] as Map)['posts'] ?? [];
          if (settings != null) {
            _notifyGameStart   = settings['notify_game_start']   as bool? ?? true;
            _notifyScoreChange = settings['notify_score_change'] as bool? ?? true;
            _notifyGameEnd     = settings['notify_game_end']     as bool? ?? true;
            _notifyMyTeamOnly  = settings['notify_my_team_only'] as bool? ?? false;
            _notifyStreak      = settings['notify_streak']        as bool? ?? true;
            _notifyRankChange  = settings['notify_rank_change']  as bool? ?? true;
            _notifyRoster      = settings['notify_roster']       as bool? ?? true;
            _notifyComment     = settings['notify_comment']      as bool? ?? true;
            _notifyPennantRace = settings['notify_pennant_race'] as bool? ?? true;
            _notifyFavHr       = settings['notify_fav_hr']       as bool? ?? true;
            _notifyWalkoff     = settings['notify_walkoff']      as bool? ?? true;
            _notifyStarterKo   = settings['notify_starter_ko']   as bool? ?? true;
          }
          _settingsLoaded = true;
          _loading = false;
        });
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    try {
      await ApiService.updateSettings({
        'notify_game_start':   _notifyGameStart,
        'notify_score_change': _notifyScoreChange,
        'notify_game_end':     _notifyGameEnd,
        'notify_my_team_only': _notifyMyTeamOnly,
        'notify_streak':        _notifyStreak,
        'notify_rank_change':   _notifyRankChange,
        'notify_roster':        _notifyRoster,
        'notify_comment':       _notifyComment,
        'notify_pennant_race':  _notifyPennantRace,
        'notify_fav_hr':        _notifyFavHr,
        'notify_walkoff':       _notifyWalkoff,
        'notify_starter_ko':    _notifyStarterKo,
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
      await context.read<AuthProvider>().logout();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('탈퇴 처리 중 오류가 발생했습니다')));
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('닉네임이 변경되었습니다')));
    } on DioException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.response?.data?['detail'] ?? '변경 실패')));
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 512);
    if (picked == null) return;
    setState(() => _uploadingImage = true);
    try {
      final url = await ApiService.uploadProfileImage(picked.path);
      setState(() {
        _user?['profile_image'] = url;
        _uploadingImage = false;
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('프로필 이미지가 변경되었습니다')));
    } catch (_) {
      setState(() => _uploadingImage = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미지 업로드 실패')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('마이페이지'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: _logout,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                    backgroundColor: const Color(0xFF1A237E),
                    backgroundImage: _user?['profile_image'] != null
                        ? NetworkImage(_user!['profile_image'])
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
                        decoration: const BoxDecoration(
                          color: Color(0xFF1A237E),
                          shape: BoxShape.circle,
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
                  backgroundColor: const Color(0xFF1A237E),
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
                        ? NetworkImage(p['profile_image'])
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
                      builder: (_) => PlayerDetailScreen(playerId: p['id']))),
                );
              }).toList(),
            ),
          ),
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
            _notifTile('경기 시작', null, _notifyGameStart,
                (v) { setState(() => _notifyGameStart = v); _saveSettings(); }),
            _notifTile('득점', null, _notifyScoreChange,
                (v) { setState(() => _notifyScoreChange = v); _saveSettings(); }),
            _notifTile('경기 종료', null, _notifyGameEnd,
                (v) { setState(() => _notifyGameEnd = v); _saveSettings(); }),
            _notifTile('끝내기 승리', '홈팀 끝내기 승리 시', _notifyWalkoff,
                (v) { setState(() => _notifyWalkoff = v); _saveSettings(); }),
            _notifTile('선발 조기강판', '선발투수 5이닝 미만 강판 시', _notifyStarterKo,
                (v) { setState(() => _notifyStarterKo = v); _saveSettings(); }),
            _notifTile(
              '마이팀 경기만',
              _notifyMyTeamOnly ? '즐겨찾기 팀 경기에만 알림' : '모든 경기 알림',
              _notifyMyTeamOnly,
              (v) { setState(() => _notifyMyTeamOnly = v); _saveSettings(); },
            ),
          ]),
          _notifCategory(Icons.leaderboard, '팀 알림', [
            _notifTile('연승/연패', '마이팀 5연승/연패 이상', _notifyStreak,
                (v) { setState(() => _notifyStreak = v); _saveSettings(); }),
            _notifTile('순위 변동', '마이팀 순위 변동 시', _notifyRankChange,
                (v) { setState(() => _notifyRankChange = v); _saveSettings(); }),
            _notifTile('선두 추격', '마이팀이 1위일 때 2위와 게임차 좁혀질 때', _notifyPennantRace,
                (v) { setState(() => _notifyPennantRace = v); _saveSettings(); }),
          ]),
          _notifCategory(Icons.person_outline, '선수 알림', [
            _notifTile('즐겨찾기 선수 홈런', '즐겨찾기 선수가 홈런 칠 때', _notifyFavHr,
                (v) { setState(() => _notifyFavHr = v); _saveSettings(); }),
            _notifTile('등록말소', '즐겨찾기 선수 1군 등록/말소 시', _notifyRoster,
                (v) { setState(() => _notifyRoster = v); _saveSettings(); }),
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
