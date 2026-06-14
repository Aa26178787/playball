"""1군 등록현황 ↔ DB diff 순수 판정 (DB/크롤 없음 — 테스트 용이).

문동주류: 2026 1군 출전 있었으나 현재 등록명단 부재 = 1군 이탈 → '등록말소' 표기.
복귀(등록명단 재등장) → '1군등록'. 순수 2군/미debut(1군 활동 없음)은 미대상(오말소 방지).
"""


def classify_roster_diff(registered: set, db_players: list[dict]) -> list[tuple]:
    """registered: 현재 1군 등록 선수명 집합.
    db_players: [{'name', 'had_1gun': bool, 'latest': 최신 change_type|None}]
    반환: 적용할 변경만 [(name, '등록말소'|'1군등록'), ...]."""
    out = []
    for p in db_players:
        name, had, latest = p['name'], p['had_1gun'], p['latest']
        in_reg = name in registered
        if not in_reg and had and latest != '등록말소':
            out.append((name, '등록말소'))
        elif in_reg and latest == '등록말소':
            out.append((name, '1군등록'))
    return out
