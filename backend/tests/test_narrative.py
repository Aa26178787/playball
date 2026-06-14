"""내러티브 엔진 순수 로직 테스트 (DB 불요)."""
from api.narrative import game_review, live_caption, mvp_line


def test_review_walkoff():
    s = game_review({"home_team": "LG", "away_team": "KT",
                     "home_score": 5, "away_score": 4, "walkoff": True})
    assert "LG" in s and "끝내기" in s and "5-4" in s


def test_review_extra_innings():
    s = game_review({"home_team": "두산", "away_team": "NC",
                     "home_score": 3, "away_score": 6, "extra_innings": True})
    assert "NC" in s and "연장" in s


def test_review_blowout():
    s = game_review({"home_team": "삼성", "away_team": "한화",
                     "home_score": 13, "away_score": 2})
    assert "삼성" in s and "대승" in s


def test_review_close():
    s = game_review({"home_team": "KIA", "away_team": "롯데",
                     "home_score": 2, "away_score": 1})
    assert "KIA" in s and ("진땀" in s or "1" in s)


def test_review_draw():
    s = game_review({"home_team": "SSG", "away_team": "키움",
                     "home_score": 3, "away_score": 3})
    assert "무승부" in s


def test_review_appends_mvp():
    s = game_review({"home_team": "LG", "away_team": "KT",
                     "home_score": 7, "away_score": 3,
                     "mvp_name": "오지환", "mvp_line": "3안타 2타점"})
    assert "오지환" in s and "3안타 2타점" in s


def test_review_missing_fields_safe():
    assert isinstance(game_review({}), str)


def test_caption_bases_loaded():
    s = live_caption({"inning": 8, "half": "말", "out": 2,
                      "base1": True, "base2": True, "base3": True,
                      "home_score": 4, "away_score": 5})
    assert "8회말" in s and "2사" in s and "만루" in s


def test_caption_tie():
    s = live_caption({"inning": 9, "half": "초", "out": 0,
                      "base1": False, "base2": False, "base3": False,
                      "home_score": 2, "away_score": 2})
    assert "동점" in s


def test_caption_out_of_game_empty():
    assert live_caption({}) == ""
    assert live_caption({"inning": 0}) == ""


def test_mvp_line_formats():
    assert mvp_line({"hits": 3, "home_runs": 1, "rbis": 4}) != ""
    assert isinstance(mvp_line({}), str)
