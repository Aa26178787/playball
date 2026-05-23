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


class PushToken(BaseModel):
    token: str


class NicknameUpdate(BaseModel):
    nickname: str


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
               notify_streak, notify_rank_change, notify_roster, notify_comment
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
            "notify_game_start":   row[0],
            "notify_score_change": row[1],
            "notify_game_end":     row[2],
            "notify_my_team_only": row[3],
            "notify_streak":       row[4] if row[4] is not None else True,
            "notify_rank_change":  row[5] if row[5] is not None else True,
            "notify_roster":       row[6] if row[6] is not None else True,
            "notify_comment":      row[7] if row[7] is not None else True,
        }
    }


@router.put("/settings")
def update_settings(body: NotificationSettings, current_user: dict = Depends(get_current_user)):
    """알림 설정 변경"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
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

from fastapi import UploadFile, File
import os, uuid, shutil

PROFILE_DIR = '/home/ubuntu/playball/backend/static/profiles'
BASE_URL = 'http://168.107.61.147:8000'

@router.post('/profile-image')
async def upload_profile_image(
    file: UploadFile = File(...),
    current_user: dict = Depends(get_current_user)
):
    ext = os.path.splitext(file.filename or 'img.jpg')[1].lower()
    if ext not in ('.jpg', '.jpeg', '.png', '.webp'):
        raise HTTPException(status_code=400, detail='jpg/png/webp만 허용됩니다')
    filename = f"{current_user['user_id']}_{uuid.uuid4().hex[:8]}{ext}"
    path = os.path.join(PROFILE_DIR, filename)
    with open(path, 'wb') as f:
        shutil.copyfileobj(file.file, f)
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
    event_date: str   # YYYY-MM-DD
    title: str
    description: Optional[str] = None
    color: Optional[str] = 'blue'

@router.get('/calendar-events')
def get_calendar_events(year: int, month: int, current_user: dict = Depends(get_current_user)):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail='DB 연결 실패')
    cur = conn.cursor()
    cur.execute("""
        SELECT id, event_date, title, description, color, created_at
        FROM user_calendar_events
        WHERE user_id = %s
          AND EXTRACT(YEAR FROM event_date) = %s
          AND EXTRACT(MONTH FROM event_date) = %s
        ORDER BY event_date, id
    """, (current_user['user_id'], year, month))
    rows = cur.fetchall()
    cur.close(); conn.close()
    return {"events": [
        {"id": r[0], "date": str(r[1]), "title": r[2],
         "description": r[3], "color": r[4], "created_at": str(r[5])}
        for r in rows
    ]}

@router.post('/calendar-events')
def create_calendar_event(body: CalendarEventCreate, current_user: dict = Depends(get_current_user)):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail='DB 연결 실패')
    cur = conn.cursor()
    cur.execute("""
        INSERT INTO user_calendar_events (user_id, event_date, title, description, color)
        VALUES (%s, %s, %s, %s, %s)
        RETURNING id
    """, (current_user['user_id'], body.event_date, body.title, body.description, body.color or 'blue'))
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
