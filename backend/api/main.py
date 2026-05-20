from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from api.routers import games, players, teams, auth, user, stadiums, widget, community


app = FastAPI(
    title="PlayBall API",
    description="KBO 야구 정보 API",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
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


@app.get("/")
def root():
    return {"message": "PlayBall API 서버 정상 작동 중!"}

@app.get("/health")
def health_check():
    return {"status": "ok"}