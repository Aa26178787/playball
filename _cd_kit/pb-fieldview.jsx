// pb-fieldview.jsx — PlayBall 필드뷰(다이아몬드+주자+타자+수비+BSO) 충실 복제. window.PB 의존.
// 출처 = game_detail_screen.dart _FullFieldView (SVG 300x310 좌표계) + _GrassExtensionPainter(잔디색).
// 좌표/색 = dart 정확값. 시그니처 = KBO 라이브 필드뷰.

// dart _posCoords / _baseCoords / 잔디 그라디언트 그대로.
const FV = {
  pos: { P:[150,208], C:[150,283], '1B':[220,186], '2B':[183,153], SS:[117,153], '3B':[80,186],
         LF:[64,118], CF:[150,92], RF:[236,118] },
  base: { base1:[208,208], base2:[150,150], base3:[92,208] },
  homePlate: [150,262],
  batterR: [132,262], batterL: [168,262],
  grass: ['#356030', '#264821'], stripe: ['#54944A', '#4C8A42'],
  bso: { B: '#22C55E', S: '#F43F5E', O: '#FFA000' },
  baseOn: '#FCD34D',
};

// BSO 오버레이 (상단) — B 3 / S 2 / O 2 dots
function PBBso({ b = 0, s = 0, o = 0 }) {
  const grp = (label, n, max, color) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
      <span style={{ font: `800 11px/1 ${PB.font}`, color: '#fff', width: 12 }}>{label}</span>
      {Array.from({ length: max }).map((_, i) => (
        <span key={i} style={{ width: 8, height: 8, borderRadius: '50%',
          background: i < n ? color : 'rgba(255,255,255,.22)' }} />
      ))}
    </div>
  );
  return (
    <div style={{ position: 'absolute', top: 8, left: '50%', transform: 'translateX(-50%)', zIndex: 2,
      display: 'flex', gap: 12, background: 'rgba(0,0,0,.45)', padding: '6px 12px', borderRadius: 999, backdropFilter: 'blur(2px)' }}>
      {grp('B', b, 3, FV.bso.B)}{grp('S', s, 2, FV.bso.S)}{grp('O', o, 2, FV.bso.O)}
    </div>
  );
}

// 선수 점 (수비=팀컬러 / 주자=노랑 / 타자=흰테)
function FieldDot({ x, y, color, label, ring, size = 19, w = 300, h = 310 }) {
  const left = `${(x / w) * 100}%`, top = `${(y / h) * 100}%`;
  return (
    <div style={{ position: 'absolute', left, top, transform: 'translate(-50%,-50%)', textAlign: 'center', zIndex: 1 }}>
      <div style={{ width: size, height: size, borderRadius: '50%', background: color, margin: '0 auto',
        border: ring ? '2px solid #fff' : '1.5px solid rgba(0,0,0,.25)', boxShadow: '0 1px 2px rgba(0,0,0,.3)' }} />
      {label && <div style={{ font: `700 8.5px/1.1 ${PB.font}`, color: '#fff', marginTop: 2, textShadow: '0 1px 2px rgba(0,0,0,.8)', whiteSpace: 'nowrap' }}>{label}</div>}
    </div>
  );
}

// 필드뷰 — fieldView={ defense:[{pos,name}], runners:{base1,..}, batter:{name,bats}, bso:{b,s,o} }
function PBFieldView({ fieldView = {}, defendCode = 'LG', isDark = true, width = 300 }) {
  const W = 300, H = 310, scale = width / W;
  const def = fieldView.defense || [];
  const runners = fieldView.runners || {};
  const batter = fieldView.batter || null;
  const bso = fieldView.bso || { b: 0, s: 0, o: 0 };
  const defColor = PB.teamColor(defendCode);

  // 다이아몬드 라인 = home→1B→2B→3B→home (베이스 중심 좌표)
  const [h0, h1] = FV.homePlate, [b1x, b1y] = FV.base.base1, [b2x, b2y] = FV.base.base2, [b3x, b3y] = FV.base.base3;
  const diamond = `${h0},${h1} ${b1x},${b1y} ${b2x},${b2y} ${b3x},${b3y}`;
  const batPos = batter && batter.bats === 'L' ? FV.batterL : FV.batterR;

  return (
    <div style={{ position: 'relative', width, height: H * scale, borderRadius: 18, overflow: 'hidden', fontFamily: PB.font }}>
      <svg viewBox={`0 0 ${W} ${H}`} width={width} height={H * scale} style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <radialGradient id="pbgrass" cx="50%" cy="38%" r="75%">
            <stop offset="0%" stopColor={FV.grass[0]} /><stop offset="100%" stopColor={FV.grass[1]} />
          </radialGradient>
        </defs>
        <rect width={W} height={H} fill="url(#pbgrass)" />
        {/* 잔디 스트라이프 */}
        {[0, 1, 2, 3, 4, 5].map(i => (
          <rect key={i} x={i * 50} y="0" width="25" height={H} fill={FV.stripe[i % 2]} opacity="0.10" />
        ))}
        {/* 외야 펜스 호 */}
        <path d="M30 120 Q150 -8 270 120" fill="none" stroke="rgba(255,255,255,.25)" strokeWidth="2" />
        {/* 내야 흙 다이아몬드 */}
        <polygon points={diamond} fill="#8a6d4b" opacity="0.92" stroke="rgba(255,255,255,.35)" strokeWidth="1.5" />
        {/* 베이스 사각 */}
        {[FV.base.base1, FV.base.base2, FV.base.base3].map(([x, y], i) => (
          <rect key={i} x={x - 5} y={y - 5} width="10" height="10" fill="#fff" transform={`rotate(45 ${x} ${y})`} />
        ))}
        {/* 홈플레이트 */}
        <polygon points={`${h0 - 6},${h1 - 2} ${h0 + 6},${h1 - 2} ${h0 + 6},${h1 + 3} ${h0},${h1 + 7} ${h0 - 6},${h1 + 3}`} fill="#fff" />
        {/* 마운드 */}
        <circle cx={FV.pos.P[0]} cy={FV.pos.P[1]} r="13" fill="#8a6d4b" stroke="rgba(255,255,255,.3)" />
      </svg>

      <PBBso b={bso.b} s={bso.s} o={bso.o} />

      {/* 수비 (팀컬러) */}
      {Object.entries(FV.pos).map(([code, [x, y]]) => {
        const d = def.find(p => p.pos === code);
        return <FieldDot key={code} x={x} y={y} color={defColor} label={d ? d.name : ''} size={code === 'P' ? 20 : 18} />;
      })}
      {/* 주자 (노랑) */}
      {['base1', 'base2', 'base3'].map(bk => runners[bk] ? (
        <FieldDot key={bk} x={FV.base[bk][0]} y={FV.base[bk][1]} color={FV.baseOn} label={runners[bk].name} ring size={18} />
      ) : null)}
      {/* 타자 (흰테, 좌/우 배터박스) */}
      {batter && <FieldDot x={batPos[0]} y={batPos[1]} color="#E5E5E7" label={batter.name} ring size={20} />}
    </div>
  );
}

Object.assign(window, { FV, PBBso, FieldDot, PBFieldView });
