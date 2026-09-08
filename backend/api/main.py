from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse, ORJSONResponse
from api.routers import games, players, teams, auth, user, stadiums, widget, community, calendar, phone, email_verify, password_reset, search, news, prediction, app_config, admin, historical, futures
from fastapi.staticfiles import StaticFiles
import time
import threading
from collections import defaultdict, deque
from api.log_setup import setup_logging
from api.paths import STATIC_DIR

setup_logging()

_ALLOWED_ORIGINS = [
    "https://playball.duckdns.org",
]
_LOCAL_ORIGIN_RE = r"^http://(localhost|127\.0\.0\.1)(:\d+)?$"

app = FastAPI(
    title="PlayBall API",
    description="KBO 야구 정보 API",
    version="1.0.0",
    docs_url=None,   # 프로덕션 Swagger UI 비활성화
    redoc_url=None,
    default_response_class=ORJSONResponse,  # orjson 직렬화 (대형 JSON 3-10x)
)

_MAX_BODY = 10 * 1024 * 1024  # 10MB (파일업로드 고려)

# ─── IP별 요청 속도 제한 (Rate Limiting) ────────────────────────────────────
# 목적: 단일 클라이언트(버그·악성봇)의 폭주로 서버 전체 마비 방지
# 임계값: 분당 200회 — 정상 앱 사용자는 절대 도달 불가 (탭 전환 최대 수십 회)
# 동시접속 1000명 이상 환경에서 소수 악성 클라이언트 차단용
# 삭제 금지: 임계값만 올리거나, 특정 path를 whitelist에 추가할 것
_rate_store: dict[str, deque] = defaultdict(deque)
_rate_lock = threading.Lock()
_RATE_LIMIT = 200       # 분당 최대 요청 수
_RATE_WINDOW = 60       # 슬라이딩 윈도우 (초)
_RATE_WHITELIST = {"/health", "/"}   # 헬스체크는 제외

# 민감 엔드포인트 추가 강화 (분당) — 무차별 대입(credential stuffing) + 인증메일 발송 남용 차단
# 글로벌 200/min로는 로그인 200회 시도/분 허용 → 너무 느슨. prefix match.
_SENSITIVE_LIMITS = [
    ("/auth/login", 10),
    ("/auth/register", 10),
    ("/auth/password/", 5),
    ("/user/email/", 5),     # send-code + verify (코드 brute-force 방어)
    ("/user/phone/", 5),     # send-code + verify
    ("/auth/check-", 30),    # 이메일/닉네임 enumeration 완화
]
_sensitive_store: dict[str, deque] = defaultdict(deque)
_MAX_RATE_KEYS = 10_000


def _prune_rate_stores(now: float) -> None:
    for store in (_rate_store, _sensitive_store):
        if len(store) <= _MAX_RATE_KEYS:
            continue
        expired = [key for key, values in store.items()
                   if not values or now - values[-1] > _RATE_WINDOW]
        for key in expired:
            store.pop(key, None)


@app.middleware("http")
async def limit_body_size(request: Request, call_next):
    content_length = request.headers.get("content-length")
    if content_length:
        try:
            if int(content_length) > _MAX_BODY:
                return JSONResponse(status_code=413, content={"detail": "요청 크기 초과"})
        except ValueError:
            return JSONResponse(status_code=400, content={"detail": "잘못된 Content-Length"})
    return await call_next(request)


def _client_ip(request: Request) -> str:
    # nginx가 X-Real-IP=실제 클라이언트로 설정. 8000은 127.0.0.1만 ACCEPT(외부 REJECT)라
    # 헤더 스푸핑 불가 → 신뢰 가능. 미사용 시 client.host는 항상 nginx(127.0.0.1)라 per-IP 무력화.
    xri = request.headers.get("x-real-ip")
    if xri:
        return xri.strip()
    xff = request.headers.get("x-forwarded-for")
    if xff:
        return xff.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


