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


# ── C1: 2군(futures) 구분 ──
def test_demoted_to_2gun():
    # 1군 부재 + 2군 등록 → '2군'(강등, 부상 아님). staleness 불요(positive 증거)
    out = classify_roster_diff(
        registered=set(),
        db_players=[{'name': '한선수', 'had_1gun': True, 'latest': None, 'days_since_last': 3}],
        futures_registered={'한선수'})
    assert ('한선수', '2군') in out


def test_injured_not_in_either():
    # 2군 크롤 성공했는데 어느 군에도 없음 + stale → 등록말소(이탈/부상)
    out = classify_roster_diff(
        registered=set(),
        db_players=[{'name': '부상자', 'had_1gun': True, 'latest': None, 'days_since_last': 40}],
        futures_registered={'다른선수'})
    assert ('부상자', '등록말소') in out


def test_2gun_no_dup():
    out = classify_roster_diff(
        registered=set(),
        db_players=[{'name': '한선수', 'had_1gun': True, 'latest': '2군', 'days_since_last': 5}],
        futures_registered={'한선수'})
    assert out == []


def test_return_from_2gun():
    out = classify_roster_diff(
        registered={'한선수'},
        db_players=[{'name': '한선수', 'had_1gun': True, 'latest': '2군', 'days_since_last': 2}],
        futures_registered=set())
    assert ('한선수', '1군등록') in out


def test_futures_fail_falls_back_to_stale():
    # 2군 크롤 실패(빈 set)면 종전 거동(말소 추론) 유지 — 회귀 방어
    out = classify_roster_diff(
        registered=set(),
        db_players=[{'name': '문동주', 'had_1gun': True, 'latest': None, 'days_since_last': 40}],
        futures_registered=set())
    assert ('문동주', '등록말소') in out
