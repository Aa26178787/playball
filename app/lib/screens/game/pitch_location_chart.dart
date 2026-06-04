import 'dart:async';
import 'package:flutter/material.dart';
import '../../api/api_service.dart';

class PitchLocationSheet extends StatefulWidget {
  final int gameId;
  final String gameStatus;
  final String? initialPitcher;
  final String? initialBatter;
  final int? initialInning;

  const PitchLocationSheet({
    super.key,
    required this.gameId,
    this.gameStatus = '종료',
    this.initialPitcher,
    this.initialBatter,
    this.initialInning,
  });

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
  int? _selectedInning;   // null = 전체
  String? _selectedBatter; // null = 전체
  String _filter = 'all';
  bool _heatmap = false;

  bool _loading = true;
  bool _error = false;
  Timer? _refreshTimer;

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
    if (widget.initialPitcher != null) _selectedPitcher = widget.initialPitcher;
    if (widget.initialBatter != null) _selectedBatter = widget.initialBatter;
    if (widget.initialInning != null) _selectedInning = widget.initialInning;
    _load();
    if (widget.gameStatus == '진행') {
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
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
          if (_selectedPitcher == null && pitchers.isNotEmpty) {
            _selectedPitcher = pitchers.first;
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && !silent) setState(() { _loading = false; _error = true; });
    }
  }

  // 현재 선택 투수의 이닝 목록
  List<int> get _availableInnings {
    final set = <int>{};
    for (final p in _pitches) {
      if (p['pitcher'] == _selectedPitcher && p['inning'] != null) {
        set.add((p['inning'] as num).toInt());
      }
    }
    final list = set.toList()..sort();
    return list;
  }

  // 현재 선택 투수+이닝의 타자 목록 (첫 등장 순서 유지)
  List<String> get _availableBatters {
    final seen = <String>{};
    final ordered = <String>[];
    for (final p in _pitches) {
      if (p['pitcher'] == _selectedPitcher) {
        if (_selectedInning == null || (p['inning'] as num?)?.toInt() == _selectedInning) {
          final batter = p['batter'] as String? ?? '';
          if (batter.isNotEmpty && seen.add(batter)) ordered.add(batter);
        }
      }
    }
    return ordered;
  }

  List<Map> get _filtered {
    return _pitches.where((p) {
      final matchPitcher = _selectedPitcher == null || p['pitcher'] == _selectedPitcher;
      final matchInning = _selectedInning == null || (p['inning'] as num?)?.toInt() == _selectedInning;
      final matchBatter = _selectedBatter == null || p['batter'] == _selectedBatter;
      final matchResult = _filter == 'all' || p['result'] == _filter;
      return matchPitcher && matchInning && matchBatter && matchResult;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('투구 위치', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              if (widget.gameStatus == '진행') ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(4)),
                  child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _heatmap = !_heatmap),
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _heatmap ? const Color(0xFF111113) : Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _heatmap ? '히트맵' : '점 모드',
                    style: TextStyle(fontSize: 11, color: _heatmap ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error)
            Expanded(child: Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey[350]),
                const SizedBox(height: 12),
                const Text('데이터를 불러오지 못했습니다', style: TextStyle(color: Colors.grey, fontSize: 14)),
              ],
            )))
          else if (_pitches.isEmpty)
            Expanded(child: Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sports_baseball, size: 52, color: Colors.grey[300]),
                const SizedBox(height: 14),
                Text(
                  widget.gameStatus == '예정' ? '경기가 아직 시작되지 않았습니다' : '투구 위치 데이터가 없습니다',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black54),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.gameStatus == '예정' ? '경기 시작 후 데이터가 표시됩니다' : '이 경기의 투구 데이터가 제공되지 않습니다',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            )))
          else
            Expanded(
              child: Column(
                children: [
                  // 1단계: 투수 선택
                  _buildSectionLabel('① 투수'),
                  _buildPitcherSelector(),

                  // 2단계: 이닝 선택
                  _buildSectionLabel('② 이닝'),
                  _buildInningSelector(),

                  // 3단계: 타자 선택
                  _buildSectionLabel('③ 타자'),
                  _buildBatterSelector(),

                  // 결과 필터
                  _buildResultFilter(),

                  // 카운트
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      '${_filtered.length}구',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),

                  // 차트
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: ClipRect(
                        child: _heatmap
                            ? _HeatmapChart(pitches: _filtered)
                            : _StrikeZoneChart(pitches: _filtered, colors: _resultColors),
                      ),
                    ),
                  ),

                  // 범례
                  if (!_heatmap)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        alignment: WrapAlignment.center,
                        children: [
                          _legend('볼', _resultColors['ball']!),
                          _legend('스트라이크', _resultColors['strike']!),
                          _legend('헛스윙', _resultColors['swing']!),
                          _legend('파울', _resultColors['foul']!),
                          _legend('타격', _resultColors['hit']!),
                          _legendDash('끝면 상한', Colors.orange),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('낮음', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Container(
                            width: 80, height: 10, margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFF2196F3), Color(0xFFFFEB3B), Color(0xFFF44336)]),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const Text('높음', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 6, bottom: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF111113))),
      ),
    );
  }

  Widget _buildPitcherSelector() {
    final hasGrouped = _homePitchers.isNotEmpty || _awayPitchers.isNotEmpty;
    if (!hasGrouped) return _buildPitcherRow(null, _pitchers);
    final classified = {..._homePitchers, ..._awayPitchers};
    final others = _pitchers.where((p) => !classified.contains(p)).toList();
    return Column(children: [
      if (_homePitchers.isNotEmpty) _buildPitcherRow(_homeTeam, _homePitchers),
      if (_awayPitchers.isNotEmpty) _buildPitcherRow(_awayTeam, _awayPitchers),
      if (others.isNotEmpty) _buildPitcherRow(null, others),
    ]);
  }

  Widget _buildPitcherRow(String? teamLabel, List<String> pitcherList) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (teamLabel != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF111113).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(teamLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF111113))),
            ),
            const SizedBox(width: 6),
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
                      onTap: () => setState(() {
                        _selectedPitcher = p;
                        _selectedInning = null;
                        _selectedBatter = null;
                      }),
                      child: _chip(p, sel, const Color(0xFF111113)),
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

  Widget _buildInningSelector() {
    final innings = _availableInnings;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(() { _selectedInning = null; _selectedBatter = null; }),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _chip('전체', _selectedInning == null, Colors.grey[700]!),
                    ),
                  ),
                  ...innings.map((ing) {
                    final sel = _selectedInning == ing;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => setState(() { _selectedInning = ing; _selectedBatter = null; }),
                        child: _chip('${ing}회', sel, Colors.grey[700]!),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatterSelector() {
    final batters = _availableBatters;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _selectedBatter = null),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _chip('전체', _selectedBatter == null, Colors.teal),
                    ),
                  ),
                  ...batters.map((b) {
                    final sel = _selectedBatter == b;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedBatter = b),
                        child: _chip(b, sel, Colors.teal),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, Color color) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? color : Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? color : Colors.grey[300]!, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: selected ? Colors.white : Colors.black87,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildResultFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _resultLabels.entries.map((e) {
                  final sel = _filter == e.key;
                  final color = e.key == 'all' ? const Color(0xFF111113) : (_resultColors[e.key] ?? Colors.grey);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _filter = e.key),
                      child: _chip(e.value, sel, color),
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

  Widget _legendDash(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 10,
          child: CustomPaint(
            painter: _DashLinePainter(color),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black87)),
      ],
    );
  }
}

