"""
OpenWeatherMap 날씨 서비스
- 구장별 좌표로 현재/예보 날씨 조회
- 5분 캐시 (과도한 API 호출 방지)
"""
import os
import threading
import time
import logging
import requests

API_KEY = os.environ.get('OPENWEATHER_API_KEY', '')
logger = logging.getLogger(__name__)
BASE_URL = 'https://api.openweathermap.org/data/2.5'

# stadium_id → (lat, lon, 실내여부)
STADIUM_COORDS = {
    1: (37.5121, 127.0715, False),   # 잠실 (LG/두산)
    2: (37.4981, 126.8672, True),    # 고척 (키움, 실내)
    3: (37.2998, 127.0100, False),   # 수원 (KT)
    4: (37.4368, 126.6936, False),   # 인천 (SSG)
    5: (36.3170, 127.4291, False),   # 대전 (한화)
    6: (35.1677, 126.8898, False),   # 광주 (KIA)
    7: (35.8418, 128.6811, False),   # 대구 (삼성)
    8: (35.2228, 128.5826, False),   # 창원 (NC)
    9: (35.1940, 129.0610, False),   # 사직 (롯데)
}

# 날씨 아이콘 코드 → 이모지
ICON_MAP = {
    '01': '☀️',   # clear sky
    '02': '🌤️',  # few clouds
    '03': '⛅',   # scattered clouds
    '04': '☁️',  # broken clouds
    '09': '🌧️',  # shower rain
    '10': '🌦️',  # rain
    '11': '⛈️',  # thunderstorm
    '13': '❄️',  # snow
    '50': '🌫️',  # mist
}

# 캐시: {stadium_id: (timestamp, data)}
_cache: dict = {}
CACHE_TTL = 300  # 5분

# stale-while-revalidate — 요청 스레드 블로킹 금지 (cold 시 구장 5곳 × 5s timeout = 홈 5초+ 지연 원인)
_refreshing: set = set()
_refresh_lock = threading.Lock()


def _spawn(key, fetch_fn):
    """백그라운드 1회 갱신 (동일 key 중복 spawn 방지)"""
    with _refresh_lock:
        if key in _refreshing:
            return
        _refreshing.add(key)

    def run():
        try:
            fetch_fn()
        except Exception as e:
            logger.warning(f'[Weather] 백그라운드 갱신 실패 {key}: {e}')
        finally:
            with _refresh_lock:
                _refreshing.discard(key)

    threading.Thread(target=run, daemon=True).start()


def _icon_emoji(icon_code: str) -> str:
    return ICON_MAP.get(icon_code[:2], '🌡️')


def get_weather(stadium_id: int) -> dict | None:
    """구장 현재 날씨 조회 (5분 캐시)"""
    if not API_KEY:
        return None
    coords = STADIUM_COORDS.get(stadium_id)
    if not coords:
        return None
    lat, lon, is_indoor = coords
    if is_indoor:
        return {'indoor': True}

    now = time.time()
    cached = _cache.get(stadium_id)
    if cached and now - cached[0] < CACHE_TTL:
        return cached[1]

    def fetch():
        resp = requests.get(f'{BASE_URL}/weather', params={
            'lat': lat, 'lon': lon,
            'appid': API_KEY,
            'units': 'metric',
            'lang': 'kr',
        }, timeout=5)
        resp.raise_for_status()
        _cache[stadium_id] = (time.time(), _parse_current(resp.json()))

    # 만료/부재 → 백그라운드 갱신 spawn, 즉시 stale(or None) 반환 (요청 비블로킹)
    _spawn(f'w{stadium_id}', fetch)
    return cached[1] if cached else None


def get_forecast_at(stadium_id: int, target_hour_kst: int) -> dict | None:
    """경기 시작 시각 근처 예보 조회 (target_hour_kst: 0~23 KST 시)"""
    if not API_KEY:
        return None
    coords = STADIUM_COORDS.get(stadium_id)
    if not coords:
        return None
    lat, lon, is_indoor = coords
    if is_indoor:
        return {'indoor': True}

    cache_key = f'{stadium_id}_fc'
    now = time.time()
    cached = _cache.get(cache_key)

    def fetch():
        resp = requests.get(f'{BASE_URL}/forecast', params={
            'lat': lat, 'lon': lon,
            'appid': API_KEY,
            'units': 'metric',
            'lang': 'kr',
            'cnt': 40,  # 5일치 (3시간 간격 × 40 = 120h)
        }, timeout=5)
        resp.raise_for_status()
        _cache[cache_key] = (time.time(), resp.json().get('list', []))

    if cached and now - cached[0] < CACHE_TTL:
        fc_list = cached[1]
    else:
        # 비블로킹 — stale 사용, 백그라운드 갱신 (없으면 None)
        _spawn(cache_key, fetch)
        if not cached:
            return None
        fc_list = cached[1]

    # target_hour_kst에 가장 가까운 예보 선택
    best = None
    best_diff = 999
    for item in fc_list:
        # dt는 UTC unix timestamp
        import datetime
        kst_hour = (datetime.datetime.utcfromtimestamp(item['dt'])
                    + datetime.timedelta(hours=9)).hour
        diff = abs(kst_hour - target_hour_kst)
        if diff < best_diff:
            best_diff = diff
            best = item

    return _parse_current(best) if best else None


# ── 백그라운드 워머: 전 구장 현재+예보 4분 주기 프리페치 ──────────────────────
# SWR 도입 후 cold 첫 응답이 None → 예정 경기 날씨 유무 불일치 발생 → 항상 warm 유지
def _warm_loop():
    time.sleep(5)  # 부팅 직후 여유
    while True:
        for sid in STADIUM_COORDS:
            try:
                get_weather(sid)
            except Exception:
                pass
            try:
                get_forecast_at(sid, 18)
            except Exception:
                pass
        time.sleep(240)  # TTL(300) 미만 — 캐시 항상 신선


if API_KEY:
    threading.Thread(target=_warm_loop, daemon=True).start()


def _parse_current(d: dict) -> dict:
    weather = d.get('weather', [{}])[0]
    main = d.get('main', {})
    wind = d.get('wind', {})
    rain = d.get('rain', {})
    icon_code = weather.get('icon', '01d')
    return {
        'indoor': False,
        'temp': round(main.get('temp', 0)),
        'feels_like': round(main.get('feels_like', 0)),
        'humidity': main.get('humidity', 0),
        'description': weather.get('description', ''),
        'icon': icon_code,
        'emoji': _icon_emoji(icon_code),
        'wind_speed': round(wind.get('speed', 0), 1),
        'rain_1h': rain.get('1h', 0),
        'pop': round(d.get('pop', 0) * 100) if 'pop' in d else None,  # 강수확률 (예보만)
    }
