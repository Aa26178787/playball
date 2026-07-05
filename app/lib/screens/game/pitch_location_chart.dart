import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../widgets/common_widgets.dart';
import '../../utils/design_tokens.dart';
import '../../utils/pitch_trajectory.dart';
import '../../api/api_service.dart';

enum _ViewMode { zone, traj }

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
  int? _selectedInning;
  String? _selectedBatter;
  String _filter = 'all';
  _ViewMode _viewMode = _ViewMode.zone;
  int? _selectedPitchIdx;

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
            .map((p) {
              final m = Map<String, dynamic>.from(p as Map);
              // Task 6: parse physics — stored under '_phys' key (PitchPhysics? value)
              m['_phys'] = PitchPhysics.fromJson(m['physics'] as Map?);
              return m;
            })
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

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _ink => Pal.ink(_isDark);
  Color get _paper => Pal.paper(_isDark);
  Color get _paper2 => Pal.paper2(_isDark);
  Color get _line => Pal.line(_isDark);
  Color get _sub => _isDark ? const Color(0xFF9A9AA3) : const Color(0xFF9A9AA2);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.lg)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(2)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('투구 위치', style: TextStyle(fontSize: Typo.title, fontWeight: Typo.extra, color: _ink, letterSpacing: -0.3)),
              if (widget.gameStatus == '진행') ...[
                const SizedBox(width: Space.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: SemColor.live, borderRadius: BorderRadius.circular(Radii.xs)),
                  child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: Typo.caption, fontWeight: Typo.bold)),
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.xs),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error)
            const Expanded(child: AppErrorView(message: '데이터를 불러오지 못했습니다'))
          else if (_pitches.isEmpty)
            Expanded(child: Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sports_baseball, size: 52, color: Colors.grey[300]),
                const SizedBox(height: 14),
                Text(
                  widget.gameStatus == '예정' ? '경기가 아직 시작되지 않았습니다' : '투구 위치 데이터가 없습니다',
                  style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.medium, color: _ink),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.gameStatus == '예정' ? '경기 시작 후 데이터가 표시됩니다' : '이 경기의 투구 데이터가 제공되지 않습니다',
                  style: TextStyle(fontSize: Typo.small, color: Colors.grey[500]),
                ),
              ],
            )))
          else
            Expanded(
              child: Column(
                children: [
                  _buildSectionLabel('① 투수'),
                  _buildPitcherSelector(),
                  _buildSectionLabel('② 이닝'),
                  _buildInningSelector(),
                  _buildSectionLabel('③ 타자'),
                  _buildBatterSelector(),
                  _buildResultFilter(),
                  _buildViewBar(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: _viewMode == _ViewMode.zone
                          ? ClipRect(child: _StrikeZoneChart(
                              pitches: _filtered, colors: _resultColors, isDark: _isDark))
                          : _buildTrajectoryContent(),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ─── view bar: [위치]/[궤적] toggle + legend ───────────────────────────────

  Widget _buildViewBar() {
    final filtered = _filtered;
    final physCount = filtered.where((p) => p['_phys'] != null).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          // toggle
          Container(
            decoration: BoxDecoration(
              color: _paper2,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: _line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _viewToggleBtn('위치', _ViewMode.zone),
                _viewToggleBtn('궤적', _ViewMode.traj),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          if (_viewMode == _ViewMode.zone)
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _legend('볼', _resultColors['ball']!),
                    const SizedBox(width: 8),
                    _legend('스트라이크', _resultColors['strike']!),
                    const SizedBox(width: 8),
                    _legend('헛스윙', _resultColors['swing']!),
                    const SizedBox(width: 8),
                    _legend('파울', _resultColors['foul']!),
                    const SizedBox(width: 8),
                    _legend('타격', _resultColors['hit']!),
                    const SizedBox(width: 8),
                    _legendDash('끝면 상한', Colors.orange),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: Text(
                '궤적 $physCount/${filtered.length}구',
                style: TextStyle(fontSize: Typo.caption, color: _sub),
              ),
            ),
          Text('· ${filtered.length}구',
              style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.medium, color: _sub)),
        ],
      ),
    );
  }

  Widget _viewToggleBtn(String label, _ViewMode mode) {
    final sel = _viewMode == mode;
    return GestureDetector(
      onTap: () => setState(() { _viewMode = mode; _selectedPitchIdx = null; }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? _ink : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.sm - 1),
        ),
        child: Text(label, style: TextStyle(
          fontSize: Typo.caption,
          fontWeight: sel ? Typo.bold : Typo.regular,
          color: sel ? _paper : _sub,
        )),
      ),
    );
  }

  // ─── trajectory tab content ───────────────────────────────────────────────

  Widget _buildTrajectoryContent() {
    final filtered = _filtered;
    final hasPhys = filtered.any((p) => p['_phys'] != null);
    if (!hasPhys) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.show_chart, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text('궤적 데이터 없음',
              style: TextStyle(fontSize: Typo.subtitle, fontWeight: Typo.medium, color: _ink)),
          const SizedBox(height: 6),
          Text('이 경기의 투구 물리 데이터가 없습니다',
              style: TextStyle(fontSize: Typo.small, color: _sub)),
        ],
      ));
    }
    return _TrajectoryView(
      pitches: filtered,
      colors: _resultColors,
      isDark: _isDark,
      selectedIdx: _selectedPitchIdx,
      onSelect: (i) => setState(() =>
          _selectedPitchIdx = _selectedPitchIdx == i ? null : i),
    );
  }

  // ─── selectors / chips ───────────────────────────────────────────────────

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 6, bottom: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(label, style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: _ink)),
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
                color: _ink.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
              child: Text(teamLabel, style: TextStyle(fontSize: Typo.caption, fontWeight: Typo.bold, color: _ink)),
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
                        _selectedPitchIdx = null;
                      }),
                      child: _chip(p, sel, _ink),
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            GestureDetector(
              onTap: () => setState(() { _selectedInning = null; _selectedBatter = null; _selectedPitchIdx = null; }),
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
                  onTap: () => setState(() { _selectedInning = ing; _selectedBatter = null; _selectedPitchIdx = null; }),
                  child: _chip('$ing회', sel, Colors.grey[700]!),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildBatterSelector() {
    final batters = _availableBatters;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            GestureDetector(
              onTap: () => setState(() { _selectedBatter = null; _selectedPitchIdx = null; }),
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
                  onTap: () => setState(() { _selectedBatter = b; _selectedPitchIdx = null; }),
                  child: _chip(b, sel, Colors.teal),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, Color color) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? color : _paper2,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: selected ? color : _line, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: Typo.caption,
          color: selected ? (color.computeLuminance() > 0.6 ? Colors.black : Colors.white) : _sub,
          fontWeight: selected ? Typo.bold : Typo.regular,
        ),
      ),
    );
  }

  Widget _buildResultFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _resultLabels.entries.map((e) {
            final sel = _filter == e.key;
            final color = e.key == 'all' ? _ink : (_resultColors[e.key] ?? Colors.grey);
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
    );
  }

  Widget _legend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: Space.xs),
        Text(label, style: TextStyle(fontSize: Typo.caption, color: _sub)),
      ],
    );
  }

  Widget _legendDash(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18, height: 10,
          child: CustomPaint(painter: _DashLinePainter(color)),
        ),
        const SizedBox(width: Space.xs),
        Text(label, style: TextStyle(fontSize: Typo.caption, color: _sub)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DashLinePainter
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// _StrikeZoneChart + _StrikeZonePainter  (Task 6: movement tail added)
// ─────────────────────────────────────────────────────────────────────────────

class _StrikeZoneChart extends StatelessWidget {
  final List<Map> pitches;
  final Map<String, Color> colors;
  final bool isDark;

  const _StrikeZoneChart({required this.pitches, required this.colors, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) => CustomPaint(
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: _StrikeZonePainter(pitches: pitches, colors: colors, isDark: isDark),
      ),
    );
  }
}

