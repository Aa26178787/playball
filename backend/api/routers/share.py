"""공유 랜딩 페이지 (메가C 성장 루프) — og 메타 + 웹앱 유도.

카카오톡/트위터 등에 링크 공유 시 미리보기(og:image)가 뜨고,
미설치/미접속자는 '웹앱에서 보기' 버튼으로 /app/ 유입.
경로: /s/p/{player_id} (선수) · /s/g/{game_id} (경기)
"""
from fastapi import APIRouter
from fastapi.responses import HTMLResponse
from database.connection import get_connection

router = APIRouter()

_BASE = "https://playball.duckdns.org"


def _page(title: str, desc: str, image: str, app_path: str = "") -> str:
    return f"""<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} — PlayBall</title>
<meta property="og:title" content="{title}">
<meta property="og:description" content="{desc}">
<meta property="og:image" content="{image}">
<meta property="og:type" content="website">
<meta name="twitter:card" content="summary">
<style>
  body {{ margin:0; font-family:-apple-system,'Apple SD Gothic Neo','Noto Sans KR',sans-serif;
        background:#0f0f12; color:#fff; display:flex; align-items:center; justify-content:center;
        min-height:100vh; text-align:center; }}
  .card {{ padding:36px 28px; max-width:340px; }}
  img.p {{ width:96px; height:96px; border-radius:50%; object-fit:cover; background:#26262c; }}
  h1 {{ font-size:22px; margin:16px 0 6px; }}
  p {{ font-size:14px; color:#9a9aa0; margin:0 0 26px; line-height:1.5; }}
  a.btn {{ display:inline-block; background:#2563eb; color:#fff; text-decoration:none;
        padding:14px 30px; border-radius:999px; font-weight:800; font-size:15px; }}
  .brand {{ margin-top:28px; font-size:12px; color:#6b6b73; font-weight:700; }}
</style>
</head>
<body>
<div class="card">
  <img class="p" src="{image}" alt="" onerror="this.style.display='none'">
  <h1>{title}</h1>
  <p>{desc}</p>
  <a class="btn" href="{_BASE}/app/{app_path}">⚾ PlayBall에서 보기</a>
  <div class="brand">PlayBall — KBO 라이브 야구</div>
</div>
</body>
</html>"""


@router.get("/s/p/{player_id}", response_class=HTMLResponse)
def share_player(player_id: int):
    conn = get_connection()
    name, team, img, ptype = "선수", "", "", ""
    if conn:
        try:
            cur = conn.cursor()
            cur.execute("""
                SELECT p.name, COALESCE(t.name, ''), COALESCE(p.profile_image, ''),
                       COALESCE(p.player_type, '')
                FROM players p LEFT JOIN teams t ON t.id = p.team_id
                WHERE p.id = %s
            """, (player_id,))
            row = cur.fetchone()
            if row:
                name, team, img, ptype = row
            cur.close()
        finally:
            conn.close()
    title = name
    desc = f"{team} {ptype}".strip() + " — 시즌 기록·존 히트맵·맞대결까지 PlayBall에서"
    image = img if img.startswith("http") else (f"{_BASE}{img}" if img else f"{_BASE}/static/icon.png")
    return _page(title, desc, image)


@router.get("/s/g/{game_id}", response_class=HTMLResponse)
def share_game(game_id: int):
    conn = get_connection()
    title, desc = "KBO 경기", "라이브 문자중계·필드뷰·승률 그래프"
    if conn:
        try:
            cur = conn.cursor()
            cur.execute("""
                SELECT ht.name, at.name, g.game_date, g.status,
                       COALESCE(g.home_score, 0), COALESCE(g.away_score, 0)
                FROM games g
                JOIN teams ht ON ht.id = g.home_team_id
                JOIN teams at ON at.id = g.away_team_id
                WHERE g.id = %s
            """, (game_id,))
            row = cur.fetchone()
            if row:
                hn, an, gdate, status, hs, a_s = row
                title = f"{an} vs {hn}"
                if status == '종료':
                    desc = f"{gdate} 최종 {a_s}:{hs} — 전 타석 중계·승률 그래프 PlayBall에서"
                elif status == '진행':
                    desc = f"지금 {a_s}:{hs} 진행 중 — 라이브 필드뷰로 보기"
                else:
                    desc = f"{gdate} 예정 — 선발 매치업·승부예측 PlayBall에서"
            cur.close()
        finally:
            conn.close()
    return _page(title, desc, f"{_BASE}/static/icon.png")
