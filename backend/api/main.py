from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse
from api.routers import games, players, teams, auth, user, stadiums, widget, community, calendar, phone, email_verify, password_reset, search, news
from fastapi.staticfiles import StaticFiles

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


@app.middleware("http")
async def limit_body_size(request: Request, call_next):
    content_length = request.headers.get("content-length")
    if content_length and int(content_length) > _MAX_BODY:
        return JSONResponse(status_code=413, content={"detail": "요청 크기 초과"})
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
app.mount("/static", StaticFiles(directory="/home/ubuntu/playball/backend/static"), name="static")


@app.get("/")
def root():
    return {"message": "PlayBall API 서버 정상 작동 중!"}

@app.get("/health")
def health_check():
    return {"status": "ok"}