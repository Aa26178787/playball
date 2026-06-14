"""1군 등록현황 diff 순수 판정 테스트 (DB/크롤 불요)."""
from crawler.roster_diff import classify_roster_diff


def test_departed():
    out = classify_roster_diff(
        registered={'김선수'},
        db_players=[
            {'name': '문동주', 'had_1gun': True, 'latest': None},
            {'name': '김선수', 'had_1gun': True, 'latest': None},
        ])
    assert ('문동주', '등록말소') in out
    assert all(n != '김선수' for n, _ in out)


def test_returned():
    out = classify_roster_diff(
        registered={'문동주'},
        db_players=[{'name': '문동주', 'had_1gun': True, 'latest': '등록말소'}])
    assert ('문동주', '1군등록') in out


def test_no_1gun_skipped():
    out = classify_roster_diff(
        registered=set(),
        db_players=[{'name': '유망주', 'had_1gun': False, 'latest': None}])
    assert out == []


def test_already_marked_no_dup():
    out = classify_roster_diff(
        registered=set(),
        db_players=[{'name': '문동주', 'had_1gun': True, 'latest': '등록말소'}])
    assert out == []
