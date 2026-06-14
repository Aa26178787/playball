"""1군 등록현황 ↔ DB diff 순수 판정 (DB/크롤 없음 — 테스트 용이).

이탈 판정 = 등록현황 부재 AND 2026 1군 출전 있었음 AND 최근 출전이 stale_days 초과 전.
  → 등록부재 단독은 위험(크롤 누락·휴식·당일말소로 현역 오탐). staleness 결합으로 방어.
복귀(등록 재등장 + 현재 말소표기) → '1군등록'. 순수 2군/미debut(1군 활동 없음)은 미대상.
"""


def classify_roster_diff(registered: set, db_players: list[dict], stale_days: int = 14) -> list[tuple]:
    """registered: 현재 1군 등록 선수명 집합.
    db_players: [{'name', 'had_1gun': bool, 'latest': change_type|None, 'days_since_last': int|None}]
    반환: 적용할 변경만 [(name, '등록말소'|'1군등록'), ...]."""
    out = []
    for p in db_players:
        name = p['name']
        in_reg = name in registered
        days = p.get('days_since_last') or 0
        if (not in_reg and p['had_1gun'] and p['latest'] != '등록말소'
                and days > stale_days):
            out.append((name, '등록말소'))
        elif in_reg and p['latest'] == '등록말소':
            out.append((name, '1군등록'))
    return out
