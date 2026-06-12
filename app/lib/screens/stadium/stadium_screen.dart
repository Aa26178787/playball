import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/team_theme.dart';
import '../../api/api_service.dart';

class StadiumScreen extends StatefulWidget {
  final int? initialIndex;
  const StadiumScreen({super.key, this.initialIndex});

  @override
  State<StadiumScreen> createState() => _StadiumScreenState();
}

class _StadiumScreenState extends State<StadiumScreen> {
  InAppWebViewController? _webController;
  bool _mapReady = false;
  int _selected = -1;

  @override
  void dispose() {
    // WebView 명시적 정리 — Native 메모리 누수 방지
    try {
      _webController?.stopLoading();
      _webController = null;
    } catch (e) { debugPrint('stadium_screen: $e'); }
    super.dispose();
  }

  static const _stadiums = [
    {
      'name': '잠실야구장 (LG)',
      'city': '서울',
      'teams': ['LG'],
      'teamNames': 'LG',
      'lat': 37.5121,
      'lng': 127.0719,
      'address': '서울 송파구 올림픽로 19-2',
    },
    {
      'name': '잠실야구장 (두산)',
      'city': '서울',
      'teams': ['OB'],
      'teamNames': '두산',
      'lat': 37.5121,
      'lng': 127.0719,
      'address': '서울 송파구 올림픽로 19-2',
    },
    {
      'name': '고척스카이돔',
      'city': '서울',
      'teams': ['WO'],
      'teamNames': '키움',
      'lat': 37.4982,
      'lng': 126.8672,
      'address': '서울 구로구 경인로 430',
    },
    {
      'name': 'KT위즈파크',
      'city': '수원',
      'teams': ['KT'],
      'teamNames': 'KT',
      'lat': 37.2997,
      'lng': 127.0095,
      'address': '경기 수원시 장안구 경수대로 893',
    },
    {
      'name': 'SSG랜더스필드',
      'city': '인천',
      'teams': ['SK'],
      'teamNames': 'SSG',
      'lat': 37.4370,
      'lng': 126.6934,
      'address': '인천 미추홀구 매소홀로 618',
    },
    {
      'name': '대전한화생명볼파크',
      'city': '대전',
      'teams': ['HH'],
      'teamNames': '한화',
      // 한밭종합운동장 야구장 기준 우하단 (남동측) ~150m
      'lat': 36.31655,
      'lng': 127.43040,
      'address': '대전광역시 중구 대종로 373',
    },
    {
      'name': '광주기아챔피언스필드',
      'city': '광주',
      'teams': ['HT'],
      'teamNames': 'KIA',
      'lat': 35.1685,
      'lng': 126.8890,
      'address': '광주 북구 서림로 10',
    },
    {
      'name': '삼성라이온즈파크',
      'city': '대구',
      'teams': ['SS'],
      'teamNames': '삼성',
      'lat': 35.8411,
      'lng': 128.6813,
      'address': '대구 수성구 야구전설로 1',
    },
    {
      'name': '창원NC파크',
      'city': '창원',
      'teams': ['NC'],
      'teamNames': 'NC',
      'lat': 35.2225,
      'lng': 128.5816,
      'address': '경남 창원시 마산회원구 삼호로 64',
    },
    {
      'name': '사직야구장',
      'city': '부산',
      'teams': ['LT'],
      'teamNames': '롯데',
      'lat': 35.1940,
      'lng': 129.0613,
      'address': '부산 동래구 사직로 45',
    },
  ];

