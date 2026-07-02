from api.milestone_detect import max_consecutive_hr, all_meet


def test_max_consecutive_hr():
    assert max_consecutive_hr(['hr', 'hr', 'hr']) == 3
    assert max_consecutive_hr(['single', 'hr', 'hr', 'out', 'hr']) == 2
    assert max_consecutive_hr(['hr', 'so', 'hr', 'hr', 'hr', 'hr']) == 4
    assert max_consecutive_hr(['single', 'double']) == 0
    assert max_consecutive_hr([]) == 0


def test_all_meet():
    assert all_meet([1, 2, 1, 1, 3, 1, 2, 1, 1], 9)          # 9명 전원 >=1
    assert not all_meet([1, 2, 0, 1, 1, 1, 1, 1, 1], 9)      # 한 명 0
    assert not all_meet([1, 1, 1], 9)                        # 9명 미만
    assert not all_meet([], 9)
    assert all_meet([2, 3], 2)
