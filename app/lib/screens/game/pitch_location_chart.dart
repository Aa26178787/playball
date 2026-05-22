import 'package:flutter/material.dart';
import '../../api/api_service.dart';

class PitchLocationSheet extends StatefulWidget {
  final int gameId;

  const PitchLocationSheet({super.key, required this.gameId});

  @override
  State<PitchLocationSheet> createState() => _PitchLocationSheetState();
}

class _PitchLocationSheetState extends State<PitchLocationSheet> {
  List<Map> _pitches = [];
  List<String> _pitchers = [];
  List<String> _homePitchers = [];
  List<String> _awayPitchers = [];
  String _homeTeam = '홈';
  String _awayTeam = '원정';
  String? _selectedPitcher;
  String _filter = 'all';
  bool _loading = true;
  bool _error = false;

  static const _resultColors = {
    'ball':   Color(0xFF2196F3),
    'strike': Color(0xFFF44336),
    'swing':  Color(0xFFFF9800),
    'foul':   Color(0xFFFFEB3B),
    'hit':    Color(0xFF4CAF50),
    'other':  Color(0xFF9E9E9E),
  };

  static const _resultLabels = {
    'all':    '전체',
    'ball':   '볼',
    'strike': '스트라이크',
    'swing':  '헛스윙',
    'foul':   '파울',
    'hit':    '타격',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.getPitchLocations(widget.gameId);
      if (mounted) {
        final pitches = (data['pitches'] as List? ?? [])
            .map((p) => Map<String, dynamic>.from(p as Map))
            .toList();
        final pitchers = List<String>.from(data['pitchers'] ?? []);
        final homePitchers = List<String>.from(data['home_pitchers'] ?? []);
        final awayPitchers = List<String>.from(data['away_pitchers'] ?? []);
        setState(() {
          _pitches = pitches;
          _pitchers = pitchers;
          _homePitchers = homePitchers;
          _awayPitchers = awayPitchers;
          _homeTeam = data['home_team'] as String? ?? '홈';
          _awayTeam = data['away_team'] as String? ?? '원정';
          _selectedPitcher = pitchers.isNotEmpty ? pitchers.first : null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  List<Map> get _filtered {
    return _pitches.where((p) {
      final matchPitcher = _selectedPitcher == null || p['pitcher'] == _selectedPitcher;
      final matchFilter = _filter == 'all' || p['result'] == _filter;
      return matchPitcher && matchFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('투구 위치', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error)
            const Expanded(child: Center(child: Text('데이터를 불러오지 못했습니다', style: TextStyle(color: Colors.grey))))
          else if (_pitches.isEmpty)
            const Expanded(child: Center(child: Text('투구 위치 데이터가 없습니다', style: TextStyle(color: Colors.grey))))
          else ...[
            // 투수 선택 (홈/원정 분리)
            if (_pitchers.length > 1)
              _buildPitcherSelector(),
            // 결과 필터
            _buildResultFilter(),
            // 카운트
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '위치 데이터 ${_filtered.length}구',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            // 차트
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _StrikeZoneChart(pitches: _filtered, colors: _resultColors),
              ),
            ),
            // 범례
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  _legend('볼', _resultColors['ball']!),
                  _legend('스트라이크', _resultColors['strike']!),
                  _legend('헛스윙', _resultColors['swing']!),
                  _legend('파울', _resultColors['foul']!),
                  _legend('타격', _resultColors['hit']!),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPitcherSelector() {
    // 분류된 투수가 있으면 홈/원정 섹션으로 나눔, 없으면 단순 목록
    final hasGrouped = _homePitchers.isNotEmpty || _awayPitchers.isNotEmpty;
    if (!hasGrouped) {
      return _buildPitcherRow(null, _pitchers);
    }

    // 홈/원정 어느 쪽에도 없는 투수 (fallback)
    final classified = {..._homePitchers, ..._awayPitchers};
    final others = _pitchers.where((p) => !classified.contains(p)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_homePitchers.isNotEmpty) _buildPitcherRow(_homeTeam, _homePitchers),
        if (_awayPitchers.isNotEmpty) _buildPitcherRow(_awayTeam, _awayPitchers),
        if (others.isNotEmpty) _buildPitcherRow(null, others),
      ],
    );
  }

  Widget _buildPitcherRow(String? teamLabel, List<String> pitcherList) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (teamLabel != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1A237E).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(teamLabel,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: pitcherList.map((p) {
                  final sel = _selectedPitcher == p;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedPitcher = p),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: sel ? const Color(0xFF1A237E) : Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: sel ? const Color(0xFF1A237E) : Colors.grey[300]!,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          p,
                          style: TextStyle(
                            fontSize: 12,
                            color: sel ? Colors.white : Colors.black87,
                            fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _resultLabels.entries.map((e) {
            final sel = _filter == e.key;
            final color = e.key == 'all' ? const Color(0xFF1A237E) : (_resultColors[e.key] ?? Colors.grey);
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _filter = e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: sel ? color : Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: sel ? color : Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 11,
                      color: sel ? Colors.white : Colors.black87,
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _legend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black87)),
      ],
    );
  }
}

class _StrikeZoneChart extends StatelessWidget {
  final List<Map> pitches;
  final Map<String, Color> colors;

  const _StrikeZoneChart({required this.pitches, required this.colors});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) => CustomPaint(
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: _StrikeZonePainter(pitches: pitches, colors: colors),
      ),
    );
  }
}

class _StrikeZonePainter extends CustomPainter {
  final List<Map> pitches;
  final Map<String, Color> colors;

