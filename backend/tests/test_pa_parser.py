"""PA 파서 순수 로직 회귀 테스트 (DB 불요).

guard 대상:
- classify_result 분기 순서 (CLAUDE.md: 순서 의존 — '삼진 아웃'=so, '땅볼로 출루'=reach_other)
- parse_game_pas의 type=23 홈런 흡수 (회귀: 23 무시 시 홈런 타석 증발 → 2024 hr=0 사고)
"""
from api.pa_parser import classify_result, parse_game_pas


def test_classify_hits():
    assert classify_result("좌익수 앞 1루타") == ("single", True)
    assert classify_result("중월 홈런") == ("hr", True)
    assert classify_result("우중간 2루타") == ("double", True)
    assert classify_result("좌중간 3루타") == ("triple", True)
    assert classify_result("내야안타") == ("single", True)


def test_classify_branch_order():
    # '삼진 아웃' — '아웃' 단어 있어도 삼진 우선
    assert classify_result("삼진 아웃")[0] == "so"
    # '실책' 키워드가 '출루'보다 먼저 매칭
    assert classify_result("3루수 실책으로 출루")[0] == "error"
    # 순수 '땅볼로 출루' (실책/야선 키워드 없음) = reach_other
    assert classify_result("유격수 땅볼로 출루")[0] == "reach_other"
    # 땅볼 + 아웃 = out
    assert classify_result("2루수 땅볼 아웃")[0] == "out"
    assert classify_result("볼넷")[0] == "bb"
    assert classify_result("몸에 맞는 볼")[0] == "hbp"
    assert classify_result("희생플라이")[0] == "sac_fly"
    assert classify_result("고의4구")[0] == "ibb"


def _row(inning, half, seqno, rtype, batter, pitcher, title):
    """parse_game_pas가 기대하는 16-튜플 (컨텍스트 컬럼은 0/false/None)."""
    return (inning, half, seqno, rtype, batter, pitcher, title,
            0, 0, 0, False, False, False, 0, 0, None)


def test_type23_homerun_captured():
    """홈런이 type 13 없이 type 23으로만 발행돼도 PA로 잡혀야 한다."""
    rows = [
        _row(1, "말", 1, 8, "김도영", "투수A", "1번타자 김도영"),
        _row(1, "말", 2, 1, "김도영", "투수A", "스트라이크"),
        _row(1, "말", 3, 23, "김도영", "투수A", "김도영 중월 홈런"),
        _row(1, "말", 4, 8, "최형우", "투수A", "2번타자 최형우"),
        _row(1, "말", 5, 13, "최형우", "투수A", "유격수 땅볼 아웃"),
    ]
    pas = parse_game_pas(rows)
    hrs = [p for p in pas if p["result_class"] == "hr"]
    assert len(hrs) == 1
    assert hrs[0]["batter_name"] == "김도영"
    assert hrs[0]["is_hit"] is True
    # 다음 타자도 별도 타석으로 분리 (홈런이 다음 타자를 삼키지 않음)
    assert any(p["batter_name"] == "최형우" for p in pas)


def test_type23_batter_mismatch_ignored():
    """늦은 하이라이트(타자명 불일치) 23은 무시 — 잘못된 타석 종료 방지."""
    rows = [
        _row(1, "말", 1, 8, "타자B", "투수A", "1번타자 타자B"),
        _row(1, "말", 2, 1, "타자B", "투수A", "스트라이크"),
        _row(1, "말", 3, 23, "딴사람", "투수A", "딴사람 중월 홈런"),  # 불일치
        _row(1, "말", 4, 13, "타자B", "투수A", "볼넷"),
    ]
    pas = parse_game_pas(rows)
    assert len(pas) == 1
    assert pas[0]["batter_name"] == "타자B"
    assert pas[0]["result_class"] == "bb"
