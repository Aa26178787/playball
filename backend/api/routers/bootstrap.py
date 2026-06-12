"""홈 부트스트랩 — 홈 첫 페인트에 필요한 응답 묶음 1콜 (성능 묶음 06-13).

홈 진입 burst(개별 GET 다발)를 1 RTT로 — LTE에서 체감 최대.
각 조각은 기존 라우트 함수 재사용 (@cached 그대로 통과 = 캐시 공유).
비우선 데이터(등록말소/내일경기/선수목록 프리페치)는 기존 지연 로딩 유지.
"""
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter

from api.cache import cached

router = APIRouter()


@router.get("/home/bootstrap")
@cached(20)
def home_bootstrap():
    from api.routers.app_config import get_app_config
    from api.routers.calendar import get_calendar
    from api.routers.games import get_today_games
    from api.routers.teams import get_team_rankings

    now_kst = datetime.now(timezone.utc) + timedelta(hours=9)
    out = {}
    # 조각별 독립 — 하나 실패해도 나머지는 제공 (클라가 누락 키만 개별 폴백)
    for key, fn in (
        ("today", lambda: get_today_games()),
        ("rankings", lambda: get_team_rankings("full")),
        ("calendar", lambda: get_calendar(now_kst.year, now_kst.month)),
        ("config", lambda: get_app_config()),
    ):
        try:
            out[key] = fn()
        except Exception:
            out[key] = None
    return out
