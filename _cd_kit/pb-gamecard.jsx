// pb-gamecard.jsx — PlayBall 홈 게임카드(풀/hero) 충실 복제. window.PB 토큰 사용.
// 구조 출처 = app/lib/screens/home/home_screen.dart (_teamSide·_buildMini5·statusPill·score).
// 다크 우선. 팀로고는 실이미지 → 여기선 팀컬러 원형+코드 스탠드인.

// ── 팀 로고 스탠드인 (실앱=CachedNetworkImage 로고) ──
function PBTeamLogo({ code, size = 46 }) {
  const c = PB.teamColor(code);
  return (
    <div style={{
      width: size, height: size, borderRadius: '50%', flexShrink: 0,
      background: c, display: 'flex', alignItems: 'center', justifyContent: 'center',
      font: `800 ${Math.round(size * 0.34)}px/1 ${PB.font}`, color: '#fff', letterSpacing: '-.02em',
    }}>{PB.teamName[code] || code}</div>
  );
}

// ── 상태 pill (예정→선발확정→라인업확정→LIVE→종료) ──
function PBStatusPill({ status, isDark }) {
  const p = PB.pal(isDark);
  const map = {
    '예정':     { bg: p.track, fg: p.ink3, dot: null,         label: '예정' },
    '선발확정':  { bg: 'rgba(255,160,0,.16)', fg: PB.sem.warning, dot: PB.sem.warning, label: '선발 확정' },
    '라인업확정': { bg: 'rgba(255,160,0,.22)', fg: PB.sem.warning, dot: PB.sem.warning, label: '라인업 확정' },
    'LIVE':     { bg: 'rgba(229,57,53,.16)', fg: PB.sem.live, dot: PB.sem.live, label: 'LIVE' },
    '종료':     { bg: p.track, fg: p.sub, dot: null,          label: '종료' },
  };
  const s = map[status] || map['예정'];
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 5,
      font: `${PB.typo.extra} ${PB.typo.caption}px/1 ${PB.font}`, color: s.fg,
      background: s.bg, padding: '5px 10px', borderRadius: PB.radii.pill,
    }}>
      {s.dot && <span style={{ width: 6, height: 6, borderRadius: '50%', background: s.dot }} />}
      {s.label}
    </span>
  );
}

// ── 최근5 (_buildMini5: 14x14 박스, W=팀컬러 L=#71717A 무=#A1A1AA, 최근경기 밑 2px선) ──
function PBMini5({ recent, accent, recentFirst = false }) {
  if (!recent || !recent.length) return <div style={{ height: 17 }} />;
  const recentIdx = recentFirst ? 0 : recent.length - 1;
  return (
    <div style={{ display: 'flex' }}>
      {recent.map((r, i) => {
        const fill = r === 'W' ? accent : r === 'L' ? '#71717A' : '#A1A1AA';
        return (
          <div key={i} style={{ marginRight: 2.5 }}>
            <div style={{
              width: 14, height: 14, borderRadius: PB.radii.xs, background: fill,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              font: `${PB.typo.extra} ${PB.typo.micro}px/1 ${PB.font}`, color: '#fff',
            }}>{r}</div>
            <div style={{ width: 14, height: 2, marginTop: 2, borderRadius: 1, background: i === recentIdx ? fill : 'transparent' }} />
          </div>
        );
      })}
    </div>
  );
}

// ── 팀 사이드 (로고46 + 팀명 + 'N위 · 홈/원정' + 최근5) ──
function PBTeamSide({ code, rank, isHome, recent, accent, isDark, recentFirst }) {
  const p = PB.pal(isDark);
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}>
      <PBTeamLogo code={code} size={46} />
      <div style={{ font: `${PB.typo.bold} ${PB.typo.subtitle}px/1 ${PB.font}`, color: p.ink }}>{PB.teamName[code] || code}</div>
      <div style={{ font: `${PB.typo.semibold} ${PB.typo.caption}px/1 ${PB.font}`, color: p.sub }}>
        {rank}위 · {isHome ? '홈' : '원정'}
      </div>
      <PBMini5 recent={recent} accent={accent} recentFirst={recentFirst} />
    </div>
  );
}

