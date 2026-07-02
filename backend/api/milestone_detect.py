"""마일스톤 순수 판정 로직 (DB-free, 테스트 대상)."""

_CYCLE = {'single', 'double', 'triple', 'hr'}
_HIT_CLASSES = {'single', 'double', 'triple', 'hr'}


def is_cycle(result_classes) -> bool:
    """한 타자의 한 경기 result_class 집합이 사이클(단·2·3루타·홈런) 포함."""
    return _CYCLE.issubset(set(result_classes))


def walkoff_type(result_class: str, is_hit: bool):
    """끝내기 결승타 유형. 홈런/안타류만(볼넷·희생·실책 끝내기는 제외)."""
    if result_class == 'hr':
        return 'walkoff_hr'
    if is_hit and result_class in _HIT_CLASSES:
        return 'walkoff_hit'
    return None


def crossed(prev: int, curr: int, thresholds) -> list:
    """prev < t <= curr 인 임계값들(이번 경기로 통과)."""
    return [t for t in thresholds if prev < t <= curr]


def dual_crossed(prev_a: int, curr_a: int, prev_b: int, curr_b: int, k: int) -> bool:
    """20-20류: 오늘 이전엔 미완성이고 오늘 포함 시 둘 다 k 도달."""
    return (prev_a < k or prev_b < k) and curr_a >= k and curr_b >= k


def format_milestone_title(emoji: str, name: str, month_str: str, cat: str,
                           value, unit: str, extra_str: str) -> str:
    """마일스톤 알림 제목. unit='' & value<=1 이면 value 생략(바이너리 이벤트 문구 정리)."""
    try:
        v = int(value)
    except (TypeError, ValueError):
        v = value
    val_part = '' if (unit == '' and isinstance(v, int) and v <= 1) else f'{v}{unit}'
    val_sep = ' ' if val_part else ''
    return f'{emoji} {name} {month_str}{cat}{val_sep}{val_part}!{extra_str}'


def career_thresholds_100(base_round, start: int, end: int) -> list:
    """라운드 임계 + [start, end] 100단위 병합(정렬·중복제거)."""
    s = set(base_round)
    s.update(range(start, end + 1, 100))
    return sorted(s)
