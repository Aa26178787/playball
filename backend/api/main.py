from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse
from api.routers import games, players, teams, auth, user, stadiums, widget, community, calendar, phone, email_verify, password_reset, search, news, prediction
from fastapi.staticfiles import StaticFiles
import time
import threading
from collections import defaultdict, deque

_ALLOWED_ORIGINS = [
    "https://playball.duckdns.org",
    "http://localhost",
    "http://10.0.0.0/8",   # 로컬 개발 (ADB over WiFi)
]

app = FastAPI(
    title="PlayBall API",
    description="KBO 야구 정보 API",
    version="1.0.0",
    docs_url=None,   # 프로덕션 Swagger UI 비활성화
    redoc_url=None,
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


@app.middleware("http")
async def limit_body_size(request: Request, call_next):
    content_length = request.headers.get("content-length")
    if content_length and int(content_length) > _MAX_BODY:
        return JSONResponse(status_code=413, content={"detail": "요청 크기 초과"})
    return await call_next(request)


@app.middleware("http")
async def rate_limit(request: Request, call_next):
    if request.url.path in _RATE_WHITELIST:
        return await call_next(request)

    ip = request.client.host if request.client else "unknown"
    now = time.time()

    with _rate_lock:
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

    return await call_next(request)


app.add_middleware(GZipMiddleware, minimum_size=500)
app.add_middleware(
    CORSMiddleware,
    allow_origins=_ALLOWED_ORIGINS,
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
app.include_router(news.router)
app.include_router(prediction.router)
app.mount("/static", StaticFiles(directory="/home/ubuntu/playball/backend/static"), name="static")


@app.get("/")
def root():
    return {"message": "PlayBall API 서버 정상 작동 중!"}

@app.get("/health")
def health_check():
    return {"status": "ok"}