from api.milestone_detect import (
    is_cycle, walkoff_type, crossed, dual_crossed,
    format_milestone_title, career_thresholds_100,
)


def test_is_cycle():
    assert is_cycle({'single', 'double', 'triple', 'hr'})
    assert is_cycle({'single', 'double', 'triple', 'hr', 'bb', 'out'})
    assert not is_cycle({'single', 'double', 'hr'})       # 3루타 없음
    assert not is_cycle(set())


def test_walkoff_type():
    assert walkoff_type('hr', True) == 'walkoff_hr'
    assert walkoff_type('single', True) == 'walkoff_hit'
    assert walkoff_type('double', True) == 'walkoff_hit'
    assert walkoff_type('bb', False) is None              # 볼넷 끝내기 = 안타 아님(제외)
    assert walkoff_type('out', False) is None


def test_crossed():
    assert crossed(998, 1002, [500, 1000, 1500]) == [1000]
    assert crossed(1499, 1501, [1000, 1100, 1500]) == [1500]
    assert crossed(1000, 1000, [1000]) == []             # 통과 아님(이미 도달)
    assert crossed(90, 250, [100, 200, 300]) == [100, 200]  # 한 경기 다중 통과


def test_dual_crossed():
    # 오늘 이전 미완성(hr 19), 오늘 20 도달 + sb 이미 25 → 20-20 완성
    assert dual_crossed(19, 20, 25, 26, 20)
    # 오늘 이전 이미 둘 다 20+ → 완성 아님(이전에 이미)
    assert not dual_crossed(20, 21, 22, 23, 20)
    # curr 한쪽 미달
    assert not dual_crossed(19, 20, 18, 19, 20)


def test_format_milestone_title():
    # value=1·unit='' → value 생략
    assert format_milestone_title('🎉', '강백호', '', '끝내기 홈런', 1, '', '') == '🎉 강백호 끝내기 홈런!'
    # value 있는 카운트형
    assert format_milestone_title('💣', '노시환', '', '한 경기', 3, '홈런', '') == '💣 노시환 한 경기 3홈런!'
    # extra_str 캡션
    assert format_milestone_title('✨', '강백호', '', '통산', 1100, '안타', ' (역대 113번째)') == '✨ 강백호 통산 1100안타! (역대 113번째)'


def test_career_thresholds_100():
    assert career_thresholds_100([500, 1000], 1000, 2500) == \
        [500, 1000, 1100, 1200, 1300, 1400, 1500, 1600, 1700, 1800, 1900,
         2000, 2100, 2200, 2300, 2400, 2500]
