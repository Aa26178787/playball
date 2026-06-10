"""앱 원격 설정 — 강제 업데이트 게이트 + 기능 킬스위치 + 공지 배너 + 시즌 단계

값 변경은 psql로:
  UPDATE app_config SET value = '"1.2.0"' WHERE key = 'min_version';
  UPDATE app_config SET value = '{"prediction": false}' WHERE key = 'kill_switches';
  UPDATE app_config SET value = '{"message": "점검 안내", "level": "info"}' WHERE key = 'banner';
변경 후 최대 60초(캐시 TTL) 내 전파.
"""
from fastapi import APIRouter
from database.connection import get_connection
from api.cache import cached

router = APIRouter()

_DEFAULTS = {
    'min_version': '1.0.0',      # 이 미만 버전 = 강제 업데이트
    'latest_version': '1.0.0',   # 권장 업데이트 안내용
    'kill_switches': {},         # {"prediction": false, "community": false ...} false=비활성
    'banner': None,              # {"message": str, "level": "info|warn", "url": str|null} or null
    'season_phase': 'regular',   # preseason | regular | postseason | offseason
}


@router.get('/app-config')
@cached(60)
def get_app_config():
    cfg = dict(_DEFAULTS)
    conn = get_connection()
    if conn:
        try:
            cur = conn.cursor()
            cur.execute('SELECT key, value FROM app_config')
            for key, value in cur.fetchall():
                if key in cfg:
                    cfg[key] = value
            cur.close()
        finally:
            conn.close()
    return cfg
