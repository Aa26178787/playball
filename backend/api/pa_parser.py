"""타석(PA) 정규화 — game_pitches 텍스트 중계를 타석 단위로 파싱해 plate_appearances 적재

소비자: per-PA 안타확률 모델 라벨 / WPA·클러치 집계 / 투수vs타자 matchup 통산.
안타 판정 = 존히트맵(players.py)과 동일 규칙: '1루타/2루타/3루타/홈런/내야안타'
('안타' 단독 표기는 Naver가 쓰지 않음).

game_pitches type 코드: 0=이닝 시작, 1=투구, 8=타자 등장, 13=타석 결과, 14=주자 플레이.
각 행의 strike/ball/out/base1~3/score/home_win_rate = 해당 시점 스냅샷
→ 타자 등장(8) 행 = 타석 시작 컨텍스트, 결과(13) 행 = 타석 종료 승률(WPA 재료).
win_rate_before/after는 홈팀 기준 Naver 승률(0~100).
"""
import logging

from database.connection import get_connection

logger = logging.getLogger(__name__)

_T_PITCH, _T_BATTER, _T_RESULT = 1, 8, 13


def classify_result(text: str) -> tuple[str, bool]:
    """타석 결과 텍스트 → (result_class, is_hit). 분기 순서가 정확도를 좌우."""
    t = text or ''
    if '홈런' in t:
        return 'hr', True
    if '3루타' in t:
        return 'triple', True
    if '2루타' in t:
        return 'double', True
    if '1루타' in t or '내야안타' in t or '번트안타' in t:
        return 'single', True
    if '고의4구' in t or '고의 4구' in t:
        return 'ibb', False
    if '볼넷' in t:
        return 'bb', False
    if '몸에' in t:  # 몸에 맞는 볼
        return 'hbp', False
    if '삼진' in t or '낫아웃' in t or '낫 아웃' in t:
        return 'so', False
    if '희생번트' in t or '희생 번트' in t:
        return 'sac_bunt', False
    if '희생플라이' in t or '희생 플라이' in t:
        return 'sac_fly', False
    if '실책' in t:
        return 'error', False
    if '야수선택' in t or '야수 선택' in t:
        return 'fc', False
    if '타격방해' in t or '포수방해' in t:
        return 'interference', False
    # '땅볼로 출루' 류 — 아웃 단어가 같이 있으면 아웃 우선
    if '출루' in t and '아웃' not in t:
        return 'reach_other', False
    if ('아웃' in t or '병살' in t or '땅볼' in t or '플라이' in t
            or '직선타' in t or '라인드라이브' in t):
        return 'out', False
    return 'etc', False


def _batter_from_title(title: str) -> str:
    """'1번타자 김지찬' → '김지찬' (batter_name 컬럼 누락 가드)"""
    parts = (title or '').strip().split()
    return parts[-1] if parts else ''


def parse_game_pas(rows) -> list[dict]:
    """정렬된 game_pitches 행들 → 타석 dict 리스트.

    rows 컬럼 순서:
      (inning, inning_half, seqno, type, batter_name, pitcher_name, title,
       strike, ball, out, base1, base2, base3, home_score, away_score, home_win_rate)
    결과(13) 없이 끝난 미완 타석(이닝 3아웃 주자사 등)은 버린다.
    같은 타석 중 타자 교체(대타) = 동일 pa_seq 슬롯을 새 타자로 대체.
    """
    pas: list[dict] = []
    counters: dict[tuple, int] = {}
    open_pa: dict | None = None
    last_wr = None  # 직전 non-null 홈 승률 (행 누락 가드)
    # 직전 투구행 스냅샷 — 타자 등장(8) 행은 out/base/score가 비어 있어(전부 0)
    # 같은 이닝half의 마지막 투구행 상태를 타석 시작 컨텍스트로 사용
    ctx_key = None
    ctx = {'out': 0, 'b1': False, 'b2': False, 'b3': False, 'hs': 0, 'as': 0}

    for (inning, half, seqno, rtype, batter, pitcher, title,
         strike, ball, out, b1, b2, b3, hs, a_s, hwr) in rows:
        if rtype == _T_BATTER:
            key = (inning, half)
            if ctx_key != key:  # 이닝 전환 — 컨텍스트 리셋
                ctx = {'out': 0, 'b1': False, 'b2': False, 'b3': False, 'hs': 0, 'as': 0}
                ctx_key = key
            if open_pa is not None and (open_pa['inning'], open_pa['inning_half']) == key:
                seq = open_pa['pa_seq']  # 대타 교체 — 같은 타석 슬롯 대체
            else:
                seq = counters.get(key, 0) + 1
            counters[key] = seq
            open_pa = {
                'inning': inning, 'inning_half': half, 'pa_seq': seq,
                'batter_name': (batter or '').strip() or _batter_from_title(title),
                'pitcher_name': (pitcher or '').strip(),
                'result_text': '', 'result_class': '', 'is_hit': False,
                'n_pitches': 0,
                'outs_before': ctx['out'],
                'base1': ctx['b1'], 'base2': ctx['b2'], 'base3': ctx['b3'],
                'home_score': ctx['hs'], 'away_score': ctx['as'],
                'win_rate_before': hwr if hwr is not None else last_wr,
                'win_rate_after': None,
                'seq_start': seqno, 'seq_end': seqno,
            }
        elif rtype == _T_PITCH:
            ctx_key = (inning, half)
            ctx = {'out': out or 0, 'b1': bool(b1), 'b2': bool(b2), 'b3': bool(b3),
                   'hs': hs or 0, 'as': a_s or 0}
            if open_pa is not None:
                if open_pa['n_pitches'] == 0:
                    # 타석 첫 투구행 스냅샷 = 정확한 타석 시작 상태
                    # (직전 타석 마지막 투구는 그 결과(안타 등) 반영 전이라 부정확)
                    open_pa['outs_before'] = out or 0
                    open_pa['base1'], open_pa['base2'], open_pa['base3'] = bool(b1), bool(b2), bool(b3)
                    open_pa['home_score'], open_pa['away_score'] = hs or 0, a_s or 0
                    if hwr is not None:
                        open_pa['win_rate_before'] = hwr
                open_pa['n_pitches'] += 1
                if pitcher and pitcher.strip():
                    open_pa['pitcher_name'] = pitcher.strip()
                open_pa['seq_end'] = seqno
        elif rtype == _T_RESULT and open_pa is not None:
            txt = (title or '').strip()
            cls, is_hit = classify_result(txt)
            open_pa['result_text'] = txt[:200]
            open_pa['result_class'] = cls
            open_pa['is_hit'] = is_hit
            open_pa['win_rate_after'] = hwr if hwr is not None else last_wr
            if pitcher and pitcher.strip() and not open_pa['pitcher_name']:
                open_pa['pitcher_name'] = pitcher.strip()
            open_pa['seq_end'] = seqno
            pas.append(open_pa)
            open_pa = None
        if hwr is not None:
            last_wr = hwr
    return pas