  static const _mapHtml = '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
html, body, #map { width: 100%; height: 100%; }
</style>
</head>
<body>
<div id="map"></div>
<script type="text/javascript" src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=e8a2fd480f33d1dd415e3979e830eb8d"></script>
<script>
var container = document.getElementById('map');
var map = new kakao.maps.Map(container, {
  center: new kakao.maps.LatLng(36.5, 127.7),
  level: 12
});

var stadiums = [
  {lat:37.5121, lng:127.0719, name:'잠실야구장 (LG/두산)'},
  {lat:37.4982, lng:126.8672, name:'고척스카이돔'},
  {lat:37.2997, lng:127.0095, name:'KT위즈파크'},
  {lat:37.4370, lng:126.6934, name:'SSG랜더스필드'},
  {lat:36.31655, lng:127.43040, name:'대전한화생명볼파크'},
  {lat:35.1685, lng:126.8890, name:'광주기아챔피언스필드'},
  {lat:35.8411, lng:128.6813, name:'삼성라이온즈파크'},
  {lat:35.2225, lng:128.5816, name:'창원NC파크'},
  {lat:35.1940, lng:129.0613, name:'사직야구장'}
];

var markerImg = new kakao.maps.MarkerImage(
  'https://t1.daumcdn.net/localimg/localimages/07/mapapidoc/markerStar.png',
  new kakao.maps.Size(24, 35)
);

stadiums.forEach(function(s) {
  var marker = new kakao.maps.Marker({
    map: map,
    position: new kakao.maps.LatLng(s.lat, s.lng),
    title: s.name
  });
  var overlay = new kakao.maps.CustomOverlay({
    position: new kakao.maps.LatLng(s.lat, s.lng),
    content: '<div style="background:rgba(26,35,126,0.85);color:#fff;padding:3px 7px;border-radius:10px;font-size:11px;white-space:nowrap;margin-bottom:4px">' + s.name + '</div>',
    yAnchor: 2.8
  });
  overlay.setMap(map);
});

function moveTo(lat, lng) {
  // 순서: setLevel 먼저 → setCenter (KakaoMap convention) + redundant setLevel for race
  map.setLevel(5);
  map.setCenter(new kakao.maps.LatLng(lat, lng));
  setTimeout(function() { map.setLevel(5); map.relayout && map.relayout(); }, 250);
  setTimeout(function() { map.setLevel(5); }, 700);
}
function resetView() {
  map.setCenter(new kakao.maps.LatLng(36.5, 127.7));
  map.setLevel(12);
}
</script>
</body>
</html>
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('구장 안내'),
        surfaceTintColor: Colors.transparent,
        actions: [
          if (_selected >= 0)
            TextButton(
              onPressed: _resetView,
              child: const Text('전체'),
            ),
        ],
      ),
      body: Column(
        children: [
          // 웹: inappwebview = 스텁(카카오맵 미지원 영역) — 무한로딩 대신 외부 링크 카드
          if (kIsWeb)
            _buildWebMapFallback(context)
          else
            SizedBox(
            height: MediaQuery.of(context).size.height * 0.38,
            child: Stack(children: [
              InAppWebView(
                initialData: InAppWebViewInitialData(
                  data: _mapHtml,
                  mimeType: 'text/html',
                  encoding: 'utf-8',
                  baseUrl: WebUri('https://playball.duckdns.org'),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  transparentBackground: true,
                ),
                onWebViewCreated: (controller) {
                  _webController = controller;
                },
                onLoadStop: (controller, url) {
                  if (mounted) {
                    setState(() => _mapReady = true);
                    final idx = widget.initialIndex;
                    if (idx != null && idx >= 0 && idx < _stadiums.length) {
                      Future.delayed(const Duration(milliseconds: 600), () {
                        if (mounted) _focusStadium(idx);
                      });
                    }
                  }
                },
              ),
              if (!_mapReady)
                Container(
                  color: Colors.grey[50],
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(strokeWidth: 2),
                        SizedBox(height: 12),
                        Text('지도 불러오는 중...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _stadiums.length,
              itemBuilder: (_, i) => _buildStadiumCard(i),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _focusStadium(int i) async {
    setState(() => _selected = i);
    final s = _stadiums[i];
    final lat = s['lat'] as double;
    final lng = s['lng'] as double;
    await _webController?.evaluateJavascript(source: 'moveTo($lat, $lng)');
  }

  // 웹 폴백 — 선택 구장(또는 안내) + 카카오맵 새 탭 열기
  Widget _buildWebMapFallback(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sel = _selected >= 0 ? _stadiums[_selected] : null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF18181C) : const Color(0xFFF4F4F6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        Icon(Icons.map_outlined, size: 30,
            color: isDark ? const Color(0xFF9A9AA0) : const Color(0xFF707078)),
        const SizedBox(height: 8),
        Text(
          sel != null ? (sel['name'] as String) : '구장을 선택하면 지도를 볼 수 있어요',
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: sel == null
              ? null
              : () {
                  final name = Uri.encodeComponent(
                      (sel['name'] as String).split(' (').first);
                  launchUrl(
                    Uri.parse('https://map.kakao.com/link/map/$name,${sel['lat']},${sel['lng']}'),
                    mode: LaunchMode.externalApplication,
                  );
                },
          icon: const Icon(Icons.open_in_new, size: 15),
          label: const Text('카카오맵에서 보기', style: TextStyle(fontSize: 12.5)),
        ),
      ]),
    );
  }

  void _openFoodSheet(int i) {
    final s = _stadiums[i];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _NearbyFoodSheet(
        stadiumIndex: i,
        stadiumName: s['name'] as String,
        teamCode: (s['teams'] as List).first as String,
      ),
    );
  }

  Future<void> _resetView() async {
    setState(() => _selected = -1);
    await _webController?.evaluateJavascript(source: 'resetView()');
  }

  Widget _buildStadiumCard(int i) {
    final s = _stadiums[i];
    final isSelected = _selected == i;
    final teams = s['teams'] as List;
    final code = teams.first as String;
    final color = teamColor(code);

    return InkWell(
      onTap: () => _focusStadium(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.07) : null,
          border: Border(
            left: BorderSide(
              color: isSelected ? color : Colors.transparent,
              width: 4,
            ),
            bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: teams.length == 2 ? 80 : 40,
              child: Row(
                children: teams.map((t) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: TeamLogo(teamCode: t as String, size: 36),
                )).toList(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s['name'] as String,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? color : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${s['city']} · ${s['teamNames']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  if (isSelected) ...[
                    const SizedBox(height: 2),
                    Text(
                      s['address'] as String,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSelected ? Icons.location_on : Icons.location_on_outlined,
                  size: 20,
                  color: isSelected ? color : Colors.grey[400],
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.restaurant_menu, size: 20,
                      color: isSelected ? color : Colors.grey[400]),
                  tooltip: '맛집 보기',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _openFoodSheet(i),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NearbyFoodSheet extends StatefulWidget {
  final int stadiumIndex;
  final String stadiumName;
  final String teamCode;

  const _NearbyFoodSheet({
    required this.stadiumIndex,
    required this.stadiumName,
    required this.teamCode,
  });

  @override
  State<_NearbyFoodSheet> createState() => _NearbyFoodSheetState();
}

class _NearbyFoodSheetState extends State<_NearbyFoodSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 카카오 탭
  List _kakaoPlaces = [];
  bool _kakaoLoading = true;

  // 팬 추천 탭
  List _communityPlaces = [];
  bool _communityLoading = false;
  bool _communityLoaded = false;

  // 내 투표 목록
  final Set<int> _myVotes = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_communityLoaded) _loadCommunity();
    });
    _loadKakao();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadKakao() async {
    try {
      final data = await ApiService.getStadiumNearbyFood(widget.stadiumIndex + 1);
      if (mounted) setState(() { _kakaoPlaces = data['places'] ?? []; _kakaoLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _kakaoLoading = false; });
    }
  }

  Future<void> _loadCommunity() async {
    if (mounted) setState(() => _communityLoading = true);
    try {
      final data = await ApiService.getCommunityFood(widget.stadiumIndex + 1);
      if (mounted) {
        setState(() {
        _communityPlaces = data['places'] ?? [];
        _communityLoading = false;
        _communityLoaded = true;
      });
      }
    } catch (_) {
      if (mounted) setState(() { _communityLoading = false; _communityLoaded = true; });
    }
  }

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _vote(int placeId) async {
    try {
      final res = await ApiService.voteFoodPlace(placeId);
      final voted = res['voted'] as bool;
      setState(() {
        if (voted) {
          _myVotes.add(placeId);
        } else {
          _myVotes.remove(placeId);
        }
        final idx = _communityPlaces.indexWhere((p) => p['id'] == placeId);
        if (idx >= 0) {
          final cur = (_communityPlaces[idx]['upvote_count'] as int);
          _communityPlaces[idx] = Map.from(_communityPlaces[idx])
            ..['upvote_count'] = voted ? cur + 1 : cur - 1;
        }
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인이 필요합니다')),
        );
      }
    }
  }

  void _showSubmitSheet(Color color) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SubmitFoodSheet(
        stadiumId: widget.stadiumIndex + 1,
        color: color,
        onSubmitted: () {
          _communityLoaded = false;
          _loadCommunity();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = teamColor(widget.teamCode);
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TeamLogo(teamCode: widget.teamCode, size: 28),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${widget.stadiumName} 맛집',
                        style: const TextStyle(
                          color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 20),
                      tooltip: '닫기',
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.white,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white60,
                  labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  tabs: const [Tab(text: '카카오 추천'), Tab(text: '팬 추천')],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildKakaoTab(color),
                _buildCommunityTab(color),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKakaoTab(Color color) {
    if (_kakaoLoading) return const Center(child: CircularProgressIndicator());
    if (_kakaoPlaces.isEmpty) {
      return Center(child: Text('주변 맛집 정보가 없습니다', style: TextStyle(color: Colors.grey[600])));
    }
    return ListView.separated(
      itemCount: _kakaoPlaces.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
      itemBuilder: (_, i) {
        final p = _kakaoPlaces[i];
        final dist = p['distance'] as int;
        final distStr = dist >= 1000 ? '${(dist / 1000).toStringAsFixed(1)}km' : '${dist}m';
        return ListTile(
          leading: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.restaurant, color: color, size: 18),
          ),
          title: Text(p['name'] as String,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          subtitle: Text(
            '${p['category']} · $distStr${(p['phone'] as String).isNotEmpty ? '\n${p['phone']}' : ''}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          isThreeLine: (p['phone'] as String).isNotEmpty,
          trailing: const Icon(Icons.open_in_new, size: 16, color: Colors.grey),
          onTap: () => _openUrl(p['url'] as String),
        );
      },
    );
  }

  Widget _buildCommunityTab(Color color) {
    if (_communityLoading) return const Center(child: CircularProgressIndicator());
    return Stack(
      children: [
        _communityPlaces.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.restaurant_menu, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text('아직 팬 추천 맛집이 없습니다\n첫 번째로 추천해보세요!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: _communityPlaces.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
                itemBuilder: (_, i) {
                  final p = _communityPlaces[i];
                  final isApproved = p['status'] == 'approved';
                  final votes = p['upvote_count'] as int;
                  final voted = _myVotes.contains(p['id'] as int);
                  return ListTile(
                    leading: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: isApproved
                            ? color.withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isApproved ? Icons.verified : Icons.restaurant,
                        color: isApproved ? color : Colors.grey,
                        size: 18,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(p['name'] as String,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                        if (isApproved)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('인증', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${p['category']} · ${p['submitted_by']} 추천',
                            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                        if ((p['memo'] as String).isNotEmpty)
                          Text('"${p['memo']}"',
                              style: TextStyle(fontSize: 11, color: Colors.grey[500],
                                  fontStyle: FontStyle.italic)),
                      ],
                    ),
                    trailing: GestureDetector(
                      onTap: () => _vote(p['id'] as int),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(voted ? Icons.thumb_up : Icons.thumb_up_outlined,
                              size: 18, color: voted ? color : Colors.grey),
                          Text('$votes', style: TextStyle(fontSize: 11, color: voted ? color : Colors.grey)),
                        ],
                      ),
                    ),
                    isThreeLine: (p['memo'] as String).isNotEmpty,
                    onTap: () => _openUrl(p['url'] as String),
                  );
                },
              ),
        Positioned(
          bottom: 16, right: 16,
          child: FloatingActionButton.extended(
            onPressed: () => _showSubmitSheet(color),
            backgroundColor: color,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('맛집 제안', style: TextStyle(fontSize: 13)),
          ),
        ),
      ],
    );
  }
}

// ── 팬 맛집 제안 시트 ────────────────────────────────────────────────────────

class _SubmitFoodSheet extends StatefulWidget {
  final int stadiumId;
  final Color color;
  final VoidCallback onSubmitted;

  const _SubmitFoodSheet({
    required this.stadiumId,
    required this.color,
    required this.onSubmitted,
  });

  @override
  State<_SubmitFoodSheet> createState() => _SubmitFoodSheetState();
}

class _SubmitFoodSheetState extends State<_SubmitFoodSheet> {
  final _searchCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  List _results = [];
  bool _searching = false;
  Map? _selected;
  bool _submitting = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _searching = true; _results = []; _selected = null; });
    try {
      final data = await ApiService.searchFoodPlace(widget.stadiumId, q);
      if (mounted) setState(() { _results = data['places'] ?? []; _searching = false; });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _submit() async {
    if (_selected == null) return;
    setState(() => _submitting = true);
    try {
      await ApiService.submitFoodPlace(widget.stadiumId, {
        'kakao_place_id': _selected!['id'],
        'name': _selected!['name'],
        'category': _selected!['category'],
        'address': _selected!['address'],
        'phone': _selected!['phone'],
        'url': _selected!['url'],
        'memo': _memoCtrl.text.trim(),
      });
      widget.onSubmitted();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('제안이 등록되었습니다. 팬 5명의 추천을 받으면 목록에 표시됩니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        final msg = e.toString().contains('409') ? '이미 등록된 장소입니다' : '제안 실패. 로그인 상태를 확인해주세요';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('맛집 제안', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: '닫기',
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('구장 2km 이내 음식점만 등록 가능합니다',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: '가게 이름 검색',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _searching ? null : _search,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  child: _searching
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('검색'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_selected != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: widget.color.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_selected!['name'] as String,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('${_selected!['category']} · ${_selected!['address']}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _memoCtrl,
                decoration: InputDecoration(
                  hintText: '추천 이유 (선택)',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
                maxLength: 50,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.color,
                    foregroundColor: Colors.white,
                  ),
                  child: _submitting
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('제안하기'),
                ),
              ),
            ] else if (_results.isNotEmpty) ...[
              Expanded(
                child: ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
                  itemBuilder: (_, i) {
                    final r = _results[i];
                    final dist = r['distance'] as int;
                    final distStr = dist >= 1000
                        ? '${(dist / 1000).toStringAsFixed(1)}km'
                        : '${dist}m';
                    return ListTile(
                      dense: true,
                      title: Text(r['name'] as String,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: Text('${r['category']} · $distStr',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      trailing: const Icon(Icons.add_circle_outline, size: 20),
                      onTap: () => setState(() { _selected = r; _results = []; }),
                    );
                  },
                ),
              ),
            ] else if (!_searching && _searchCtrl.text.isNotEmpty && _results.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Center(
                  child: Text('검색 결과가 없습니다. 구장 2km 이내 음식점만 검색됩니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
