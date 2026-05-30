from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from typing import Optional
from database.connection import get_connection
from api.routers.auth import get_current_user

router = APIRouter()


class FavoriteTeam(BaseModel):
    team_id: int


class FavoritePlayer(BaseModel):
    player_id: int


class NotificationSettings(BaseModel):
    notify_game_start: bool
    notify_score_change: bool
    notify_game_end: bool
    notify_my_team_only: bool
    notify_streak: bool = True
    notify_rank_change: bool = True
    notify_roster: bool = True
    notify_comment: bool = True
    notify_pennant_race: bool = True
    notify_fav_hr: bool = True
    notify_walkoff: bool = True
    notify_starter_ko: bool = True
    notify_before_minutes: int = 60  # 30 / 60 / 120


class PushToken(BaseModel):
    token: str


class NicknameUpdate(BaseModel):
    nickname: str


class StadiumRecord(BaseModel):
    wins: int
    losses: int
    draws: int


class StadiumVisitCreate(BaseModel):
    game_id: int
    result: str  # win / loss / draw
    memo: Optional[str] = None
    image_url: Optional[str] = None


# ===== 닉네임 변경 =====

@router.put("/nickname")
def update_nickname(body: NicknameUpdate, current_user: dict = Depends(get_current_user)):
    nickname = body.nickname.strip()
    if len(nickname) < 2 or len(nickname) > 20:
        raise HTTPException(status_code=400, detail="닉네임은 2~20자여야 합니다")

    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("SELECT id FROM users WHERE nickname = %s AND id != %s", (nickname, current_user["user_id"]))
    if cur.fetchone():
        cur.close()
        conn.close()
        raise HTTPException(status_code=400, detail="이미 사용 중인 닉네임입니다")

    cur.execute("UPDATE users SET nickname = %s WHERE id = %s", (nickname, current_user["user_id"]))
    conn.commit()
    cur.close()
    conn.close()
    return {"message": "닉네임 변경 완료", "nickname": nickname}


# ===== 마이팀 =====

@router.get("/favorite-teams")
def get_favorite_teams(current_user: dict = Depends(get_current_user)):
    """마이팀 목록 조회"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("""
        SELECT t.id, t.name, t.short_name, t.logo_url,
               t.wins, t.losses, t.rank, t.win_rate
        FROM user_favorite_teams uft
        JOIN teams t ON uft.team_id = t.id
        WHERE uft.user_id = %s
        ORDER BY uft.created_at
    """, (current_user["user_id"],))

    rows = cur.fetchall()
    cur.close()
    conn.close()

    return {
        "teams": [
            {
                "id":         r[0],
                "name":       r[1],
                "short_name": r[2],
                "logo_url":   r[3],
                "wins":       r[4],
                "losses":     r[5],
                "rank":       r[6],
                "win_rate":   float(r[7]) if r[7] else 0,
            }
            for r in rows
        ]
    }


@router.post("/favorite-teams")
def add_favorite_team(body: FavoriteTeam, current_user: dict = Depends(get_current_user)):
    """마이팀 추가"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()

    # 팀 존재 확인
    cur.execute("SELECT id FROM teams WHERE id = %s", (body.team_id,))
    if not cur.fetchone():
        raise HTTPException(status_code=404, detail="팀을 찾을 수 없습니다")

    # 중복 확인
    cur.execute("""
        SELECT id FROM user_favorite_teams 
        WHERE user_id = %s AND team_id = %s
    """, (current_user["user_id"], body.team_id))
    if cur.fetchone():
        raise HTTPException(status_code=400, detail="이미 마이팀으로 등록된 팀입니다")

    cur.execute("""
        INSERT INTO user_favorite_teams (user_id, team_id)
        VALUES (%s, %s)
    """, (current_user["user_id"], body.team_id))

    conn.commit()
    cur.close()
    conn.close()
    return {"message": "마이팀 추가 완료"}


