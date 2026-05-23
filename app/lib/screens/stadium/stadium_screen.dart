import 'package:flutter/material.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/team_theme.dart';
import '../../api/api_service.dart';

class StadiumScreen extends StatefulWidget {
  const StadiumScreen({super.key});

  @override
  State<StadiumScreen> createState() => _StadiumScreenState();
}

class _StadiumScreenState extends State<StadiumScreen> {
  KakaoMapController? _mapController;
  int _selected = -1;

  static const _stadiums = [
    {
      'name': '잠실야구장',
      'city': '서울',
      'teams': ['LG', 'OB'],
      'teamNames': 'LG · 두산',
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
      'name': '한화생명이글스파크',
      'city': '대전',
      'teams': ['HH'],
      'teamNames': '한화',
      'lat': 36.3169,
      'lng': 127.4289,
      'address': '대전 중구 대종로 373',
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

  static final _koreaCenter = LatLng(36.5, 127.7);

  Set<Marker> get _markers => _stadiums.asMap().entries.map((e) {
    return Marker(
      markerId: 'stadium_${e.key}',
      latLng: LatLng(e.value['lat'] as double, e.value['lng'] as double),
    );
  }).toSet();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('구장 안내'),
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
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.38,
            child: KakaoMap(
              onMapCreated: (controller) {
                _mapController = controller;
              },
              markers: _markers.toList(),
              center: _koreaCenter,
              currentLevel: 13,
            ),
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
    final latLng = LatLng(s['lat'] as double, s['lng'] as double);
    _mapController?.setCenter(latLng);
    _mapController?.setLevel(4);

    if (!mounted) return;
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
    _mapController?.setCenter(_koreaCenter);
    _mapController?.setLevel(13);
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
            Icon(
              isSelected ? Icons.location_on : Icons.location_on_outlined,
              size: 20,
              color: isSelected ? color : Colors.grey[400],
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

class _NearbyFoodSheetState extends State<_NearbyFoodSheet> {
  List _places = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.getStadiumNearbyFood(widget.stadiumIndex + 1);
      if (mounted) setState(() { _places = data['places'] ?? []; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '맛집 정보를 불러올 수 없습니다'; _loading = false; });
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final color = teamColor(widget.teamCode);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, sc) => Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                TeamLogo(teamCode: widget.teamCode, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${widget.stadiumName} 주변 맛집',
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: TextStyle(color: Colors.grey[600])))
                    : _places.isEmpty
                        ? Center(child: Text('주변 맛집 정보가 없습니다', style: TextStyle(color: Colors.grey[600])))
                        : ListView.separated(
                            controller: sc,
                            itemCount: _places.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
                            itemBuilder: (_, i) {
                              final p = _places[i];
                              final dist = p['distance'] as int;
                              final distStr = dist >= 1000 ? '${(dist / 1000).toStringAsFixed(1)}km' : '${dist}m';
                              return ListTile(
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.restaurant, color: color, size: 20),
                                ),
                                title: Text(p['name'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                  '${p['category']} · $distStr${(p['phone'] as String).isNotEmpty ? '\n${p['phone']}' : ''}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                                isThreeLine: (p['phone'] as String).isNotEmpty,
                                trailing: const Icon(Icons.open_in_new, size: 16, color: Colors.grey),
                                onTap: () => _openUrl(p['url'] as String),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
