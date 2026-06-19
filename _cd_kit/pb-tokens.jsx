// pb-tokens.jsx — PlayBall 실제 디자인 토큰 (design_tokens.dart + team_theme.dart 1:1)
// ⚠️ 권위 소스 = app/lib/utils/design_tokens.dart · team_theme.dart. 값은 그 정확 복제.
// 모든 PlayBall 컴포넌트는 이 토큰을 써야 실앱과 동일. window.PB 로 전역 노출.

const PB = {
  font: '-apple-system, "Pretendard Variable", "Helvetica Neue", Helvetica, Arial, sans-serif',

  // 중성 팔레트 (Pal) — pal(isDark). ink~sub 텍스트 4단계, paper/line/track surface.
  pal(d) {
    return d
      ? { ink:'#F4F4F5', ink2:'#C9C9D1', ink3:'#9A9AA3', sub:'#8E8E98',
          paper:'#18181C', paper2:'#1F1F24', line:'#26262C', line2:'#33333A', track:'#2C2C33', bg:'#0F0F12' }
      : { ink:'#111113', ink2:'#3F3F46', ink3:'#6B6B73', sub:'#9A9AA2',
          paper:'#FFFFFF', paper2:'#F5F5F6', line:'#EDEDF0', line2:'#E0E0E4', track:'#E8E8EC', bg:'#FAFAFA' };
  },

  // 시맨틱/도메인 색 (SemColor)
  sem: {
    live:'#E53935', success:'#1976D2', warning:'#FFA000', danger:'#C62828',
    bsoB:'#22C55E', bsoS:'#F43F5E', bsoO:'#F97316',
    baseOn:'#FCD34D', baseAura:'#F59E0B', panelDark:'#111113',
  },

  // 타이포 — size(px) 11단계 + weight 7단계
  typo: {
    micro:10, mini:11, caption:11, small:12, body:13, subtitle:14,
    title:16, lg:18, h2:20, h1:24, display:34,
    thin:300, regular:400, semibold:500, medium:600, bold:700, extra:800, black:900,
  },

  radii: { xs:4, sm:8, md:12, lg:16, xl:20, pill:999 },
  space: { xs:4, sm:8, md:12, lg:16, xl:24, xxl:32 },

  // 팀컬러 (team_theme.dart kTeamColors) — raw 값(로고/그라디언트 배경용)
  team: {
    LG:'#C30452', KT:'#3D424B', SK:'#CE0E2D', NC:'#071D49', OB:'#131E3E',
    HT:'#EA0029', LT:'#E4003C', SS:'#1B4BAB', HH:'#FF6600', WO:'#820024',
  },
  // 팀 표시명
  teamName: {
    LG:'LG', KT:'KT', SK:'SSG', NC:'NC', OB:'두산',
    HT:'KIA', LT:'롯데', SS:'삼성', HH:'한화', WO:'키움',
  },
  teamColor(code) { return this.team[code] || '#607D8B'; },

  // 전경 보정색 (adjustTeamColor) — 텍스트/배지/테두리/점에 사용.
  // 다크: l<0.45 → l+0.30(clamp .75) / 그 외 raw. 라이트: l>0.6 → l-0.10 / 그 외 raw.
  adjustTeam(code, isDark) {
    const { h, s, l } = hexToHsl(this.teamColor(code));
    let nl = l;
    if (isDark) { if (l < 0.45) nl = Math.min(l + 0.30, 0.75); else return this.teamColor(code); }
    else { if (l > 0.6) nl = Math.max(l - 0.10, 0); else return this.teamColor(code); }
    return hslToHex(h, s, nl);
  },
};

// ── hex ↔ hsl (adjustTeam 용) ──
function hexToHsl(hex) {
  let r = parseInt(hex.slice(1, 3), 16) / 255;
  let g = parseInt(hex.slice(3, 5), 16) / 255;
  let b = parseInt(hex.slice(5, 7), 16) / 255;
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
  let h = 0, s = 0; const l = (mx + mn) / 2;
  if (mx !== mn) {
    const d = mx - mn;
    s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    if (mx === r) h = (g - b) / d + (g < b ? 6 : 0);
    else if (mx === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h /= 6;
  }
  return { h, s, l };
}
function hslToHex(h, s, l) {
  let r, g, b;
  if (s === 0) { r = g = b = l; }
  else {
    const hue2rgb = (p, q, t) => {
      if (t < 0) t += 1; if (t > 1) t -= 1;
      if (t < 1 / 6) return p + (q - p) * 6 * t;
      if (t < 1 / 2) return q;
      if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
      return p;
    };
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    const p = 2 * l - q;
    r = hue2rgb(p, q, h + 1 / 3); g = hue2rgb(p, q, h); b = hue2rgb(p, q, h - 1 / 3);
  }
  const to = x => Math.round(x * 255).toString(16).padStart(2, '0');
  return `#${to(r)}${to(g)}${to(b)}`;
}

Object.assign(window, { PB, hexToHsl, hslToHex });
