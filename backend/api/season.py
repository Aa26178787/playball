"""시즌 단계 상태머신 — 순수 판별 (DB 없음). scheduler가 일정으로 호출.

postseason은 자동 판별 안 함 (KBO 일정에 PS 구분 메타 부재) — admin 핀 전용.
"""
from datetime import date


def compute_phase(today: date, first_game, last_game, has_recent: bool) -> str:
    """오늘 + 올해 정규경기 first/last(date|None) + 최근 ±10일 경기 유무 → 단계.

    - first/last 미정 → 'offseason' (일정 없음)
    - today < first_game → 'preseason'
    - today > last_game AND 최근 경기 없음 → 'offseason'
    - 그 외 → 'regular'
    """
    if first_game is None or last_game is None:
        return 'offseason'
    if today < first_game:
        return 'preseason'
    if today > last_game and not has_recent:
        return 'offseason'
    return 'regular'
