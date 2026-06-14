"""시즌 상태머신 순수 판별 테스트 (DB 불요)."""
from datetime import date

from api.season import compute_phase


def test_preseason():
    assert compute_phase(date(2026, 3, 1), date(2026, 3, 22), date(2026, 10, 1), False) == 'preseason'


def test_regular_has_recent():
    assert compute_phase(date(2026, 6, 15), date(2026, 3, 22), date(2026, 10, 1), True) == 'regular'


def test_offseason_after_last():
    assert compute_phase(date(2026, 12, 1), date(2026, 3, 22), date(2026, 10, 1), False) == 'offseason'


def test_no_schedule_offseason():
    assert compute_phase(date(2026, 1, 5), None, None, False) == 'offseason'


def test_regular_during_window_no_recent_flag():
    # 시즌 기간 내(올스타 휴식 등 최근경기 플래그 False여도) → regular 유지
    assert compute_phase(date(2026, 7, 15), date(2026, 3, 22), date(2026, 10, 1), False) == 'regular'