class _HeatmapChart extends StatelessWidget {
  final List<Map> pitches;
  const _HeatmapChart({required this.pitches});

  static const int cols = 10;
  static const int rows = 12;
  static const double xMin = _StrikeZonePainter.xMin;
  static const double xMax = _StrikeZonePainter.xMax;
  static const double zMin = _StrikeZonePainter.zMin;
  static const double zMax = _StrikeZonePainter.zMax;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) => CustomPaint(
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: _HeatmapPainter(pitches: pitches),
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final List<Map> pitches;
  _HeatmapPainter({required this.pitches});

  static const int cols = 10;
  static const int rows = 12;
  static const double xMin = _StrikeZonePainter.xMin;
  static const double xMax = _StrikeZonePainter.xMax;
  static const double zMin = _StrikeZonePainter.zMin;
  static const double zMax = _StrikeZonePainter.zMax;
  static const double plateHalfW = _StrikeZonePainter.plateHalfW;
  static const double absHalfW = _StrikeZonePainter.absHalfW;
  static const double absDropFt = _StrikeZonePainter.absDropFt;

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

  Color _heatColor(double t) {
    if (t < 0.5) {
      return Color.lerp(const Color(0xFF2196F3), const Color(0xFFFFEB3B), t * 2)!;
    } else {
      return Color.lerp(const Color(0xFFFFEB3B), const Color(0xFFF44336), (t - 0.5) * 2)!;
    }
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
    final topAbs = topSz;
    final botAbs = botSz;
    final topBack = topAbs - absDropFt;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFFF5F5F5));

    // Build density grid
    final grid = List.generate(rows, (_) => List.filled(cols, 0));
    for (final p in pitches) {
      final x = (p['x'] as num?)?.toDouble();
      final z = (p['z'] as num?)?.toDouble();
      if (x == null || z == null) continue;
      final col = ((x - xMin) / (xMax - xMin) * cols).floor().clamp(0, cols - 1);
      final row = ((zMax - z) / (zMax - zMin) * rows).floor().clamp(0, rows - 1);
      grid[row][col]++;
    }
    final maxCount = grid.fold<int>(0, (m, row) => row.fold<int>(m, (mm, v) => v > mm ? v : mm));

    final cellW = size.width / cols;
    final cellH = size.height / rows;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final count = grid[r][c];
        if (count == 0) continue;
        final t = maxCount > 0 ? count / maxCount : 0.0;
        final color = _heatColor(t).withValues(alpha: 0.7 + 0.3 * t);
        canvas.drawRect(
          Rect.fromLTWH(c * cellW, r * cellH, cellW, cellH),
          Paint()..color = color,
        );
      }
    }

    // Zone overlay
    final tl = _toCanvas(-absHalfW, topAbs, size);
    final br = _toCanvas(absHalfW, botAbs, size);
    final zoneRect = Rect.fromPoints(tl, br);
    canvas.drawRect(zoneRect,
        Paint()..color = Colors.white.withValues(alpha: 0.15)..style = PaintingStyle.stroke..strokeWidth = 2);

    final yTopBack = _toCanvas(0, topBack, size).dy;
    final dashPaint = Paint()
      ..color = Colors.orange.withValues(alpha: 0.8)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    double dx = tl.dx;
    while (dx < br.dx) {
      final end = dx + 4 < br.dx ? dx + 4 : br.dx;
      canvas.drawLine(Offset(dx, yTopBack), Offset(end, yTopBack), dashPaint);
      dx += 7;
    }

    // Grid lines 3x3
    final zoneH = (topAbs - botAbs) / 3;
    for (int i = 1; i <= 2; i++) {
      final y = _toCanvas(0, botAbs + zoneH * i, size).dy;
      canvas.drawLine(Offset(tl.dx, y), Offset(br.dx, y),
          Paint()..color = Colors.white.withValues(alpha: 0.4)..strokeWidth = 0.5);
    }
    final zoneW = absHalfW * 2 / 3;
    for (int i = 1; i <= 2; i++) {
      final x = _toCanvas(-absHalfW + zoneW * i, 0, size).dx;
      canvas.drawLine(Offset(x, tl.dy), Offset(x, br.dy),
          Paint()..color = Colors.white.withValues(alpha: 0.4)..strokeWidth = 0.5);
    }

    // Count labels on cells
    final textStyle = const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold);
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final count = grid[r][c];
        if (count == 0) continue;
        final tp = TextPainter(
          text: TextSpan(text: '$count', style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(c * cellW + (cellW - tp.width) / 2, r * cellH + (cellH - tp.height) / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) => old.pitches != pitches;
}

class _DashLinePainter extends CustomPainter {
  final Color color;
  const _DashLinePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1.5..style = PaintingStyle.stroke;
    double x = 0;
    while (x < size.width) {
      final end = x + 4 < size.width ? x + 4 : size.width;
      canvas.drawLine(Offset(x, size.height / 2), Offset(end, size.height / 2), paint);
      x += 7;
    }
  }
  @override
  bool shouldRepaint(_DashLinePainter old) => old.color != color;
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
  // KBO 홈플레이트 반폭 8.5인치(ft), 공 반지름 1.45인치(ft)
  // ABS: 공 중심이 플레이트 끝 + 공반지름 이내 → strike
  static const double plateHalfW = 8.5 / 12.0;          // 0.7083 ft
  static const double ballR      = 1.45 / 12.0;         // 0.1208 ft
  static const double absHalfW   = plateHalfW + ballR;  // 0.8292 ft
  // 끝면(후면) 높이 오프셋: 중간면보다 1.5cm 낮게 설정 (KBO ABS 공식 규정)
  static const double absDropFt  = 1.5 / 30.48;         // 0.0492 ft

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
    // topSz/botSz = ABS 판정 경계 (이미 ball-edge 기준, 추가 ballR 불필요)
    final topAbs = topSz;
    final botAbs = botSz;
    // 끝면(후면) 기준 상한: 중간면보다 1.5cm 낮음
    final topBack = topAbs - absDropFt;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFFF5F5F5));

    final groundY = _toCanvas(0, 0, size).dy;
    canvas.drawLine(
      Offset(0, groundY), Offset(size.width, groundY),
      Paint()..color = Colors.brown.withValues(alpha: 0.3)..strokeWidth = 1,
    );

    // ABS 스트라이크존 (공 중심 기준 판정 경계)
    final tl = _toCanvas(-absHalfW, topAbs, size);
    final br = _toCanvas(absHalfW, botAbs, size);
    final zoneRect = Rect.fromPoints(tl, br);

    // 중간면+끝면 모두 통과 구역 (확정 스트라이크)
    canvas.drawRect(zoneRect, Paint()..color = Colors.red.withValues(alpha: 0.06));

    // 끝면 기준 상한선 위 구역: 중간면 통과 but 끝면 불통 가능 (경계 영역)
    final yTopBack = _toCanvas(0, topBack, size).dy;
    canvas.drawRect(
      Rect.fromLTRB(tl.dx, tl.dy, br.dx, yTopBack),
      Paint()..color = Colors.orange.withValues(alpha: 0.13),
    );

    // 전체 존 테두리 (중간면 기준)
    canvas.drawRect(zoneRect,
        Paint()..color = Colors.red.withValues(alpha: 0.5)..style = PaintingStyle.stroke..strokeWidth = 1.5);

    // 끝면 상한선: 점선
    final dashPaint = Paint()
      ..color = Colors.orange.withValues(alpha: 0.75)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    _drawDashedHLine(canvas, tl.dx, br.dx, yTopBack, dashPaint);

    // 3x3 구역 구분선
    final zoneH = (topAbs - botAbs) / 3;
    for (int i = 1; i <= 2; i++) {
      final y = _toCanvas(0, botAbs + zoneH * i, size).dy;
      canvas.drawLine(Offset(tl.dx, y), Offset(br.dx, y),
          Paint()..color = Colors.red.withValues(alpha: 0.2)..strokeWidth = 0.5);
    }

    final zoneW = absHalfW * 2 / 3;
    for (int i = 1; i <= 2; i++) {
      final x = _toCanvas(-absHalfW + zoneW * i, 0, size).dx;
      canvas.drawLine(Offset(x, tl.dy), Offset(x, br.dy),
          Paint()..color = Colors.red.withValues(alpha: 0.2)..strokeWidth = 0.5);
    }

    // 홈플레이트 실제 폭 (±8.5인치) — tip을 캔버스 안에 고정
    final plateCenter = _toCanvas(0, 0, size);
    final plateLeft = _toCanvas(-plateHalfW, 0.15, size);
    final plateRight = _toCanvas(plateHalfW, 0.15, size);
    final plateTipY = (plateCenter.dy + 8).clamp(0.0, size.height - 1);
    final platePath = Path()
      ..moveTo(plateLeft.dx, plateLeft.dy)
      ..lineTo(plateRight.dx, plateRight.dy)
      ..lineTo(plateCenter.dx, plateTipY)
      ..close();
    canvas.drawPath(platePath, Paint()..color = Colors.grey[300]!);
    canvas.drawPath(platePath,
        Paint()..color = Colors.grey[500]!..style = PaintingStyle.stroke..strokeWidth = 1);

    final centerX = plateCenter.dx;
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

  void _drawDashedHLine(Canvas canvas, double x1, double x2, double y, Paint paint,
      {double dashLen = 4, double gapLen = 3}) {
    double x = x1;
    while (x < x2) {
      final end = x + dashLen < x2 ? x + dashLen : x2;
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(_StrikeZonePainter old) => old.pitches != pitches;
}
