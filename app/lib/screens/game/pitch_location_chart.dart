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

      // Task 6: movement tail for pitches with physics
      final phys = p['_phys'] as PitchPhysics?;
      if (phys != null) {
        final (pfxX, pfxZ) = pitchMovement(phys);
        // spinless reference location (ft) = actual minus the movement break
        final refX = x - pfxX / 12.0;
        final refZ = z - pfxZ / 12.0;
        final refPos = _toCanvas(refX, refZ, size);

        // tail line: reference → actual
        canvas.drawLine(refPos, pos,
          Paint()
            ..color = color.withValues(alpha: 0.6)
            ..strokeWidth = 1.8
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round);

        // arrowhead at actual dot
        final dx = pos.dx - refPos.dx;
        final dy = pos.dy - refPos.dy;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len > 2) {
          final ux = dx / len, uy = dy / len;
          // backward unit vector
          final bx = -ux, by = -uy;
          const arrowLen = 5.0;
          final cosA = math.cos(0.45);
          final sinA = math.sin(0.45);
          final ah1 = Offset(
            pos.dx + arrowLen * (bx * cosA - by * sinA),
            pos.dy + arrowLen * (bx * sinA + by * cosA),
          );
          final ah2 = Offset(
            pos.dx + arrowLen * (bx * cosA + by * sinA),
            pos.dy + arrowLen * (-bx * sinA + by * cosA),
          );
          final arrowPaint = Paint()
            ..color = color.withValues(alpha: 0.6)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(pos, ah1, arrowPaint);
          canvas.drawLine(pos, ah2, arrowPaint);
        }
      }

      // dot (always)
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
// Task 7: _TrajectoryView widget
// ─────────────────────────────────────────────────────────────────────────────

class _TrajectoryView extends StatelessWidget {
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

  TextStyle _labelStyle(bool isDark) => TextStyle(
    fontSize: Typo.caption, fontWeight: Typo.bold,
    color: isDark ? const Color(0xFF9A9AA3) : const Color(0xFF9A9AA2),
  );

  @override
  Widget build(BuildContext context) {
    final physPitches = pitches.where((p) => p['_phys'] != null).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── side panel (y-distance × z-height) ───────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text('측면 (거리 × 높이)', style: _labelStyle(isDark)),
        ),
        Expanded(
          flex: 5,
          child: ClipRect(
            child: LayoutBuilder(
              builder: (_, c) => CustomPaint(
                size: Size(c.maxWidth, c.maxHeight),
                painter: _TrajectorySidePainter(
                  pitches: pitches,
                  colors: colors,
                  isDark: isDark,
                  selectedIdx: selectedIdx,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // ── top panel (y-distance × x-lateral) ───────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text('상단 (거리 × 좌우)', style: _labelStyle(isDark)),
        ),
        Expanded(
          flex: 4,
          child: ClipRect(
            child: LayoutBuilder(
              builder: (_, c) => CustomPaint(
                size: Size(c.maxWidth, c.maxHeight),
                painter: _TrajectoryTopPainter(
                  pitches: pitches,
                  colors: colors,
                  isDark: isDark,
                  selectedIdx: selectedIdx,
                ),
              ),
            ),
          ),
        ),
        // ── pitch selector strip ──────────────────────────────────────────
        if (physPitches.isNotEmpty)
          SizedBox(
            height: 36,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: pitches.length,
              itemBuilder: (_, i) {
                final p = pitches[i];
                if (p['_phys'] == null) return const SizedBox.shrink();
                final result = p['result'] as String? ?? 'other';
                final color = colors[result] ?? colors['other']!;
                final sel = selectedIdx == i;
                return GestureDetector(
                  onTap: () => onSelect(i),
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

    // plate width band at plate edge
    const plateHalfW = 8.5 / 12.0;
    final plateTop = _tc(_yPlate, plateHalfW, size);
    final plateBot = _tc(_yPlate, -plateHalfW, size);
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