@router.delete("/favorite-teams/{team_id}")
def remove_favorite_team(team_id: int, current_user: dict = Depends(get_current_user)):
    """마이팀 삭제"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("""
        DELETE FROM user_favorite_teams
        WHERE user_id = %s AND team_id = %s
    """, (current_user["user_id"], team_id))

    conn.commit()
    cur.close()
    conn.close()
    return {"message": "마이팀 삭제 완료"}


# ===== 관심 선수 =====

@router.get("/favorite-players")
def get_favorite_players(current_user: dict = Depends(get_current_user)):
    """관심 선수 목록 조회"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("""
        SELECT p.id, p.name, p.position, p.number,
               p.profile_image, t.name AS team
        FROM user_favorite_players ufp
        JOIN players p ON ufp.player_id = p.id
        JOIN teams t ON p.team_id = t.id
        WHERE ufp.user_id = %s
        ORDER BY ufp.created_at
    """, (current_user["user_id"],))

    rows = cur.fetchall()
    cur.close()
    conn.close()

    return {
        "players": [
            {
                "id":            r[0],
                "name":          r[1],
                "position":      r[2],
                "number":        r[3],
                "profile_image": r[4],
                "team":          r[5],
            }
            for r in rows
        ]
    }


@router.post("/favorite-players")
def add_favorite_player(body: FavoritePlayer, current_user: dict = Depends(get_current_user)):
    """관심 선수 추가"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()

    cur.execute("SELECT id FROM players WHERE id = %s", (body.player_id,))
    if not cur.fetchone():
        raise HTTPException(status_code=404, detail="선수를 찾을 수 없습니다")

    cur.execute("""
        SELECT id FROM user_favorite_players
        WHERE user_id = %s AND player_id = %s
    """, (current_user["user_id"], body.player_id))
    if cur.fetchone():
        raise HTTPException(status_code=400, detail="이미 즐겨찾기된 선수입니다")

    cur.execute("""
        INSERT INTO user_favorite_players (user_id, player_id)
        VALUES (%s, %s)
    """, (current_user["user_id"], body.player_id))

    conn.commit()
    cur.close()
    conn.close()
    return {"message": "관심 선수 추가 완료"}


@router.delete("/favorite-players/{player_id}")
def remove_favorite_player(player_id: int, current_user: dict = Depends(get_current_user)):
    """관심 선수 삭제"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("""
        DELETE FROM user_favorite_players
        WHERE user_id = %s AND player_id = %s
    """, (current_user["user_id"], player_id))

    conn.commit()
    cur.close()
    conn.close()
    return {"message": "관심 선수 삭제 완료"}


# ===== 알림 설정 =====

@router.get("/settings")
def get_settings(current_user: dict = Depends(get_current_user)):
    """알림 설정 조회"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("""
        SELECT notify_game_start, notify_score_change,
               notify_game_end, notify_my_team_only,
               notify_streak, notify_rank_change, notify_roster, notify_comment,
               notify_pennant_race, notify_fav_hr, notify_walkoff, notify_starter_ko,
               notify_before_minutes
        FROM user_settings
        WHERE user_id = %s
    """, (current_user["user_id"],))

    row = cur.fetchone()
    cur.close()
    conn.close()

    if not row:
        return {"settings": None}

    return {
        "settings": {
            "notify_game_start":      row[0],
            "notify_score_change":    row[1],
            "notify_game_end":        row[2],
            "notify_my_team_only":    row[3],
            "notify_streak":          row[4]  if row[4]  is not None else True,
            "notify_rank_change":     row[5]  if row[5]  is not None else True,
            "notify_roster":          row[6]  if row[6]  is not None else True,
            "notify_comment":         row[7]  if row[7]  is not None else True,
            "notify_pennant_race":    row[8]  if row[8]  is not None else True,
            "notify_fav_hr":          row[9]  if row[9]  is not None else True,
            "notify_walkoff":         row[10] if row[10] is not None else True,
            "notify_starter_ko":      row[11] if row[11] is not None else True,
            "notify_before_minutes":  row[12] if row[12] is not None else 60,
        }
    }


@router.put("/settings")
def update_settings(body: NotificationSettings, current_user: dict = Depends(get_current_user)):
    """알림 설정 변경"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    before_min = body.notify_before_minutes if body.notify_before_minutes in (30, 60, 120) else 60
    cur.execute("""
        UPDATE user_settings
        SET notify_game_start = %s,
            notify_score_change = %s,
            notify_game_end = %s,
            notify_my_team_only = %s,
            notify_streak = %s,
            notify_rank_change = %s,
            notify_roster = %s,
            notify_comment = %s,
            notify_pennant_race = %s,
            notify_fav_hr = %s,
            notify_walkoff = %s,
            notify_starter_ko = %s,
            notify_before_minutes = %s,
            updated_at = NOW()
        WHERE user_id = %s
    """, (
        body.notify_game_start,
        body.notify_score_change,
        body.notify_game_end,
        body.notify_my_team_only,
        body.notify_streak,
        body.notify_rank_change,
        body.notify_roster,
        body.notify_comment,
        body.notify_pennant_race,
        body.notify_fav_hr,
        body.notify_walkoff,
        body.notify_starter_ko,
        before_min,
        current_user["user_id"]
    ))

    conn.commit()
    cur.close()
    conn.close()
    return {"message": "알림 설정 변경 완료"}