class _StrikeZonePainter extends CustomPainter {
  final List<Map> pitches;
  final Map<String, Color> colors;
  final bool isDark;

  _StrikeZonePainter({required this.pitches, required this.colors, required this.isDark});

  static const double xMin = -2.5;
  static const double xMax = 2.5;
  static const double zMin = 0.0;
  static const double zMax = 5.5;
  static const double plateHalfW = 8.5 / 12.0;
  static const double ballR      = 1.45 / 12.0;
  static const double absHalfW   = plateHalfW + ballR;
  static const double absDropFt  = 1.5 / 30.48;

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
    final topAbs = topSz;
    final botAbs = botSz;
    final topBack = topAbs - absDropFt;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = isDark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F5));

    final groundY = _toCanvas(0, 0, size).dy;
    canvas.drawLine(
      Offset(0, groundY), Offset(size.width, groundY),
      Paint()..color = Colors.brown.withValues(alpha: 0.3)..strokeWidth = 1,
    );

    final tl = _toCanvas(-absHalfW, topAbs, size);
    final br = _toCanvas(absHalfW, botAbs, size);
    final zoneRect = Rect.fromPoints(tl, br);

    canvas.drawRect(zoneRect, Paint()..color = Colors.red.withValues(alpha: 0.06));

    final yTopBack = _toCanvas(0, topBack, size).dy;
    canvas.drawRect(
      Rect.fromLTRB(tl.dx, tl.dy, br.dx, yTopBack),
      Paint()..color = Colors.orange.withValues(alpha: 0.13),
    );

    canvas.drawRect(zoneRect,
        Paint()..color = Colors.red.withValues(alpha: 0.5)..style = PaintingStyle.stroke..strokeWidth = 1.5);

    final dashPaint = Paint()
      ..color = Colors.orange.withValues(alpha: 0.75)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    _drawDashedHLine(canvas, tl.dx, br.dx, yTopBack, dashPaint);

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

    final plateCenter = _toCanvas(0, 0, size);
    final plateLeft  = _toCanvas(-plateHalfW, 0.15, size);
    final plateRight = _toCanvas(plateHalfW, 0.15, size);
    final plateTipY  = (plateCenter.dy + 8).clamp(0.0, size.height - 1);
    final platePath  = Path()
      ..moveTo(plateLeft.dx, plateLeft.dy)
      ..lineTo(plateRight.dx, plateRight.dy)
      ..lineTo(plateCenter.dx, plateTipY)
      ..close();
    canvas.drawPath(platePath, Paint()..color = isDark ? Colors.grey[700]! : Colors.grey[300]!);
    canvas.drawPath(platePath,
        Paint()..color = Colors.grey[500]!..style = PaintingStyle.stroke..strokeWidth = 1);

    canvas.drawLine(
      Offset(plateCenter.dx, 0), Offset(plateCenter.dx, size.height),
      Paint()..color = Colors.grey.withValues(alpha: 0.2)..strokeWidth = 0.5,
    );

    // ── draw pitches: movement tail (Task 6) then dot ──────────────────────
    for (final p in pitches) {
      final x = (p['x'] as num?)?.toDouble();
      final z = (p['z'] as num?)?.toDouble();
      if (x == null || z == null) continue;
      final result = p['result'] as String? ?? 'other';
      final color = colors[result] ?? colors['other']!;
      final pos = _toCanvas(x, z, size);

      if (pos.dx < -10 || pos.dx > size.width + 10 ||
          pos.dy < -10 || pos.dy > size.height + 10) {
        continue;
      }

      // dot (위치 뷰 = 궤적/무브먼트 미표시, 궤적은 [궤적] 탭 전용)
      canvas.drawCircle(pos, 5.5, Paint()..color = Colors.black.withValues(alpha: 0.15));
      canvas.drawCircle(pos, 5, Paint()..color = color.withValues(alpha: 0.85));
      canvas.drawCircle(pos, 5,
          Paint()..color = Colors.white.withValues(alpha: 0.5)..style = PaintingStyle.stroke..strokeWidth = 1);
    }

    final textStyle = TextStyle(fontSize: Typo.caption, fontWeight: Typo.medium,
        color: isDark ? Colors.grey[400] : Colors.grey[700]);
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
  bool shouldRepaint(_StrikeZonePainter old) => old.pitches != pitches || old.isDark != isDark;
}

