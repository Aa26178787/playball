"""1군 등록현황 diff 순수 판정 테스트 (DB/크롤 불요)."""
from crawler.roster_diff import classify_roster_diff


def test_departed_stale():
    # 1군 활동 + 등록부재 + 장기 미출전 → 등록말소
    out = classify_roster_diff(
        registered={'김선수'},
        db_players=[
            {'name': '문동주', 'had_1gun': True, 'latest': None, 'days_since_last': 40},
            {'name': '김선수', 'had_1gun': True, 'latest': None, 'days_since_last': 1},
        ])
    assert ('문동주', '등록말소') in out
    assert all(n != '김선수' for n, _ in out)


def test_recent_play_not_flagged():
    # 등록부재여도 최근(3일전) 출전했으면 말소 안 함 (크롤 누락·휴식 방어)
    out = classify_roster_diff(
        registered=set(),
        db_players=[{'name': '강민호', 'had_1gun': True, 'latest': None, 'days_since_last': 3}])
    assert out == []


def test_returned():
    out = classify_roster_diff(
        registered={'문동주'},
        db_players=[{'name': '문동주', 'had_1gun': True, 'latest': '등록말소', 'days_since_last': 40}])
    assert ('문동주', '1군등록') in out


def test_no_1gun_skipped():
    out = classify_roster_diff(
        registered=set(),
        db_players=[{'name': '유망주', 'had_1gun': False, 'latest': None, 'days_since_last': 99}])
    assert out == []


def test_already_marked_no_dup():
    out = classify_roster_diff(
        registered=set(),
        db_players=[{'name': '문동주', 'had_1gun': True, 'latest': '등록말소', 'days_since_last': 40}])
    assert out == []