# ===== FCM 푸시 토큰 =====

@router.post("/push-token")
def register_push_token(body: PushToken, current_user: dict = Depends(get_current_user)):
    """FCM 푸시 토큰 등록"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("""
        INSERT INTO push_tokens (user_id, token)
        VALUES (%s, %s)
        ON CONFLICT (user_id, token) DO NOTHING
    """, (current_user["user_id"], body.token))

    conn.commit()
    cur.close()
    conn.close()
    return {"message": "푸시 토큰 등록 완료"}

from fastapi import UploadFile, File, Request
import os, uuid, shutil
from api.security_log import log_upload

PROFILE_DIR = '/home/ubuntu/playball/backend/static/profiles'
BASE_URL = 'https://playball.duckdns.org'
_MAX_UPLOAD_BYTES = 5 * 1024 * 1024  # 5MB

# 이미지 매직바이트 (JPEG, PNG, WebP)
_IMG_MAGIC = {
    b'\xff\xd8\xff': ('.jpg', '.jpeg'),
    b'\x89PNG':       ('.png',),
    b'RIFF':          ('.webp',),   # RIFF????WEBP 추가 검증
}

def _validate_image(data: bytes, ext: str) -> bool:
    """매직바이트로 실제 이미지 포맷 검증"""
    for magic, exts in _IMG_MAGIC.items():
        if data[:len(magic)] == magic:
            if magic == b'RIFF':
                return data[8:12] == b'WEBP' and ext in exts
            return ext in exts
    return False


@router.post('/profile-image')
async def upload_profile_image(
    file: UploadFile = File(...),
    request: Request = None,
    current_user: dict = Depends(get_current_user)
):
    ext = os.path.splitext(file.filename or 'img.jpg')[1].lower()
    if ext not in ('.jpg', '.jpeg', '.png', '.webp'):
        raise HTTPException(status_code=400, detail='jpg/png/webp만 허용됩니다')
    data = await file.read(_MAX_UPLOAD_BYTES + 1)
    if len(data) > _MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail='파일 크기는 5MB를 초과할 수 없습니다')
    if not _validate_image(data, ext):
        raise HTTPException(status_code=400, detail='유효하지 않은 이미지 파일입니다')
    filename = f"{current_user['user_id']}_{uuid.uuid4().hex[:8]}{ext}"
    path = os.path.join(PROFILE_DIR, filename)
    with open(path, 'wb') as f:
        f.write(data)
    ip = (request.headers.get("X-Real-IP") or request.client.host) if request else "unknown"
    log_upload(ip, current_user['user_id'], filename, len(data))
    url = f"{BASE_URL}/static/profiles/{filename}"
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail='DB 연결 실패')
    cur = conn.cursor()
    cur.execute('UPDATE users SET profile_image = %s WHERE id = %s', (url, current_user['user_id']))
    conn.commit()
    cur.close()
    conn.close()
    return {'profile_image': url}


# ===== 개인 캘린더 이벤트 =====
class CalendarEventCreate(BaseModel):
    event_date: str          # YYYY-MM-DD (시작일)
    end_date: Optional[str] = None  # YYYY-MM-DD (종료일, 없으면 시작일과 동일)
    title: str
    description: Optional[str] = None
    color: Optional[str] = 'blue'

@router.get('/calendar-events')
def get_calendar_events(year: int, month: int, current_user: dict = Depends(get_current_user)):
    from datetime import date, timedelta
    import calendar as cal
    month_start = date(year, month, 1)
    month_end = date(year, month, cal.monthrange(year, month)[1])
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail='DB 연결 실패')
    cur = conn.cursor()
    # 해당 월에 걸치는 모든 이벤트 (시작일 <= 월말 AND 종료일 >= 월초)
    cur.execute("""
        SELECT id, event_date, COALESCE(end_date, event_date), title, description, color, created_at
        FROM user_calendar_events
        WHERE user_id = %s
          AND event_date <= %s
          AND COALESCE(end_date, event_date) >= %s
        ORDER BY event_date, id
    """, (current_user['user_id'], month_end, month_start))
    rows = cur.fetchall()
    cur.close(); conn.close()
    return {"events": [
        {"id": r[0], "start_date": str(r[1]), "end_date": str(r[2]),
         "date": str(r[1]),  # 하위 호환
         "title": r[3], "description": r[4], "color": r[5], "created_at": str(r[6])}
        for r in rows
    ]}

@router.post('/calendar-events')
def create_calendar_event(body: CalendarEventCreate, current_user: dict = Depends(get_current_user)):
    end = body.end_date or body.event_date
    if end < body.event_date:
        end = body.event_date
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail='DB 연결 실패')
    cur = conn.cursor()
    cur.execute("""
        INSERT INTO user_calendar_events (user_id, event_date, end_date, title, description, color)
        VALUES (%s, %s, %s, %s, %s, %s)
        RETURNING id
    """, (current_user['user_id'], body.event_date, end, body.title, body.description, body.color or 'blue'))
    new_id = cur.fetchone()[0]
    conn.commit(); cur.close(); conn.close()
    return {"id": new_id, "message": "일정 추가 완료"}

@router.delete('/calendar-events/{event_id}')
def delete_calendar_event(event_id: int, current_user: dict = Depends(get_current_user)):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail='DB 연결 실패')
    cur = conn.cursor()
    cur.execute("""
        DELETE FROM user_calendar_events
        WHERE id = %s AND user_id = %s
    """, (event_id, current_user['user_id']))
    conn.commit(); cur.close(); conn.close()
    return {"message": "삭제 완료"}


# ── 알림 타임라인 ──────────────────────────────────────────────────────────────

@router.get('/notifications')
def get_notifications(limit: int = 30, current_user: dict = Depends(get_current_user)):
    """알림 이력 조회 (최신순)"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail='DB 연결 실패')
    cur = conn.cursor()
    cur.execute("""
        SELECT id, title, body, type, game_id, is_read, created_at
        FROM user_notifications
        WHERE user_id = %s
        ORDER BY created_at DESC
        LIMIT %s
    """, (current_user['user_id'], limit))
    rows = cur.fetchall()
    cur.execute(
        "SELECT COUNT(*) FROM user_notifications WHERE user_id = %s AND is_read = FALSE",
        (current_user['user_id'],)
    )
    unread = cur.fetchone()[0]
    cur.close(); conn.close()
    return {
        "unread_count": unread,
        "notifications": [
            {
                "id":         r[0],
                "title":      r[1],
                "body":       r[2],
                "type":       r[3],
                "game_id":    r[4],
                "is_read":    r[5],
                "created_at": str(r[6]),
            }
            for r in rows
        ]
    }


