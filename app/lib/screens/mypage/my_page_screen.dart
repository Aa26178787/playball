import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import '../../api/api_service.dart';
import '../../providers/auth_provider.dart';
import '../../utils/team_theme.dart';
import '../player/player_detail_screen.dart';
import '../team/team_detail_screen.dart';
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
  bool _loading = true;

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
      ]);
      if (mounted) {
        setState(() {
          _user = results[0];
          _favoriteTeams = (results[1] as Map)['teams'] ?? [];
          _favoritePlayers = (results[2] as Map)['players'] ?? [];
          _loading = false;
        });
      }
    } catch (_) {
      setState(() => _loading = false);
    }
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
                  const SizedBox(height: 24),
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
    final phone = _user?['phone_number'];
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(
          Icons.email_outlined,
          color: verified ? Colors.green : Colors.orange,
        ),
        title: Text(verified
            ? '이메일 인증 완료'
            : '이메일 미인증'),
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
}
