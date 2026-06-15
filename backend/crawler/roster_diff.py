"""1군 등록현황 ↔ DB diff 순수 판정 (DB/크롤 없음 — 테스트 용이).

이탈 판정 = 등록현황 부재 AND 2026 1군 출전 있었음 AND 최근 출전이 stale_days 초과 전.
  → 등록부재 단독은 위험(크롤 누락·휴식·당일말소로 현역 오탐). staleness 결합으로 방어.
복귀(등록 재등장 + 현재 말소/2군 표기) → '1군등록'. 순수 2군/미debut(1군 활동 없음)은 미대상.

C1(2026-06-16): futures_registered(2군 등록현황) 주면 '부상≠2군' 구분.
  2군 등록 = positive 증거(staleness 불요) → '2군'(강등). 어느 군에도 없음 = '등록말소'(이탈/부상).
"""


def classify_roster_diff(registered: set, db_players: list[dict], stale_days: int = 14,
                         futures_registered: set | None = None) -> list[tuple]:
    """registered: 현재 1군 등록 선수명 집합. futures_registered: 현재 2군 등록 선수명 집합(옵션).
    db_players: [{'name', 'had_1gun': bool, 'latest': change_type|None, 'days_since_last': int|None}]
    반환: 적용할 변경만 [(name, '등록말소'|'1군등록'|'2군'), ...].

    판정:
      1군 부재 & had_1gun & 2군 등록    → '2군'      (강등 — 2군 활동 = 부상 아님, 즉시판정)
      1군 부재 & had_1gun & 2군도 부재 & stale → '등록말소' (이탈/부상 — 부재 추론이라 staleness 가드)
      1군 등록 & latest∈(등록말소,2군)   → '1군등록'  (복귀)
    """
    futures_registered = futures_registered or set()
    has_futures = bool(futures_registered)
    out = []
    for p in db_players:
        name = p['name']
        in_reg = name in registered
        in_fut = name in futures_registered
        days = p.get('days_since_last') or 0
        latest = p.get('latest')
        if not in_reg and p['had_1gun']:
            if has_futures and in_fut:
                if latest != '2군':
                    out.append((name, '2군'))            # 2군 활동 확인 = 강등(부상 아님)
            elif (not in_fut) and days > stale_days and latest != '등록말소':
                # has_futures=False(2군 크롤 실패)면 종전 거동 유지(말소 추론)
                out.append((name, '등록말소'))
        elif in_reg and latest in ('등록말소', '2군'):
            out.append((name, '1군등록'))
    return out