@router.post('/notifications/read-all')
def read_all_notifications(current_user: dict = Depends(get_current_user)):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail='DB 연결 실패')
    cur = conn.cursor()
    cur.execute(
        "UPDATE user_notifications SET is_read = TRUE WHERE user_id = %s AND is_read = FALSE",
        (current_user['user_id'],)
    )
    conn.commit(); cur.close(); conn.close()
    return {"message": "모두 읽음"}


@router.patch('/notifications/{notif_id}/read')
def read_notification(notif_id: int, current_user: dict = Depends(get_current_user)):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail='DB 연결 실패')
    cur = conn.cursor()
    cur.execute(
        "UPDATE user_notifications SET is_read = TRUE WHERE id = %s AND user_id = %s",
        (notif_id, current_user['user_id'])
    )
    conn.commit(); cur.close(); conn.close()
    return {"message": "읽음"}


# ===== 직관 기록 =====

@router.get('/stadium-record')
def get_stadium_record(current_user: dict = Depends(get_current_user)):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail='DB 연결 실패')
    cur = conn.cursor()
    cur.execute("""
        SELECT
            COUNT(*) FILTER (WHERE result='win') AS wins,
            COUNT(*) FILTER (WHERE result='loss') AS losses,
            COUNT(*) FILTER (WHERE result='draw') AS draws
        FROM user_stadium_visits WHERE user_id=%s
    """, (current_user['user_id'],))
    row = cur.fetchone()
    cur.close(); conn.close()
    return {"wins": row[0] or 0, "losses": row[1] or 0, "draws": row[2] or 0}


