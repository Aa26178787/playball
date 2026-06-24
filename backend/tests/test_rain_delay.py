"""우천중단 키워드 매칭 순수 테스트 (네트워크/DB 불요)."""
from crawler.naver_crawler import _text_has_suspend


def test_positive_keywords():
    assert _text_has_suspend('서스펜디드 게임 선언')
    assert _text_has_suspend('우천으로 경기가 중단되었습니다')
    assert _text_has_suspend('강우 중단')
    assert _text_has_suspend('우천 중단')
    assert _text_has_suspend('비로 인해 경기 중단')        # '경기 중단' 구문 매칭
    assert _text_has_suspend('1회초 우천 중단 선언 후 그라운드 정비')


def test_strong_signal_combination():
    # '중단' + 우천/강우 동반 = 어순 변형도 흡수
    assert _text_has_suspend('경기 진행 중 우천 사유로 중단')
    assert _text_has_suspend('강우가 거세져 경기 중단')


def test_negatives_no_false_positive():
    assert not _text_has_suspend('')
    assert not _text_has_suspend(None)
    assert not _text_has_suspend('1구 스트라이크')
    assert not _text_has_suspend('홈런! 좌측 담장을 넘어갑니다')
    # '중단' 단독 + 비/우천 무관 → 오탐 금지
    assert not _text_has_suspend('연속 안타 행진이 중단됐다')
    assert not _text_has_suspend('타자의 집중력이 흐트러졌다')