  _StrikeZonePainter({required this.pitches, required this.colors});

  static const double xMin = -2.5;
  static const double xMax = 2.5;
  static const double zMin = 0.0;
  static const double zMax = 5.5;
  static const double plateHalfW = 17.0 / 12.0;

  double get _avgTopSz {
    final vals = pitches.where((p) => p['top_sz'] != null).map((p) => (p['top_sz'] as num).toDouble());
    if (vals.isEmpty) return 3.3;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  double get _avgBotSz {
    final vals = pitches.where((p) => p['bot_sz'] != null).map((p) => (p['bot_sz'] as num).toDouble());
    if (vals.isEmpty) return 1.6;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  Offset _toCanvas(double x, double z, Size size) {
    final cx = (x - xMin) / (xMax - xMin) * size.width;
    final cy = (zMax - z) / (zMax - zMin) * size.height;
    return Offset(cx, cy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final topSz = _avgTopSz;
    final botSz = _avgBotSz;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFFF5F5F5));

    final groundY = _toCanvas(0, 0, size).dy;
    canvas.drawLine(
      Offset(0, groundY), Offset(size.width, groundY),
      Paint()..color = Colors.brown.withValues(alpha: 0.3)..strokeWidth = 1,
    );

    final tl = _toCanvas(-plateHalfW, topSz, size);
    final br = _toCanvas(plateHalfW, botSz, size);
    final zoneRect = Rect.fromPoints(tl, br);

    canvas.drawRect(zoneRect, Paint()..color = Colors.red.withValues(alpha: 0.06));
    canvas.drawRect(zoneRect,
        Paint()..color = Colors.red.withValues(alpha: 0.5)..style = PaintingStyle.stroke..strokeWidth = 1.5);

    final zoneH = (topSz - botSz) / 3;
    for (int i = 1; i <= 2; i++) {
      final y = _toCanvas(0, botSz + zoneH * i, size).dy;
      canvas.drawLine(Offset(tl.dx, y), Offset(br.dx, y),
          Paint()..color = Colors.red.withValues(alpha: 0.2)..strokeWidth = 0.5);
    }

    final zoneW = plateHalfW * 2 / 3;
    for (int i = 1; i <= 2; i++) {
      final x = _toCanvas(-plateHalfW + zoneW * i, 0, size).dx;
      canvas.drawLine(Offset(x, tl.dy), Offset(x, br.dy),
          Paint()..color = Colors.red.withValues(alpha: 0.2)..strokeWidth = 0.5);
    }

    final plateBottom = _toCanvas(0, 0, size);
    final plateLeft = _toCanvas(-plateHalfW, 0.15, size);
    final plateRight = _toCanvas(plateHalfW, 0.15, size);
    final platePath = Path()
      ..moveTo(plateLeft.dx, plateLeft.dy)
      ..lineTo(plateRight.dx, plateRight.dy)
      ..lineTo(plateBottom.dx, plateBottom.dy + 8)
      ..close();
    canvas.drawPath(platePath, Paint()..color = Colors.grey[300]!);
    canvas.drawPath(platePath,
        Paint()..color = Colors.grey[500]!..style = PaintingStyle.stroke..strokeWidth = 1);

    final centerX = _toCanvas(0, 0, size).dx;
    canvas.drawLine(
      Offset(centerX, 0), Offset(centerX, size.height),
      Paint()..color = Colors.grey.withValues(alpha: 0.2)..strokeWidth = 0.5,
    );

    for (final p in pitches) {
      final x = (p['x'] as num?)?.toDouble();
      final z = (p['z'] as num?)?.toDouble();
      if (x == null || z == null) continue;
      final result = p['result'] as String? ?? 'other';
      final color = colors[result] ?? colors['other']!;
      final pos = _toCanvas(x, z, size);

      if (pos.dx < -10 || pos.dx > size.width + 10 ||
          pos.dy < -10 || pos.dy > size.height + 10) continue;

      canvas.drawCircle(pos, 5.5, Paint()..color = Colors.black.withValues(alpha: 0.15));
      canvas.drawCircle(pos, 5, Paint()..color = color.withValues(alpha: 0.85));
      canvas.drawCircle(pos, 5,
          Paint()..color = Colors.white.withValues(alpha: 0.5)..style = PaintingStyle.stroke..strokeWidth = 1);
    }

    final textStyle = const TextStyle(fontSize: 9, color: Colors.grey);
    for (final z in [1.0, 2.0, 3.0, 4.0, 5.0]) {
      if (z > zMax) break;
      final y = _toCanvas(0, z, size).dy;
      final tp = TextPainter(
        text: TextSpan(text: '${z.toInt()}ft', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, y - 6));
    }
  }

  @override
  bool shouldRepaint(_StrikeZonePainter old) => old.pitches != pitches;
}