# ===== 직관 방문 기록 =====

@router.get('/stadium-visits')
def get_stadium_visits(limit: int = 20, current_user: dict = Depends(get_current_user)):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail='DB 연결 실패')
    cur = conn.cursor()
    cur.execute("""
        SELECT v.id, v.game_id, v.result, v.memo, v.created_at,
               g.game_date, g.home_score, g.away_score, g.status,
               ht.name AS home_team, ht.short_name AS home_code,
               at2.name AS away_team, at2.short_name AS away_code,
               v.image_url
        FROM user_stadium_visits v
        JOIN games g ON g.id = v.game_id
        JOIN teams ht ON ht.id = g.home_team_id
        JOIN teams at2 ON at2.id = g.away_team_id
        WHERE v.user_id = %s
        ORDER BY v.created_at DESC
        LIMIT %s
    """, (current_user['user_id'], limit))
    rows = cur.fetchall()
    cur.close(); conn.close()
    visits = []
    for r in rows:
        visits.append({
            "id": r[0], "game_id": r[1], "result": r[2], "memo": r[3],
            "created_at": r[4].isoformat() if r[4] else None,
            "game_date": r[5].isoformat() if r[5] else None,
            "home_score": r[6], "away_score": r[7], "status": r[8],
            "home_team": r[9], "home_code": r[10],
            "away_team": r[11], "away_code": r[12],
            "image_url": r[13],
        })
    return {"visits": visits}


@router.post('/stadium-visits')
def add_stadium_visit(body: StadiumVisitCreate, current_user: dict = Depends(get_current_user)):
    if body.result not in ('win', 'loss', 'draw'):
        raise HTTPException(status_code=400, detail="result는 win/loss/draw 중 하나")
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail='DB 연결 실패')
    cur = conn.cursor()
    try:
        cur.execute("""
            INSERT INTO user_stadium_visits (user_id, game_id, result, memo, image_url)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (user_id, game_id) DO UPDATE
                SET result=EXCLUDED.result, memo=EXCLUDED.memo, image_url=EXCLUDED.image_url
            RETURNING id
        """, (current_user['user_id'], body.game_id, body.result, body.memo, body.image_url))
        visit_id = cur.fetchone()[0]
        conn.commit()
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(e))
    finally:
        cur.close(); conn.close()
    return {"id": visit_id}


