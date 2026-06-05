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
  // size scale (px)
  static const double micro   = 9;   // dot, badge mini
  static const double caption = 11;  // chip, label
  static const double body    = 13;  // 본문, 일반 정보
  static const double subtitle= 14;  // 부제목
  static const double title   = 16;  // 제목
  static const double h2      = 20;  // 큰 제목
  static const double h1      = 24;  // 스코어 등 강조
  static const double display = 34;  // 스코어보드 메인

  // weight tokens
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium  = FontWeight.w600;
  static const FontWeight bold    = FontWeight.w700;
  static const FontWeight extra   = FontWeight.w800;
}

class SemColor {
  // semantic
  static const live    = Color(0xFFE53935);  // 라이브 / 위험
  static const success = Color(0xFF1976D2);  // 승투 / 성공
  static const warning = Color(0xFFFFA000);  // 경고 / 라인업
  static const danger  = Color(0xFFC62828);  // 패투 / 위험 강조
  static const info    = Color(0xFF1976D2);  // 정보

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

class Space {
  static const double xs  = 4;
  static const double sm  = 8;
  static const double md  = 12;
  static const double lg  = 16;
  static const double xl  = 24;
  static const double xxl = 32;
}

// 최소 터치 영역 (iOS HIG / Android Material)
const double kMinTapTarget = 44;
