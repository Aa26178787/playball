// share_cards.dart — 공유용 카드 위젯 (메가C). showShareCardDialog와 함께 사용.
// 캡처 대상이라 테마 무관 고정 디자인 (다크/라이트 동일 출력).
import 'package:flutter/material.dart';
import '../utils/team_theme.dart';
import '../utils/web_image.dart';

const _cardW = 330.0;
const _ink = Color(0xFF111113);
const _sub = Color(0xFF707078);
const _line = Color(0xFFE8E8EC);

/// 직관 기록 공유 카드
class VisitShareCard extends StatelessWidget {
  final String homeCode, awayCode;
  final String homeName, awayName;
  final String result; // win / loss / draw
  final String dateStr; // 2026년 6월 12일
  final String stadium;
  final String memo;
  const VisitShareCard({
    super.key,
    required this.homeCode, required this.awayCode,
    required this.homeName, required this.awayName,
    required this.result, required this.dateStr,
    required this.stadium, this.memo = '',
  });

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (result) {
      'win' => ('승리한 날', const Color(0xFF2563EB)),
      'loss' => ('아쉬운 날', const Color(0xFFDC2626)),
      _ => ('무승부', const Color(0xFF6B6B73)),
    };
    return Container(
      width: _cardW,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('🏟️ 직관 — $label',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
        ),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Column(children: [
            TeamLogo(teamCode: awayCode, size: 56),
            const SizedBox(height: 6),
            Text(awayName,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _ink)),
          ]),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 22),
            child: Text('VS',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: _sub)),
          ),
          Column(children: [
            TeamLogo(teamCode: homeCode, size: 56),
            const SizedBox(height: 6),
            Text(homeName,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _ink)),
          ]),
        ]),
        const SizedBox(height: 16),
        Text('$dateStr · $stadium',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _sub)),
        if (memo.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('"$memo"',
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: _ink, height: 1.5)),
          ),
        ],
        const SizedBox(height: 16),
        const _Watermark(),
      ]),
    );
  }
}

/// 선수 카드 공유
class PlayerShareCard extends StatelessWidget {
  final String name;
  final String teamCode;
  final String teamName;
  final String? profileImage;
  final String position; // 투수/내야수 등
  final String number; // 등번호
  final List<(String, String)> stats; // [(라벨, 값)] 4개 권장
  const PlayerShareCard({
    super.key,
    required this.name, required this.teamCode, required this.teamName,
    this.profileImage, this.position = '', this.number = '',
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    final color = teamColor(teamCode);
    return Container(
      width: _cardW,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // 팀컬러 헤더
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, Color.lerp(color, Colors.black, 0.25)!],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Row(children: [
            netCircleAvatar(
              radius: 34,
              url: profileImage ?? '',
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              child: (profileImage == null || profileImage!.isEmpty)
                  ? const Icon(Icons.person, size: 34, color: Colors.white70)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 3),
                Text(
                  [teamName, if (number.isNotEmpty) 'No.$number', position]
                      .where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.85)),
                ),
              ]),
            ),
            TeamLogo(teamCode: teamCode, size: 40),
          ]),
        ),
        // 스탯 그리드
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(children: [
            Row(
              children: stats.take(4).map((s) => Expanded(
                child: Column(children: [
                  Text(s.$2,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900, color: _ink)),
                  const SizedBox(height: 2),
                  Text(s.$1, style: const TextStyle(fontSize: 10.5, color: _sub)),
                ]),
              )).toList(),
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: _line),
            const SizedBox(height: 12),
            const _Watermark(),
          ]),
        ),
      ]),
    );
  }
}

class _Watermark extends StatelessWidget {
  const _Watermark();
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
      Text('⚾', style: TextStyle(fontSize: 12)),
      SizedBox(width: 5),
      Text('PlayBall — KBO 라이브',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _sub,
              letterSpacing: 0.2)),
    ]);
  }
}