@router.delete('/stadium-visits/{visit_id}')
def delete_stadium_visit(visit_id: int, current_user: dict = Depends(get_current_user)):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail='DB 연결 실패')
    cur = conn.cursor()
    cur.execute("DELETE FROM user_stadium_visits WHERE id=%s AND user_id=%s RETURNING id",
                (visit_id, current_user['user_id']))
    deleted = cur.fetchone()
    conn.commit(); cur.close(); conn.close()
    if not deleted:
        raise HTTPException(status_code=404, detail="기록 없음")
    return {"ok": True}


# ===== 직관 통계 =====

@router.get('/stadium-stats')
def get_stadium_stats(current_user: dict = Depends(get_current_user)):
    """구장별/월별 직관 통계"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail='DB 연결 실패')
    cur = conn.cursor()
    uid = current_user['user_id']

    cur.execute("""
        SELECT s.id, s.name,
               COUNT(*) AS total,
               COUNT(*) FILTER (WHERE v.result='win') AS wins,
               COUNT(*) FILTER (WHERE v.result='loss') AS losses,
               COUNT(*) FILTER (WHERE v.result='draw') AS draws
        FROM user_stadium_visits v
        JOIN games g ON g.id = v.game_id
        JOIN stadiums s ON s.id = g.stadium_id
        WHERE v.user_id = %s
        GROUP BY s.id, s.name
        ORDER BY total DESC
    """, (uid,))
    by_stadium = [
        {"stadium_id": r[0], "name": r[1],
         "total": r[2], "wins": r[3], "losses": r[4], "draws": r[5],
         "win_rate": round(r[3]/r[2], 3) if r[2] > 0 else 0.0}
        for r in cur.fetchall()
    ]

    cur.execute("""
        SELECT EXTRACT(YEAR FROM g.game_date)::int AS yr,
               EXTRACT(MONTH FROM g.game_date)::int AS mo,
               COUNT(*) AS total,
               COUNT(*) FILTER (WHERE v.result='win') AS wins,
               COUNT(*) FILTER (WHERE v.result='loss') AS losses,
               COUNT(*) FILTER (WHERE v.result='draw') AS draws
        FROM user_stadium_visits v
        JOIN games g ON g.id = v.game_id
        WHERE v.user_id = %s
        GROUP BY yr, mo
        ORDER BY yr DESC, mo DESC
    """, (uid,))
    by_month = [
        {"year": r[0], "month": r[1],
         "total": r[2], "wins": r[3], "losses": r[4], "draws": r[5]}
        for r in cur.fetchall()
    ]

    cur.close(); conn.close()
    return {"by_stadium": by_stadium, "by_month": by_month}


# ===== 직관승률 랭킹 (공개) =====

@router.get('/stadium-ranking')
def get_stadium_ranking(limit: int = 30):
    """직관 5회 이상 유저 승률 랭킹 (공개)"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail='DB 연결 실패')
    cur = conn.cursor()
    cur.execute("""
        SELECT u.nickname,
               COUNT(*) AS total,
               COUNT(*) FILTER (WHERE v.result='win') AS wins,
               COUNT(*) FILTER (WHERE v.result='loss') AS losses,
               COUNT(*) FILTER (WHERE v.result='draw') AS draws
        FROM user_stadium_visits v
        JOIN users u ON u.id = v.user_id
        GROUP BY u.id, u.nickname
        HAVING COUNT(*) >= 5
        ORDER BY
            (COUNT(*) FILTER (WHERE v.result='win'))::float /
            NULLIF(COUNT(*) FILTER (WHERE v.result IN ('win','loss')), 0) DESC NULLS LAST,
            COUNT(*) DESC
        LIMIT %s
    """, (limit,))
    rows = cur.fetchall()
    cur.close(); conn.close()
    result = []
    for i, r in enumerate(rows):
        total = r[1]; wins = r[2]; losses = r[3]; draws = r[4]
        denom = wins + losses
        win_rate = round(wins / denom, 3) if denom > 0 else 0.0
        result.append({
            "rank": i + 1,
            "nickname": r[0],
            "total": total,
            "wins": wins,
            "losses": losses,
            "draws": draws,
            "win_rate": win_rate,
        })
    return {"ranking": result}
