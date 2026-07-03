import 'package:flutter_test/flutter_test.dart';
import 'package:playball/utils/pitch_trajectory.dart';

// 대략 직구: release 55ft, 145km/h, 약간 라이즈 무브먼트
const _p = PitchPhysics(
  x0: 0.0, vx0: 0.0, ax: 0.0,
  y0: 50.0, vy0: -130.0, ay: 25.0,
  z0: 6.0, vz0: -5.0, az: -15.0, crossY: 1.417,
);

void main() {
  test('trajectory starts at release, ends at plate', () {
    final t = pitchTrajectory(_p);
    expect(t.length, greaterThan(2));
    // 시작 = release 근처(y≈y0=50)
    expect((t.first.y - 50.0).abs() < 0.5, isTrue);
    // 끝 = plate(y≈crossY=1.417)
    expect((t.last.y - 1.417).abs() < 0.5, isTrue);
  });

  test('trajectory z decreases toward plate (gravity)', () {
    final t = pitchTrajectory(_p);
    expect(t.last.z < t.first.z, isTrue);   // 홈 도달 시 낮아짐
  });

  test('fromJson null-safe', () {
    expect(PitchPhysics.fromJson(null), isNull);
    expect(PitchPhysics.fromJson({'x0': null}), isNull);
    final p = PitchPhysics.fromJson({
      'x0': 0.0,'vx0':0.0,'ax':0.0,'y0':50.0,'vy0':-130.0,'ay':25.0,
      'z0':6.0,'vz0':-5.0,'az':-15.0,'cross_y':1.417});
    expect(p, isNotNull);
  });

  test('movement returns finite pfx', () {
    final (px, pz) = pitchMovement(_p);
    expect(px.isFinite && pz.isFinite, isTrue);
  });
}