def save_plate_appearances_for_game(game_id: int) -> int:
    """게임 1개 파싱 → plate_appearances upsert. 반환 = 적재 타석 수."""
    conn = get_connection()
    if not conn:
        return 0
    try:
        cur = conn.cursor()
        # 시즌 초 경기는 크롤러가 카운트/주자/스코어 스냅샷을 안 채움(전부 0/false)
        # → 미기록 게임은 컨텍스트를 NULL로 적재 (0/false로 두면 모델이 거짓 학습)
        cur.execute("""
            SELECT EXISTS (
                SELECT 1 FROM game_pitches
                WHERE game_id = %s AND type = 1
                  AND (strike > 0 OR ball > 0 OR out > 0 OR base1 OR base2 OR base3)
            )
        """, (game_id,))
        has_ctx = bool(cur.fetchone()[0])
        cur.execute("""
            SELECT inning, inning_half, seqno, type, batter_name, pitcher_name, title,
                   strike, ball, out, base1, base2, base3,
                   home_score, away_score, home_win_rate
            FROM game_pitches
            WHERE game_id = %s
            ORDER BY inning, inning_half, seqno, id
        """, (game_id,))
        pas = parse_game_pas(cur.fetchall())
        if not has_ctx:
            for pa in pas:
                pa['outs_before'] = None
                pa['base1'] = pa['base2'] = pa['base3'] = None
                pa['home_score'] = pa['away_score'] = None
        for pa in pas:
            cur.execute("""
                INSERT INTO plate_appearances
                  (game_id, inning, inning_half, pa_seq, batter_name, pitcher_name,
                   result_text, result_class, is_hit, n_pitches, outs_before,
                   base1, base2, base3, home_score, away_score,
                   win_rate_before, win_rate_after, seq_start, seq_end)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (game_id, inning, inning_half, pa_seq) DO UPDATE SET
                  batter_name = EXCLUDED.batter_name,
                  pitcher_name = EXCLUDED.pitcher_name,
                  result_text = EXCLUDED.result_text,
                  result_class = EXCLUDED.result_class,
                  is_hit = EXCLUDED.is_hit,
                  n_pitches = EXCLUDED.n_pitches,
                  outs_before = EXCLUDED.outs_before,
                  base1 = EXCLUDED.base1, base2 = EXCLUDED.base2, base3 = EXCLUDED.base3,
                  home_score = EXCLUDED.home_score, away_score = EXCLUDED.away_score,
                  win_rate_before = EXCLUDED.win_rate_before,
                  win_rate_after = EXCLUDED.win_rate_after,
                  seq_start = EXCLUDED.seq_start, seq_end = EXCLUDED.seq_end
            """, (game_id, pa['inning'], pa['inning_half'], pa['pa_seq'],
                  pa['batter_name'][:50], pa['pitcher_name'][:50],
                  pa['result_text'], pa['result_class'], pa['is_hit'],
                  pa['n_pitches'], pa['outs_before'],
                  pa['base1'], pa['base2'], pa['base3'],
                  pa['home_score'], pa['away_score'],
                  pa['win_rate_before'], pa['win_rate_after'],
                  pa['seq_start'], pa['seq_end']))
        conn.commit()
        cur.close()
        return len(pas)
    except Exception as e:
        logger.error(f"[PA] 적재 실패 game={game_id}: {e}")
        try:
            conn.rollback()
        except Exception:
            pass
        return 0
    finally:
        conn.close()