// ── 게임카드 (풀/hero) ──
function PBGameCard({ game, isDark = true, isMyTeam = true }) {
  const p = PB.pal(isDark);
  const accent = PB.adjustTeam(game.myCode || game.homeCode, isDark);
  const isLive = game.status === 'LIVE';
  const isUpcoming = ['예정', '선발확정', '라인업확정'].includes(game.status);
  const isFinished = game.status === '종료';
  const homeWon = isFinished && game.homeScore > game.awayScore;
  const awayWon = isFinished && game.awayScore > game.homeScore;
  const isDraw = isFinished && game.homeScore === game.awayScore;

  const scoreColor = (won) => won ? p.ink : (isDraw ? p.ink : p.ink2);
  const scoreSize = (won) => won ? 34 : 26;

  return (
    <div style={{
      background: p.paper, borderRadius: PB.radii.lg, border: `1px solid ${p.line}`,
      padding: '14px 0 16px', fontFamily: PB.font,
      boxShadow: isDark ? 'none' : '0 1px 3px rgba(0,0,0,0.05)',
    }}>
      {/* 헤더: 마이팀 칩 + 상태 pill */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 15px' }}>
        {isMyTeam ? (
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3 }}>
            <span style={{ color: accent, fontSize: 12 }}>★</span>
            <span style={{ font: `${PB.typo.extra} ${PB.typo.caption}px/1 ${PB.font}`, color: accent }}>마이팀</span>
          </span>
        ) : <span />}
        <PBStatusPill status={game.status} isDark={isDark} />
      </div>

      <div style={{ height: 13 }} />

      {/* 메인 grid: 홈 | 스코어(86) | 원정 */}
      <div style={{ display: 'flex', alignItems: 'center', padding: '0 15px' }}>
        <PBTeamSide code={game.homeCode} rank={game.homeRank} isHome accent={accent}
          recent={game.homeRecent} isDark={isDark} recentFirst={false} />
        <div style={{ width: 86, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
          {isUpcoming ? (
            <div style={{ font: `${PB.typo.extra} ${PB.typo.lg}px/1 ${PB.font}`, color: p.ink }}>{game.startTime || 'VS'}</div>
          ) : (
            <div style={{ display: 'flex', alignItems: 'baseline' }}>
              <span style={{ font: `${PB.typo.extra} ${scoreSize(homeWon)}px/1 ${PB.font}`, color: scoreColor(homeWon),
                opacity: (homeWon || isDraw) ? 1 : 0.55, fontVariantNumeric: 'tabular-nums' }}>{game.homeScore}</span>
              <span style={{ font: `${PB.typo.medium} ${PB.typo.h2}px/1 ${PB.font}`, color: p.ink3, padding: '0 9px' }}>:</span>
              <span style={{ font: `${PB.typo.extra} ${scoreSize(awayWon)}px/1 ${PB.font}`, color: scoreColor(awayWon),
                opacity: (awayWon || isDraw) ? 1 : 0.55, fontVariantNumeric: 'tabular-nums' }}>{game.awayScore}</span>
            </div>
          )}
          {isLive && <div style={{ font: `${PB.typo.medium} 9.5px/1 ${PB.font}`, color: PB.sem.live, marginTop: 6 }}>{game.inning}</div>}
          {isFinished && isDraw && <div style={{ font: `${PB.typo.medium} 9.5px/1 ${PB.font}`, color: p.ink3, marginTop: 6 }}>무승부</div>}
        </div>
        <PBTeamSide code={game.awayCode} rank={game.awayRank} isHome={false} accent={accent}
          recent={game.awayRecent} isDark={isDark} recentFirst={true} />
      </div>

      <div style={{ height: 10 }} />

      {/* 날씨 · 구장 (plain text) */}
      {game.weather && (
        <div style={{ textAlign: 'center', font: `${PB.typo.regular} ${PB.typo.small}px/1.3 ${PB.font}`, color: p.sub, padding: '0 15px' }}>
          {game.weather}
        </div>
      )}
    </div>
  );
}

Object.assign(window, { PBTeamLogo, PBStatusPill, PBMini5, PBTeamSide, PBGameCard });
