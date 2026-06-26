/// 서버 타임스탬프 → 로컬(KST) DateTime 변환.
///
/// 서버는 전부 UTC로 동작한다. 그런데 created_at / published_at가
/// 타임존 표기 없는 naive 문자열(예: "2026-06-26T10:08:23.613583")로 직렬화되면
/// Dart의 DateTime.parse는 이를 *로컬 시각*으로 해석한다.
/// → UTC 값을 KST로 잘못 읽어 정확히 +9시간 오차가 생긴다
///   (알림함 "방금" 알림이 "9시간 전"으로 표시된 버그).
///
/// 규칙: 문자열에 타임존 표기(Z / +09:00 등)가 있으면 그대로 존중하고,
/// 없으면(naive) UTC로 재해석한 뒤 toLocal()으로 변환한다.
/// 서버가 UTC로 동작하므로 naive=UTC 가정이 항상 성립한다.
DateTime parseServerTime(String s) {
  final hasTz = s.endsWith('Z') ||
      s.endsWith('z') ||
      RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  final dt = DateTime.parse(s);
  if (hasTz || dt.isUtc) return dt.toLocal();
  return DateTime.utc(dt.year, dt.month, dt.day, dt.hour, dt.minute,
          dt.second, dt.millisecond, dt.microsecond)
      .toLocal();
}