@app.middleware("http")
async def rate_limit(request: Request, call_next):
    if request.url.path in _RATE_WHITELIST:
        return await call_next(request)

    ip = _client_ip(request)
    now = time.time()

    with _rate_lock:
        _prune_rate_stores(now)
        dq = _rate_store[ip]
        # 윈도우 밖 타임스탬프 제거
        while dq and now - dq[0] > _RATE_WINDOW:
            dq.popleft()
        if len(dq) >= _RATE_LIMIT:
            return JSONResponse(
                status_code=429,
                content={"detail": "요청이 너무 많습니다. 잠시 후 다시 시도해주세요."},
            )
        dq.append(now)

        # 민감 경로 추가 제한
        for prefix, limit in _SENSITIVE_LIMITS:
            if request.url.path.startswith(prefix):
                sdq = _sensitive_store[f"{prefix}:{ip}"]
                while sdq and now - sdq[0] > _RATE_WINDOW:
                    sdq.popleft()
                if len(sdq) >= limit:
                    return JSONResponse(
                        status_code=429,
                        content={"detail": "요청이 너무 많습니다. 잠시 후 다시 시도해주세요."},
                    )
                sdq.append(now)
                break

    return await call_next(request)


# ETag/304 — GET 200 응답 바디 해시. 클라(30s 폴링)가 If-None-Match 보내면
# 변화 없을 때 304 헤더만 반환 (풀바디 재전송 대역 절감 — 성능 백로그 06-13).
# add 순서: GZip보다 먼저 add = 스택 안쪽 = 압축 전 원본 바디 기준 해시.
import hashlib as _hashlib
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response as _StarletteResponse


class _ETagMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)
        if request.method != "GET" or response.status_code != 200:
            return response
        content_type = response.headers.get("content-type", "")
        content_length = response.headers.get("content-length")
        try:
            response_size = int(content_length) if content_length is not None else None
        except ValueError:
            response_size = None
        if (not content_type.startswith("application/json")
                or response_size is None
                or response_size > 2 * 1024 * 1024):
            return response
        body = b"".join([chunk async for chunk in response.body_iterator])
        etag = f'W/"{_hashlib.md5(body).hexdigest()}"'
        if request.headers.get("if-none-match") == etag:
            return _StarletteResponse(status_code=304, headers={"ETag": etag})
        headers = dict(response.headers)
        headers["ETag"] = etag
        headers.pop("content-length", None)  # 재계산 위임
        return _StarletteResponse(
            content=body,
            status_code=response.status_code,
            headers=headers,
            media_type=response.media_type,
        )


# DAU 기록 — 인증 요청의 user_id 일별 적재 (관리자 통계, 06-13. 무음 실패)
from api.dau import record_from_auth_header


class _DauMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        record_from_auth_header(request.headers.get("authorization"))
        return await call_next(request)


app.add_middleware(_DauMiddleware)
app.add_middleware(_ETagMiddleware)
app.add_middleware(GZipMiddleware, minimum_size=500)
app.add_middleware(
    CORSMiddleware,
    allow_origins=_ALLOWED_ORIGINS,
    allow_origin_regex=_LOCAL_ORIGIN_RE,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Admin-Key"],
    allow_credentials=True,
)

# 라우터 등록
app.include_router(auth.router, prefix="/auth", tags=["회원"])
app.include_router(games.router, prefix="/games", tags=["경기"])
app.include_router(players.router, prefix="/players", tags=["선수"])
app.include_router(teams.router, prefix="/teams", tags=["팀"])
app.include_router(user.router, prefix="/user", tags=["유저"])
app.include_router(stadiums.router, prefix="/stadiums", tags=["경기장"])
app.include_router(widget.router, prefix="/widget", tags=["위젯"])
app.include_router(community.router, prefix="/community", tags=["커뮤니티"])
app.include_router(calendar.router, prefix="/calendar", tags=["캘린더"])
app.include_router(phone.router, prefix="/user/phone", tags=["전화인증"])
app.include_router(email_verify.router, prefix="/user/email", tags=["이메일인증"])
app.include_router(password_reset.router, prefix="/auth/password", tags=["비밀번호재설정"])
app.include_router(search.router, prefix="/search", tags=["검색"])
app.include_router(app_config.router, tags=["설정"])
app.include_router(admin.router, tags=["관리자"])  # 콘솔 UI = /static/admin/index.html
app.include_router(news.router)
app.include_router(prediction.router)
from api.routers import allstar
app.include_router(allstar.router, prefix="/allstar", tags=["올스타"])
from api.routers import share
app.include_router(share.router, tags=["공유 랜딩"])
from api.routers import bootstrap
app.include_router(bootstrap.router, tags=["부트스트랩"])
app.include_router(historical.router, prefix="/historical", tags=["역대"])
app.include_router(futures.router, prefix="/futures", tags=["퓨처스(2군)"])
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


@app.get("/")
def root():
    return {"message": "PlayBall API 서버 정상 작동 중!"}

@app.get("/health")
def health_check():
    return {"status": "ok"}
