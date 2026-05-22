from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
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
               notify_game_end, notify_my_team_only
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
            updated_at = NOW()
        WHERE user_id = %s
    """, (
        body.notify_game_start,
        body.notify_score_change,
        body.notify_game_end,
        body.notify_my_team_only,
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