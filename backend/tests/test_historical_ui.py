from api.routers.historical import _ip_to_outs, _outs_to_ip, _aggregate_career


def test_ip_outs_roundtrip():
    # KBO 표기 6.1 = 6⅓이닝 = 19 아웃, 6.2 = 6⅔ = 20
    assert _ip_to_outs(6.1) == 19
    assert _ip_to_outs(6.2) == 20
    assert _ip_to_outs(7.0) == 21
    assert _outs_to_ip(19) == 6.1
    assert _outs_to_ip(20) == 6.2
    assert _outs_to_ip(21) == 7.0


def test_aggregate_career_batter():
    rows = [
        {"player_type": "타자", "at_bats": 100, "hits": 30, "doubles": 5,
         "triples": 1, "home_runs": 4, "walks": 10, "hbp": 2, "sac_flies": 1,
         "rbis": 20, "runs": 18, "strikeouts": 15, "stolen_bases": 3},
        {"player_type": "타자", "at_bats": 200, "hits": 50, "doubles": 8,
         "triples": 0, "home_runs": 10, "walks": 20, "hbp": 3, "sac_flies": 2,
         "rbis": 40, "runs": 35, "strikeouts": 30, "stolen_bases": 5},
    ]
    c = _aggregate_career(rows)
    assert c["at_bats"] == 300
    assert c["hits"] == 80
    assert c["home_runs"] == 14
    assert c["avg"] == round(80 / 300, 3)
    # tb = hits + doubles + 2*triples + 3*hr = 80 + 13 + 2 + 42 = 137
    assert c["slg"] == round(137 / 300, 3)


def test_aggregate_career_pitcher():
    rows = [
        {"player_type": "투수", "innings_pitched": 6.1, "earned_runs": 2,
         "hits_allowed": 5, "walks_allowed": 1, "strikeouts_pitched": 7,
         "wins": 1, "losses": 0, "saves": 0, "holds": 0},
        {"player_type": "투수", "innings_pitched": 6.2, "earned_runs": 3,
         "hits_allowed": 6, "walks_allowed": 2, "strikeouts_pitched": 5,
         "wins": 0, "losses": 1, "saves": 0, "holds": 0},
    ]
    c = _aggregate_career(rows)
    # outs 19+20=39 → 13.0 이닝
    assert c["innings_pitched"] == 13.0
    assert c["wins"] == 1
    assert c["strikeouts_pitched"] == 12
    # era = 5*9 / 13.0
    assert c["era"] == round(5 * 9 / 13.0, 2)
