// pb-components.jsx — PlayBall 순위카드 · 선수행 · compact 게임카드 (실토큰). window.PB 의존.
// 출처 = team_screen.dart(_buildCardRow) · player_screen.dart(_numAvatar,_buildRankRow) · home_screen.dart(compact).

// ── 순위변동 ▲▼ ──
function PBMove({ delta, isDark }) {
  const p = PB.pal(isDark);
  if (delta == null || delta === 0) return <span style={{ font: `${PB.typo.bold} 9px/1 ${PB.font}`, color: p.line2 }}>–</span>;
  const up = delta > 0;
  return <span style={{ font: `${PB.typo.bold} 9px/1 ${PB.font}`, color: up ? PB.sem.success : PB.sem.danger }}>
    {up ? '▲' : '▼'}{Math.abs(delta)}</span>;
}

// ── 팀 순위 카드 (마이팀=팀컬러 tint / top3=ink / 선두 뱃지) ──
function PBRankCard({ team, isDark = true, isFav = false }) {
  const p = PB.pal(isDark);
  const tc = PB.adjustTeam(team.code, isDark);
  const isLead = !team.gb || team.gb === 0;
  const cardBg = isFav ? hexA(tc, isDark ? 0.18 : 0.07) : p.paper;
  const cardBd = isFav ? hexA(tc, isDark ? 0.55 : 0.40) : p.line;
  const rankCol = isFav ? tc : (team.rank <= 3 ? p.ink : p.sub);
  const badge = (txt, bg, fg) => <span style={{ font: `${PB.typo.extra} ${PB.typo.micro}px/1 ${PB.font}`, color: fg, background: bg, padding: '2px 6px', borderRadius: PB.radii.xs }}>{txt}</span>;
  return (
    <div style={{ background: cardBg, border: `1px solid ${cardBd}`, borderRadius: PB.radii.lg, padding: '13px 14px', fontFamily: PB.font, display: 'flex', alignItems: 'center' }}>
      <div style={{ width: 24, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
        <span style={{ font: `${PB.typo.extra} ${PB.typo.lg}px/1 ${PB.font}`, color: rankCol, fontVariantNumeric: 'tabular-nums' }}>{team.rank}</span>
        <PBMove delta={team.rankChange} isDark={isDark} />
      </div>
      <div style={{ width: 13 }} />
      <PBLogo code={team.code} size={42} />
      <div style={{ width: 13 }} />
      <div style={{ flex: 1 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <span style={{ font: `${PB.typo.extra} ${PB.typo.subtitle}px/1 ${PB.font}`, color: p.ink }}>{PB.teamName[team.code]}</span>
          {isFav && badge('마이팀', tc, '#fff')}
          {isLead && badge('선두', p.ink, isDark ? '#0F0F12' : '#fff')}
        </div>
        <div style={{ height: 7 }} />
        <div style={{ display: 'flex', alignItems: 'center' }}>
          <span style={{ font: `${PB.typo.semibold} ${PB.typo.body}px/1 ${PB.font}`, color: p.ink3, fontVariantNumeric: 'tabular-nums' }}>
            {team.w}승 {team.l}패{team.d > 0 ? ` ${team.d}무` : ''}</span>
          <span style={{ width: 1, height: 11, margin: '0 8px', background: p.line2 }} />
          <span style={{ font: `${PB.typo.semibold} ${PB.typo.body}px/1 ${PB.font}`, color: p.ink3, fontVariantNumeric: 'tabular-nums' }}>{team.w + team.l + team.d}경기</span>
          <span style={{ width: 1, height: 11, margin: '0 8px', background: p.line2 }} />
          <span style={{ font: `${PB.typo.bold} ${PB.typo.body}px/1 ${PB.font}`, color: p.ink, fontVariantNumeric: 'tabular-nums' }}>{Math.round(team.winRate * 100)}%</span>
        </div>
      </div>
    </div>
  );
}

// ── 선수 아바타 (팀컬러 보더 + #번호 미니배지) ──
function PBNumAvatar({ player, size = 42 }) {
  const c = PB.teamColor(player.code);
  return (
    <div style={{ width: size, height: size, position: 'relative', flexShrink: 0 }}>
      <div style={{ width: size, height: size, borderRadius: '50%', border: `2px solid ${hexA(c, 0.45)}`,
        background: hexA(c, 0.88), display: 'flex', alignItems: 'center', justifyContent: 'center',
        font: `${PB.typo.extra} ${Math.round(size * 0.28)}px/1 ${PB.font}`, color: '#fff' }}>
        {player.number ? `#${player.number}` : (player.name || '?')[0]}
      </div>
      {player.number && (
        <div style={{ position: 'absolute', right: -2, bottom: -2, background: hexA(c, 0.95),
          border: '1px solid #fff', borderRadius: 5, padding: '1px 4px',
          font: `${PB.typo.extra} ${PB.typo.micro}px/1 ${PB.font}`, color: '#fff' }}>#{player.number}</div>
      )}
    </div>
  );
}

// ── 선수 순위 리스트 행 ──
function PBPlayerRow({ rank, player, statVal, statLabel, isDark = true }) {
  const p = PB.pal(isDark);
  const tc = PB.adjustTeam(player.code, isDark);
  const isTop3 = rank <= 3;
  return (
    <div style={{ display: 'flex', alignItems: 'center', padding: '11px 18px', borderBottom: `1px solid ${p.line}`, fontFamily: PB.font }}>
      <div style={{ width: 28, textAlign: 'center', font: `${PB.typo.extra} ${isTop3 ? 18 : 14}px/1 ${PB.font}`, color: isTop3 ? tc : p.sub, fontVariantNumeric: 'tabular-nums' }}>{rank}</div>
      <div style={{ width: 11 }} />
      <PBNumAvatar player={player} size={42} />
      <div style={{ width: 11 }} />
      <div style={{ flex: 1 }}>
        <div style={{ font: `${PB.typo.extra} ${PB.typo.subtitle}px/1 ${PB.font}`, color: p.ink }}>{player.name}</div>
        <div style={{ height: 4 }} />
        <div style={{ font: `${PB.typo.regular} ${PB.typo.mini}px/1 ${PB.font}`, color: p.ink2 }}>{PB.teamName[player.code]} · {player.position}</div>
      </div>
      <div style={{ textAlign: 'right' }}>
        <div style={{ font: `${PB.typo.extra} ${PB.typo.h2}px/1 ${PB.font}`, color: p.ink, fontVariantNumeric: 'tabular-nums' }}>{statVal}</div>
        <div style={{ font: `${PB.typo.regular} ${PB.typo.micro}px/1 ${PB.font}`, color: p.sub, marginTop: 2 }}>{statLabel}</div>
      </div>
    </div>
  );
}

// ── compact 게임카드 (일반경기 — 양 사이드 로고44+홈/원정칩, 중앙 스코어/상태) ──
function PBCompactCard({ game, isDark = true }) {
  const p = PB.pal(isDark);
  const isUpcoming = ['예정', '선발확정', '라인업확정'].includes(game.status);
  const isFinished = game.status === '종료';
  const homeWon = isFinished && game.homeScore > game.awayScore;
  const awayWon = isFinished && game.awayScore > game.homeScore;
  const side = (code, isHome, won) => (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 5, width: 70 }}>
      <PBLogo code={code} size={44} dim={isFinished && !won && !((isHome ? homeWon : awayWon))} />
      <span style={{ font: `${PB.typo.bold} ${PB.typo.micro}px/1 ${PB.font}`, color: p.sub, background: p.track, padding: '2px 6px', borderRadius: PB.radii.xs }}>{isHome ? '홈' : '원정'}</span>
    </div>
  );
  return (
    <div style={{ background: p.paper, border: `1px solid ${p.line}`, borderRadius: PB.radii.lg, padding: '14px 16px', fontFamily: PB.font, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
      {side(game.homeCode, true, homeWon)}
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
        {isUpcoming
          ? <span style={{ font: `${PB.typo.extra} 18px/1 ${PB.font}`, color: p.ink }}>{game.startTime || 'VS'}</span>
          : <span style={{ font: `${PB.typo.extra} 18px/1 ${PB.font}`, color: p.ink, fontVariantNumeric: 'tabular-nums' }}>
              <span style={{ color: homeWon ? p.ink : p.ink2, opacity: homeWon ? 1 : .55 }}>{game.homeScore}</span>
              <span style={{ color: p.ink3, padding: '0 6px' }}>:</span>
              <span style={{ color: awayWon ? p.ink : p.ink2, opacity: awayWon ? 1 : .55 }}>{game.awayScore}</span>
            </span>}
        <PBStatusPill status={game.status} isDark={isDark} />
      </div>
      {side(game.awayCode, false, awayWon)}
    </div>
  );
}

// 팀로고 스탠드인 (dim = 패팀 흐림)
function PBLogo({ code, size = 44, dim = false }) {
  return <div style={{ width: size, height: size, borderRadius: '50%', background: PB.teamColor(code), opacity: dim ? 0.45 : 1,
    display: 'flex', alignItems: 'center', justifyContent: 'center', font: `800 ${Math.round(size * 0.32)}px/1 ${PB.font}`, color: '#fff' }}>{PB.teamName[code] || code}</div>;
}

// hex + alpha → rgba
function hexA(hex, a) {
  const r = parseInt(hex.slice(1, 3), 16), g = parseInt(hex.slice(3, 5), 16), b = parseInt(hex.slice(5, 7), 16);
  return `rgba(${r},${g},${b},${a})`;
}

Object.assign(window, { PBMove, PBRankCard, PBNumAvatar, PBPlayerRow, PBCompactCard, PBLogo, hexA });
