import 'package:flutter/material.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import '../../utils/team_theme.dart';

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
