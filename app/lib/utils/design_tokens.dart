import 'package:flutter/material.dart';

/// 디자인 토큰 — typography + semantic color + spacing
/// 인라인 fontSize/color 대신 사용
///
/// paper: 카드/패널 배경 (가장 안쪽 layer)
/// paper2: 카드 안 약간 진한 sub-layer (날씨 chip, 핀 캡슐 등)
/// line: 카드 외곽선 (1px)
/// line2: 강조 외곽선 (2px) 또는 separator
/// ink/ink2/ink3/sub: 텍스트 4단계 (진함 → 흐림)
class Typo {
  // ── size scale (px) — 데이터 밀집 UI 기준 단계. 인라인 fontSize 리터럴 대신 사용.
  // 점진 마이그레이션: off-scale 리터럴 → 가장 가까운 토큰. **화면 단위로 육안검증과 함께** 전환.
  //   off-scale 매핑:  8→micro(9) · 15→subtitle(14) · 17→title(16) · 19→lg(18) · 22→h2(20) · 26→h1(24)
  //   실사용 빈도(2026-06): 11(176)·12(120)·13(112)·10(85)·14(54)·9(34)·16(31) = 소형 단계 다층(의도)
  static const double micro    = 10;  // dot, mini badge (06-17 가시성: 9→10)
  static const double mini     = 11;  // 타임스탬프·카운트 등 최소 메타 (06-17: 10→11)
  static const double caption  = 11;  // chip, label
  static const double small    = 12;  // 보조 정보
  static const double body     = 13;  // 본문, 일반 정보
  static const double subtitle = 14;  // 부제 / 강조 정보
  static const double title    = 16;  // 카드 제목
  static const double lg       = 18;  // 큰 값 / 소제목
  static const double h2       = 20;  // 섹션 제목
  static const double h1       = 24;  // 강조 숫자 (스코어 등)
  static const double display  = 34;  // 스코어보드 메인

  // weight tokens
  static const FontWeight thin     = FontWeight.w300;
  static const FontWeight regular  = FontWeight.w400;
  static const FontWeight semibold = FontWeight.w500;
  static const FontWeight medium   = FontWeight.w600;
  static const FontWeight bold     = FontWeight.w700;
  static const FontWeight extra    = FontWeight.w800;
  static const FontWeight black    = FontWeight.w900;
}

class SemColor {
  // semantic
  static const live    = Color(0xFFE53935);  // 라이브 / 위험
  static const success = Color(0xFF1976D2);  // 승투 / 성공
  static const warning = Color(0xFFFFA000);  // 경고 / 라인업
  static const danger  = Color(0xFFC62828);  // 패투 / 위험 강조
  static const info    = success;            // 정보 — success와 동일 (의도적 alias)

  /// 브랜드 색 (테마 분기) — 다크모드 #E5E5E7 / 라이트 #111113
  static Color brand(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark
          ? const Color(0xFFE5E5E7) : panelDark;

  // BSO
  static const bsoB = Color(0xFF22C55E);  // ball
  static const bsoS = Color(0xFFF43F5E);  // strike
  static const bsoO = Color(0xFFF97316);  // out

  // base 점거
  static const baseOn   = Color(0xFFFCD34D);
  static const baseAura = Color(0xFFF59E0B);

  // dark panel/sheet bg (SnackBar, game header, player header)
  static const panelDark = Color(0xFF111113);
}

/// 중성 팔레트 (다크/라이트 쌍) — 화면별 `_C`/로컬 헬퍼가 반복 정의하던 9단계 중앙화.
/// 인자 = isDark (각 빌드 스코프가 이미 계산한 값 전달, Theme 재조회 회피).
/// ⚠️ 값은 기존 인라인 정준값과 1:1. 변경 시 전 화면 영향 — 다크 가시성 감사 동반.
class Pal {
  static Color ink(bool d)    => d ? const Color(0xFFF4F4F5) : const Color(0xFF111113);
  static Color ink2(bool d)   => d ? const Color(0xFFC9C9D1) : const Color(0xFF3F3F46);
  static Color ink3(bool d)   => d ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B73);
  static Color sub(bool d)    => d ? const Color(0xFF8E8E98) : const Color(0xFF9A9AA2);
  static Color paper(bool d)  => d ? const Color(0xFF18181C) : Colors.white;
  static Color paper2(bool d) => d ? const Color(0xFF1F1F24) : const Color(0xFFF5F5F6);
  static Color line(bool d)   => d ? const Color(0xFF26262C) : const Color(0xFFEDEDF0);
  static Color line2(bool d)  => d ? const Color(0xFF33333A) : const Color(0xFFE0E0E4);
  static Color track(bool d)  => d ? const Color(0xFF2C2C33) : const Color(0xFFE8E8EC);
}

class Space {
  static const double xs  = 4;
  static const double sm  = 8;
  static const double md  = 12;
  static const double lg  = 16;
  static const double xl  = 24;
  static const double xxl = 32;
}

class Radii {
  // 모서리 반경 통일 scale (Flutter Radius와 충돌 회피 → Radii)
  static const double xs  = 4;   // chip mini
  static const double sm  = 8;   // chip
  static const double md  = 12;  // card inner
  static const double lg  = 16;  // card outer
  static const double xl  = 20;  // sheet, dialog
  static const double pill = 999;
}

// 최소 터치 영역 (iOS HIG / Android Material)
const double kMinTapTarget = 44;
