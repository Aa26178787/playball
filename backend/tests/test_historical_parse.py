"""역대수집 순수 파서 테스트 (DB/크롤 불요)."""
import datetime
from crawler.historical_crawler import _parse_ip, _parse_bio, _safe_int, _safe_float


def test_parse_ip():
    assert _parse_ip('168 1/3') == 168.1   # 6.1 = 6⅓ 관례
    assert _parse_ip('7 2/3') == 7.2
    assert _parse_ip('173') == 173.0
    assert _parse_ip('128 2/3') == 128.2
    assert _parse_ip('-') is None
    assert _parse_ip('') is None
    assert _parse_ip(None) is None


def test_safe_int_float():
    assert _safe_int('1,234') == 1234
    assert _safe_int('-') is None
    assert _safe_int('') is None
    assert _safe_int('5') == 5
    assert _safe_float('0.337') == 0.337
    assert _safe_float('-') is None


def test_parse_bio_full():
    # 양준혁 detail div.player_info li 샘플
    items = [
        '선수명: 양준혁',
        '생년월일: 1969년 05월 26일',
        '포지션: 외야수(좌투좌타)',
        '신장/체중: 188cm/95kg',
        '경력: 남도초-경운중-대구상고-영남대-삼성-해태-LG',
        '지명순위: 93 삼성 1차',
    ]
    b = _parse_bio(items)
    assert b['birth_date'] == datetime.date(1969, 5, 26)
    assert b['position'] == '외야수'
    assert b['throws'] == '좌'
    assert b['bats'] == '좌'
    assert b['height'] == 188
    assert b['weight'] == 95
    assert b['career'].startswith('남도초')
    assert b['draft_info'] == '93 삼성 1차'


def test_parse_bio_righty_pitcher():
    items = ['포지션: 투수(우투우타)', '신장/체중: 180cm/85kg', '생년월일: 1975년 01월 02일']
    b = _parse_bio(items)
    assert b['throws'] == '우'
    assert b['bats'] == '우'
    assert b['position'] == '투수'
    assert b['height'] == 180


def test_parse_bio_missing_fields():
    # 결손 필드는 키 부재 (None 아님) — COALESCE가 기존값 보존
    b = _parse_bio(['선수명: 홍길동'])
    assert 'birth_date' not in b
    assert 'height' not in b
