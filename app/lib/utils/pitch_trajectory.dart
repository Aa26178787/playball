import 'dart:math' as math;

class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);
}

class PitchPhysics {
  final double x0, vx0, ax, y0, vy0, ay, z0, vz0, az, crossY;
  const PitchPhysics({
    required this.x0, required this.vx0, required this.ax,
    required this.y0, required this.vy0, required this.ay,
    required this.z0, required this.vz0, required this.az,
    required this.crossY,
  });
  static PitchPhysics? fromJson(Map? j) {
    if (j == null) return null;
    double? d(String k) => (j[k] is num) ? (j[k] as num).toDouble() : null;
    final v = [d('x0'), d('vx0'), d('ax'), d('y0'), d('vy0'), d('ay'),
              d('z0'), d('vz0'), d('az'), d('cross_y')];
    if (v.any((e) => e == null)) return null;
    return PitchPhysics(
      x0: v[0]!, vx0: v[1]!, ax: v[2]!, y0: v[3]!, vy0: v[4]!, ay: v[5]!,
      z0: v[6]!, vz0: v[7]!, az: v[8]!, crossY: v[9]!);
  }
}

double _pos(double p0, double v0, double a, double t) => p0 + v0 * t + 0.5 * a * t * t;

// y(t)=crossY 되는 t (양근 중 최소 양수)
double _tPlate(PitchPhysics p) {
  final a = 0.5 * p.ay, b = p.vy0, c = p.y0 - p.crossY;
  if (a.abs() < 1e-9) return (b.abs() < 1e-9) ? 0.0 : (-c / b);
  final disc = b * b - 4 * a * c;
  if (disc < 0) return 0.0;
  final s = math.sqrt(disc);
  final t1 = (-b - s) / (2 * a), t2 = (-b + s) / (2 * a);
  final cands = [t1, t2].where((t) => t > 1e-6).toList()..sort();
  return cands.isEmpty ? 0.0 : cands.first;
}

List<Vec3> pitchTrajectory(PitchPhysics p, {int samples = 24}) {
  final tp = _tPlate(p);
  if (tp <= 0) return const [];
  final out = <Vec3>[];
  for (int i = 0; i <= samples; i++) {
    final t = tp * i / samples;
    out.add(Vec3(_pos(p.x0, p.vx0, p.ax, t), _pos(p.y0, p.vy0, p.ay, t), _pos(p.z0, p.vz0, p.az, t)));
  }
  return out;
}

// 무브먼트(inch) = 실제 plate 도달 - 무회전(중력만: ax=0, az=-32.174) 기준
(double, double) pitchMovement(PitchPhysics p) {
  final tp = _tPlate(p);
  if (tp <= 0) return (0, 0);
  final actX = _pos(p.x0, p.vx0, p.ax, tp), actZ = _pos(p.z0, p.vz0, p.az, tp);
  final refX = _pos(p.x0, p.vx0, 0.0, tp), refZ = _pos(p.z0, p.vz0, -32.174, tp);
  return ((actX - refX) * 12.0, (actZ - refZ) * 12.0);
}