// ─────────────────────────────────────────────────────────────────────────────
// Task 7: _TrajectoryView widget  (Task 8: 2D/3D sub-toggle added)
// ─────────────────────────────────────────────────────────────────────────────

class _TrajectoryView extends StatefulWidget {
  final List<Map> pitches;
  final Map<String, Color> colors;
  final bool isDark;
  final int? selectedIdx;
  final void Function(int) onSelect;

  const _TrajectoryView({
    required this.pitches,
    required this.colors,
    required this.isDark,
    required this.selectedIdx,
    required this.onSelect,
  });

  @override
  State<_TrajectoryView> createState() => _TrajectoryViewState();
}

class _TrajectoryViewState extends State<_TrajectoryView> {
  bool _show3D = false;

  TextStyle _labelStyle() => TextStyle(
    fontSize: Typo.caption, fontWeight: Typo.bold,
    color: widget.isDark ? const Color(0xFF9A9AA3) : const Color(0xFF9A9AA2),
  );

  @override
  Widget build(BuildContext context) {
    final physPitches = widget.pitches.where((p) => p['_phys'] != null).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 2D / 3D sub-toggle ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              _subToggle('2D', !_show3D),
              const SizedBox(width: 4),
              _subToggle('3D', _show3D),
            ],
          ),
        ),
        if (_show3D) ...[
          // ── 3D rotating view ─────────────────────────────────────────────
          Expanded(
            child: ClipRect(
              child: _Trajectory3DView(
                pitches: widget.pitches,
                colors: widget.colors,
                isDark: widget.isDark,
                selectedIdx: widget.selectedIdx,
              ),
            ),
          ),
        ] else ...[
          // ── side panel (y-distance × z-height) ───────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text('측면 (거리 × 높이)', style: _labelStyle()),
          ),
          Expanded(
            flex: 5,
            child: ClipRect(
              child: LayoutBuilder(
                builder: (_, c) => CustomPaint(
                  size: Size(c.maxWidth, c.maxHeight),
                  painter: _TrajectorySidePainter(
                    pitches: widget.pitches,
                    colors: widget.colors,
                    isDark: widget.isDark,
                    selectedIdx: widget.selectedIdx,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // ── top panel (y-distance × x-lateral) ───────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text('상단 (거리 × 좌우)', style: _labelStyle()),
          ),
          Expanded(
            flex: 4,
            child: ClipRect(
              child: LayoutBuilder(
                builder: (_, c) => CustomPaint(
                  size: Size(c.maxWidth, c.maxHeight),
                  painter: _TrajectoryTopPainter(
                    pitches: widget.pitches,
                    colors: widget.colors,
                    isDark: widget.isDark,
                    selectedIdx: widget.selectedIdx,
                  ),
                ),
              ),
            ),
          ),
        ],
        // ── pitch selector strip ─────────────────────────────────────────────
        if (physPitches.isNotEmpty)
          SizedBox(
            height: 36,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: widget.pitches.length,
              itemBuilder: (_, i) {
                final p = widget.pitches[i];
                if (p['_phys'] == null) return const SizedBox.shrink();
                final result = p['result'] as String? ?? 'other';
                final color = widget.colors[result] ?? widget.colors['other']!;
                final sel = widget.selectedIdx == i;
                return GestureDetector(
                  onTap: () => widget.onSelect(i),
                  child: Container(
                    margin: const EdgeInsets.only(right: 4),
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: sel ? color : color.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                      border: sel ? Border.all(color: color, width: 2) : null,
                    ),
                    child: Center(
                      child: Text('${i + 1}',
                        style: TextStyle(
                          fontSize: Typo.micro,
                          color: sel ? Colors.white : color,
                          fontWeight: Typo.bold,
                        )),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _subToggle(String label, bool active) {
    final isDark = widget.isDark;
    return GestureDetector(
      onTap: () => setState(() => _show3D = label == '3D'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.10))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.xs),
          border: Border.all(
            color: active
                ? (isDark
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.2))
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: Typo.caption,
            fontWeight: active ? Typo.bold : Typo.regular,
            color: active
                ? (isDark ? Colors.white : Colors.black)
                : (isDark ? const Color(0xFF9A9AA3) : const Color(0xFF9A9AA2)),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Task 7: _TrajectorySidePainter  (canvas-x = distance y, canvas-y = height z)
// ─────────────────────────────────────────────────────────────────────────────

class _TrajectorySidePainter extends CustomPainter {
  final List<Map> pitches;
  final Map<String, Color> colors;
  final bool isDark;
  final int? selectedIdx;

  _TrajectorySidePainter({
    required this.pitches,
    required this.colors,
    required this.isDark,
    required this.selectedIdx,
  });

  static const double _yRelease = 55.0;
  static const double _yPlate   = 0.0;
  static const double _zMin     = 0.0;
  static const double _zMax     = 7.0;

  // release at canvas left, plate at canvas right
  Offset _tc(double worldY, double worldZ, Size size) {
    final cx = (_yRelease - worldY) / (_yRelease - _yPlate) * size.width;
    final cy = (_zMax - worldZ) / (_zMax - _zMin) * size.height;
    return Offset(cx, cy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = isDark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F5));

    // ground line
    final groundY = _tc(0, 0, size).dy;
    canvas.drawLine(Offset(0, groundY), Offset(size.width, groundY),
        Paint()..color = Colors.brown.withValues(alpha: 0.3)..strokeWidth = 1);

    // strike zone band at plate edge
    double topSz = 3.3, botSz = 1.6;
    final tops = pitches.where((p) => p['top_sz'] != null).map((p) => (p['top_sz'] as num).toDouble()).toList();
    final bots = pitches.where((p) => p['bot_sz'] != null).map((p) => (p['bot_sz'] as num).toDouble()).toList();
    if (tops.isNotEmpty) topSz = tops.reduce((a, b) => a + b) / tops.length;
    if (bots.isNotEmpty) botSz = bots.reduce((a, b) => a + b) / bots.length;

    final szTop = _tc(_yPlate, topSz, size);
    final szBot = _tc(_yPlate, botSz, size);
    final szX   = size.width - 8;
    canvas.drawRect(
      Rect.fromLTRB(szX, szTop.dy, size.width, szBot.dy),
      Paint()..color = Colors.red.withValues(alpha: 0.15),
    );
    canvas.drawRect(
      Rect.fromLTRB(szX, szTop.dy, size.width, szBot.dy),
      Paint()..color = Colors.red.withValues(alpha: 0.5)..style = PaintingStyle.stroke..strokeWidth = 1.2,
    );

    // grid lines + labels
    final lblStyle = TextStyle(
      fontSize: Typo.micro,
      color: isDark ? Colors.grey[500] : Colors.grey[600],
    );
    for (final zv in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]) {
      if (zv > _zMax) break;
      final oy = _tc(0, zv, size).dy;
      canvas.drawLine(Offset(0, oy), Offset(size.width, oy),
          Paint()..color = Colors.grey.withValues(alpha: 0.12)..strokeWidth = 0.5);
      final tp = TextPainter(
        text: TextSpan(text: '${zv.toInt()}ft', style: lblStyle),
        textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(2, oy - 9));
    }
    for (final yv in [10.0, 20.0, 30.0, 40.0, 50.0]) {
      final ox = _tc(yv, 0, size).dx;
      canvas.drawLine(Offset(ox, 0), Offset(ox, size.height),
          Paint()..color = Colors.grey.withValues(alpha: 0.12)..strokeWidth = 0.5);
      final tp = TextPainter(
        text: TextSpan(text: '${yv.toInt()}ft', style: lblStyle),
        textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(ox + 2, size.height - 12));
    }

    // trajectories
    for (int i = 0; i < pitches.length; i++) {
      final p = pitches[i];
      final phys = p['_phys'] as PitchPhysics?;
      if (phys == null) continue;
      final result = p['result'] as String? ?? 'other';
      final color = colors[result] ?? colors['other']!;
      final isSel   = selectedIdx == i;
      final isOther = selectedIdx != null && !isSel;
      final alpha   = isOther ? 0.18 : (isSel ? 1.0 : 0.55);
      final strokeW = isSel ? 2.5 : 1.5;

      final traj = pitchTrajectory(phys, samples: 24);
      if (traj.length < 2) continue;
      final path = Path();
      bool first = true;
      for (final v in traj) {
        final o = _tc(v.y, v.z, size);
        if (first) { path.moveTo(o.dx, o.dy); first = false; }
        else { path.lineTo(o.dx, o.dy); }
      }
      canvas.drawPath(path, Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = strokeW
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);

      // release dot
      if (!isOther) {
        final rel = _tc(traj.first.y, traj.first.z, size);
        canvas.drawCircle(rel, isSel ? 4.5 : 3.0,
            Paint()..color = color.withValues(alpha: alpha));
      }
    }
  }

  @override
  bool shouldRepaint(_TrajectorySidePainter old) =>
      old.pitches != pitches || old.isDark != isDark || old.selectedIdx != selectedIdx;
}

// ─────────────────────────────────────────────────────────────────────────────
// Task 7: _TrajectoryTopPainter  (canvas-x = distance y, canvas-y = lateral x)
// ─────────────────────────────────────────────────────────────────────────────

class _TrajectoryTopPainter extends CustomPainter {
  final List<Map> pitches;
  final Map<String, Color> colors;
  final bool isDark;
  final int? selectedIdx;

  _TrajectoryTopPainter({
    required this.pitches,
    required this.colors,
    required this.isDark,
    required this.selectedIdx,
  });

  static const double _yRelease = 55.0;
  static const double _yPlate   = 0.0;
  static const double _xRange   = 3.0;   // ±3 ft lateral

  // release at canvas left, plate at canvas right
  // positive x (pitcher's right / catcher's right) at canvas top
  Offset _tc(double worldY, double worldX, Size size) {
    final cx = (_yRelease - worldY) / (_yRelease - _yPlate) * size.width;
    final cy = (_xRange - worldX) / (_xRange * 2) * size.height;
    return Offset(cx, cy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = isDark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F5));

    // center line (x = 0)
    final centerY = _tc(0, 0, size).dy;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY),
        Paint()..color = Colors.grey.withValues(alpha: 0.3)..strokeWidth = 0.8);

    // ABS 스트라이크존 lateral 밴드 (plate 반폭 + 공 반지름 = 위치 뷰 absHalfW)
    const absHalfW = 8.5 / 12.0 + 1.45 / 12.0;
    final plateTop = _tc(_yPlate, absHalfW, size);
    final plateBot = _tc(_yPlate, -absHalfW, size);
    final szX = size.width - 8;
    canvas.drawRect(
      Rect.fromLTRB(szX, plateTop.dy, size.width, plateBot.dy),
      Paint()..color = Colors.blue.withValues(alpha: 0.15),
    );
    canvas.drawRect(
      Rect.fromLTRB(szX, plateTop.dy, size.width, plateBot.dy),
      Paint()..color = Colors.blue.withValues(alpha: 0.4)..style = PaintingStyle.stroke..strokeWidth = 1.2,
    );

    final lblStyle = TextStyle(
      fontSize: Typo.micro,
      color: isDark ? Colors.grey[500] : Colors.grey[600],
    );
    for (final xv in [-2.0, -1.0, 1.0, 2.0]) {
      final oy = _tc(0, xv, size).dy;
      canvas.drawLine(Offset(0, oy), Offset(size.width, oy),
          Paint()..color = Colors.grey.withValues(alpha: 0.12)..strokeWidth = 0.5);
      final lbl = '${xv > 0 ? '+' : ''}${xv.toInt()}ft';
      final tp = TextPainter(
        text: TextSpan(text: lbl, style: lblStyle),
        textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(2, oy - 9));
    }

    // distance labels
    for (final yv in [10.0, 20.0, 30.0, 40.0, 50.0]) {
      final ox = _tc(yv, 0, size).dx;
      canvas.drawLine(Offset(ox, 0), Offset(ox, size.height),
          Paint()..color = Colors.grey.withValues(alpha: 0.12)..strokeWidth = 0.5);
      final tp = TextPainter(
        text: TextSpan(text: '${yv.toInt()}ft', style: lblStyle),
        textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(ox + 2, size.height - 12));
    }

    // trajectories
    for (int i = 0; i < pitches.length; i++) {
      final p = pitches[i];
      final phys = p['_phys'] as PitchPhysics?;
      if (phys == null) continue;
      final result = p['result'] as String? ?? 'other';
      final color = colors[result] ?? colors['other']!;
      final isSel   = selectedIdx == i;
      final isOther = selectedIdx != null && !isSel;
      final alpha   = isOther ? 0.18 : (isSel ? 1.0 : 0.55);
      final strokeW = isSel ? 2.5 : 1.5;

      final traj = pitchTrajectory(phys, samples: 24);
      if (traj.length < 2) continue;
      final path = Path();
      bool first = true;
      for (final v in traj) {
        final o = _tc(v.y, v.x, size);
        if (first) { path.moveTo(o.dx, o.dy); first = false; }
        else { path.lineTo(o.dx, o.dy); }
      }
      canvas.drawPath(path, Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = strokeW
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);

      if (!isOther) {
        final rel = _tc(traj.first.y, traj.first.x, size);
        canvas.drawCircle(rel, isSel ? 4.5 : 3.0,
            Paint()..color = color.withValues(alpha: alpha));
      }
    }

    // axis label
    final axisLbl = TextPainter(
      text: TextSpan(text: '투수 → 포수', style: lblStyle),
      textDirection: TextDirection.ltr)..layout();
    axisLbl.paint(canvas, Offset(size.width / 2 - axisLbl.width / 2, size.height - 12));
  }

  @override
  bool shouldRepaint(_TrajectoryTopPainter old) =>
      old.pitches != pitches || old.isDark != isDark || old.selectedIdx != selectedIdx;
}

// ─────────────────────────────────────────────────────────────────────────────
// Task 8: _Trajectory3DView  — drag-to-rotate 3D perspective
// ─────────────────────────────────────────────────────────────────────────────

class _Trajectory3DView extends StatefulWidget {
  final List<Map> pitches;
  final Map<String, Color> colors;
  final bool isDark;
  final int? selectedIdx;

  const _Trajectory3DView({
    required this.pitches,
    required this.colors,
    required this.isDark,
    required this.selectedIdx,
  });

  @override
  State<_Trajectory3DView> createState() => _Trajectory3DViewState();
}

class _Trajectory3DViewState extends State<_Trajectory3DView> {
  // Initial 3/4 view: pitcher slightly right, looking from above-behind catcher
  double _yaw   = 0.40;   // ~23° — scene rotated laterally
  double _pitch = 0.28;   // ~16° — tilt down from above

  void _onPan(DragUpdateDetails d) {
    setState(() {
      _yaw = (_yaw + d.delta.dx * 0.012)
          .clamp(-math.pi, math.pi);
      _pitch = (_pitch - d.delta.dy * 0.012)
          .clamp(-math.pi / 2 + 0.05, math.pi / 2 - 0.05);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: _onPan,
      child: LayoutBuilder(
        builder: (_, c) => CustomPaint(
          size: Size(c.maxWidth, c.maxHeight),
          painter: _Trajectory3DPainter(
            pitches: widget.pitches,
            colors: widget.colors,
            isDark: widget.isDark,
            selectedIdx: widget.selectedIdx,
            yaw: _yaw,
            pitch: _pitch,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Task 8: _Trajectory3DPainter
//
// Coordinate system (world, ft):
//   y = distance from plate (0=plate, 55=release)
//   x = lateral (positive = catcher's right)
//   z = height (positive = up)
//
// Projection pipeline:
//   1. Translate to scene centre (0, 27.5, 3.5)
//   2. Yaw  (θ) rotation around world-up  (z) axis
//   3. Pitch (φ) rotation around scene-lateral (x) axis
//   4. Camera pull-back: camera sits 55 ft "behind" scene centre
//   5. Perspective divide
// ─────────────────────────────────────────────────────────────────────────────

class _Trajectory3DPainter extends CustomPainter {
  final List<Map> pitches;
  final Map<String, Color> colors;
  final bool isDark;
  final int? selectedIdx;
  final double yaw, pitch;

  _Trajectory3DPainter({
    required this.pitches,
    required this.colors,
    required this.isDark,
    required this.selectedIdx,
    required this.yaw,
    required this.pitch,
  });

  // Scene centre
  static const double _scCx = 0.0;
  static const double _scCy = 27.5;
  static const double _scCz = 3.5;
  // Camera sits this many scene-units behind the scene centre along the
  // rotated depth axis.  55 ft keeps all trajectory points in front.
  static const double _camBack = 55.0;

  /// Project world-space (wx, wy, wz) → canvas Offset.
  /// Returns null when the point is behind the camera.
  Offset? _proj(double wx, double wy, double wz, Size size, double scale) {
    // 1. Translate to scene centre
    final lx = wx - _scCx;
    final ly = wy - _scCy;
    final lz = wz - _scCz;

    // 2. Yaw rotation around Z (scene-up) axis
    final cosY = math.cos(yaw), sinY = math.sin(yaw);
    final rx = lx * cosY + ly * sinY;
    final ry = -lx * sinY + ly * cosY;

    // 3. Pitch rotation around X (scene-lateral) axis
    //    positive pitch = tilt scene forward → view from above
    final cosP = math.cos(pitch), sinP = math.sin(pitch);
    final px      = rx;
    final pyDepth = ry * cosP + lz * sinP;   // depth in camera frame
    final pzUp    = -ry * sinP + lz * cosP;  // vertical in camera frame

    // 4. Camera pull-back: camera at pyDepth = -_camBack
    final depth = pyDepth + _camBack;
    if (depth < 0.1) return null;

    // 5. Perspective divide
    final s = _camBack / depth * scale;
    return Offset(
      size.width  / 2 + px   * s,
      size.height / 2 - pzUp * s,  // canvas-y inverted
    );
  }

  void _drawSeg(Canvas c, Offset? a, Offset? b, Paint p) {
    if (a != null && b != null) c.drawLine(a, b, p);
  }

  void _drawPoly(Canvas c, List<Offset?> pts, Paint p, {bool close = false}) {
    Offset? prev;
    for (final pt in pts) {
      if (pt != null && prev != null) c.drawLine(prev, pt, p);
      if (pt != null) prev = pt;
    }
    if (close && prev != null && pts.first != null) {
      c.drawLine(prev, pts.first!, p);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = isDark ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F5));

    // Scale: 1 ft ≈ 1/10 of the canvas shortest side
    final scale = size.shortestSide / 10.0;

    // ── Average strike zone dimensions ────────────────────────────────────────
    double topSz = 3.3, botSz = 1.6;
    final tops = pitches.where((p) => p['top_sz'] != null)
        .map((p) => (p['top_sz'] as num).toDouble()).toList();
    final bots = pitches.where((p) => p['bot_sz'] != null)
        .map((p) => (p['bot_sz'] as num).toDouble()).toList();
    if (tops.isNotEmpty) topSz = tops.reduce((a, b) => a + b) / tops.length;
    if (bots.isNotEmpty) botSz = bots.reduce((a, b) => a + b) / bots.length;

    const pHW = 8.5 / 12.0; // plate half-width (ft) — 홈플레이트/그리드용
    // ABS 스트라이크존 반폭 = 플레이트 반폭 + 공 반지름 (위치 뷰 _StrikeZonePainter.absHalfW와 동일)
    const absHW = pHW + 1.45 / 12.0;

    // ── Ground guide grid (z = 0) ─────────────────────────────────────────────
    final gridP = Paint()
      ..color = Colors.grey.withValues(alpha: 0.14)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    // Longitudinal lines (along y)
    for (final xv in [-pHW, 0.0, pHW]) {
      _drawSeg(canvas,
        _proj(xv, 55.0, 0.0, size, scale),
        _proj(xv,  0.0, 0.0, size, scale),
        gridP,
      );
    }
    // Distance tick lines (across x)
    for (final yv in [0.0, 10.0, 20.0, 30.0, 40.0, 50.0]) {
      _drawSeg(canvas,
        _proj(-pHW, yv, 0.0, size, scale),
        _proj( pHW, yv, 0.0, size, scale),
        gridP,
      );
    }

    // ── Strike zone rectangle at plate (y = 0) ────────────────────────────────
    final zonePts = [
      _proj(-absHW, 0.0, topSz, size, scale),  // TL
      _proj( absHW, 0.0, topSz, size, scale),  // TR
      _proj( absHW, 0.0, botSz, size, scale),  // BR
      _proj(-absHW, 0.0, botSz, size, scale),  // BL
    ];
    _drawPoly(canvas, zonePts,
        Paint()..color = Colors.red.withValues(alpha: 0.06),
        close: true);
    _drawPoly(canvas, zonePts,
        Paint()
          ..color = Colors.red.withValues(alpha: 0.55)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke,
        close: true);

    // ── Home plate pentagon (flat on ground) ──────────────────────────────────
    // Standard plate: 17" wide front, tip toward catcher (−y direction)
    const plateSideY = -0.25; // where angled sides start
    const plateTipY  = -0.55; // pointed back toward catcher
    final platePts = [
      _proj(-pHW, 0.0,       0.0, size, scale), // front-left
      _proj( pHW, 0.0,       0.0, size, scale), // front-right
      _proj( pHW, plateSideY, 0.0, size, scale), // back-right
      _proj( 0.0, plateTipY,  0.0, size, scale), // tip
      _proj(-pHW, plateSideY, 0.0, size, scale), // back-left
    ];
    final plateColor = isDark ? Colors.grey[600]! : Colors.grey[400]!;
    _drawPoly(canvas, platePts,
        Paint()..color = plateColor.withValues(alpha: 0.5),
        close: true);
    _drawPoly(canvas, platePts,
        Paint()
          ..color = Colors.grey.withValues(alpha: 0.7)
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke,
        close: true);

    // ── Trajectory polylines ─────────────────────────────────────────────────
    for (int i = 0; i < pitches.length; i++) {
      final p = pitches[i];
      final phys = p['_phys'] as PitchPhysics?;
      if (phys == null) continue;

      final result = p['result'] as String? ?? 'other';
      final color  = colors[result] ?? colors['other']!;
      final isSel   = selectedIdx == i;
      final isOther = selectedIdx != null && !isSel;
      final alpha   = isOther ? 0.13 : (isSel ? 1.0 : 0.55);
      final strokeW = isSel ? 2.8 : 1.5;

      final traj = pitchTrajectory(phys, samples: 24);
      if (traj.length < 2) continue;

      final pts3d = traj
          .map((v) => _proj(v.x, v.y, v.z, size, scale))
          .toList();

      // Draw polyline
      final path = Path();
      bool first = true;
      for (final pt in pts3d) {
        if (pt == null) continue;
        if (first) { path.moveTo(pt.dx, pt.dy); first = false; }
        else        { path.lineTo(pt.dx, pt.dy); }
      }
      canvas.drawPath(path, Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = strokeW
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);

      if (!isOther) {
        // Release dot (start of path, near pitcher)
        Offset? rel;
        for (final pt in pts3d) { if (pt != null) { rel = pt; break; } }
        if (rel != null) {
          canvas.drawCircle(rel, isSel ? 4.5 : 3.0,
              Paint()..color = color.withValues(alpha: alpha));
        }

        // Plate-arrival marker (solid + white ring)
        Offset? plat;
        for (final pt in pts3d.reversed) { if (pt != null) { plat = pt; break; } }
        if (plat != null) {
          canvas.drawCircle(plat, isSel ? 5.5 : 3.5,
              Paint()..color = color.withValues(alpha: alpha));
          canvas.drawCircle(plat, isSel ? 5.5 : 3.5,
              Paint()
                ..color = Colors.white.withValues(alpha: 0.8)
                ..style = PaintingStyle.stroke
                ..strokeWidth = isSel ? 2.0 : 1.2);
        }
      }
    }

    // ── Drag hint ─────────────────────────────────────────────────────────────
    final hintStyle = TextStyle(
      fontSize: Typo.micro,
      color: Colors.grey[500]!.withValues(alpha: 0.65),
    );
    final tp = TextPainter(
      text: TextSpan(text: '드래그하여 회전', style: hintStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        Offset(size.width - tp.width - 4, size.height - tp.height - 4));
  }

  @override
  bool shouldRepaint(_Trajectory3DPainter old) =>
      old.pitches     != pitches     ||
      old.isDark      != isDark      ||
      old.selectedIdx != selectedIdx ||
      old.yaw         != yaw         ||
      old.pitch       != pitch;
}
