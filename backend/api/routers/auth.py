from fastapi import APIRouter, HTTPException, Depends
from fastapi.security import OAuth2PasswordBearer
from pydantic import BaseModel
from jose import JWTError, jwt
from datetime import datetime, timedelta, timezone
from database.connection import get_connection
import bcrypt
import hashlib
import os
import secrets

router = APIRouter()

SECRET_KEY = os.environ.get("JWT_SECRET_KEY", "playball_secret_key_2026_fallback")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60       # 1시간
REFRESH_TOKEN_EXPIRE_DAYS = 30

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


class UserRegister(BaseModel):
    email: str
    password: str
    nickname: str


class UserLogin(BaseModel):
    email: str
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


def hash_password(password: str) -> str:
    salt = bcrypt.gensalt()
    return bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))


def create_access_token(user_id: int, email: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    return jwt.encode({"sub": str(user_id), "email": email, "exp": expire}, SECRET_KEY, algorithm=ALGORITHM)


def create_refresh_token(user_id: int) -> str:
    raw = secrets.token_hex(32)
    token_hash = hashlib.sha256(raw.encode()).hexdigest()
    expires_at = datetime.now(timezone.utc) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    conn = get_connection()
    if conn:
        cur = conn.cursor()
        # 유저당 최대 5개 유지 (오래된 것 삭제)
        cur.execute("""
            DELETE FROM refresh_tokens WHERE id IN (
                SELECT id FROM refresh_tokens WHERE user_id=%s AND revoked=FALSE
                ORDER BY created_at ASC
                OFFSET 4
            )
        """, (user_id,))
        cur.execute(
            "INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES (%s, %s, %s)",
            (user_id, token_hash, expires_at)
        )
        conn.commit(); cur.close(); conn.close()
    return raw


def get_current_user(token: str = Depends(oauth2_scheme)):
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = int(payload.get("sub"))
        email = payload.get("email")
        if not user_id:
            raise HTTPException(status_code=401, detail="인증 실패")
        return {"user_id": user_id, "email": email}
    except JWTError:
        raise HTTPException(status_code=401, detail="토큰이 유효하지 않습니다")


@router.get("/check-email")
def check_email(email: str):
    """이메일 중복확인"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("SELECT id FROM users WHERE email = %s", (email,))
    exists = cur.fetchone() is not None
    cur.close()
    conn.close()
    return {"available": not exists}


@router.get("/check-nickname")
def check_nickname(nickname: str):
    """닉네임 중복확인"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("SELECT id FROM users WHERE nickname = %s", (nickname,))
    exists = cur.fetchone() is not None
    cur.close()
    conn.close()
    return {"available": not exists}


@router.post("/register")
def register(user: UserRegister):
    """회원가입"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()

    # 이메일 중복 확인
    cur.execute("SELECT id FROM users WHERE email = %s", (user.email,))
    if cur.fetchone():
        raise HTTPException(status_code=400, detail="이미 사용 중인 이메일입니다")

    # 닉네임 중복 확인
    cur.execute("SELECT id FROM users WHERE nickname = %s", (user.nickname,))
    if cur.fetchone():
        raise HTTPException(status_code=400, detail="이미 사용 중인 닉네임입니다")

    # 비밀번호 해시 후 저장
    hashed_pw = hash_password(user.password)
    cur.execute("""
        INSERT INTO users (email, password_hash, nickname)
        VALUES (%s, %s, %s)
        RETURNING id
    """, (user.email, hashed_pw, user.nickname))

    user_id = cur.fetchone()[0]

    # 기본 알림 설정 생성
    cur.execute("""
        INSERT INTO user_settings (user_id)
        VALUES (%s)
    """, (user_id,))

    conn.commit()
    cur.close()
    conn.close()

    access_token = create_access_token(user_id, user.email)
    refresh_token = create_refresh_token(user_id)
    return {
        "message": "회원가입 성공",
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "user_id": user_id,
        "nickname": user.nickname
    }


@router.post("/login")
def login(user: UserLogin):
    """로그인"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("""
        SELECT id, email, password_hash, nickname
        FROM users WHERE email = %s
    """, (user.email,))
    row = cur.fetchone()
    cur.close()
    conn.close()

    if not row:
        raise HTTPException(status_code=401, detail="이메일 또는 비밀번호가 틀렸습니다")

    user_id, email, password_hash, nickname = row

    if not verify_password(user.password, password_hash):
        raise HTTPException(status_code=401, detail="이메일 또는 비밀번호가 틀렸습니다")

    access_token = create_access_token(user_id, email)
    refresh_token = create_refresh_token(user_id)
    return {
        "message": "로그인 성공",
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "user_id": user_id,
        "nickname": nickname
    }


@router.post("/refresh")
def refresh_token(body: RefreshRequest):
    """Refresh token으로 새 access token 발급"""
    token_hash = hashlib.sha256(body.refresh_token.encode()).hexdigest()
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("""
        SELECT rt.user_id, u.email
        FROM refresh_tokens rt
        JOIN users u ON rt.user_id = u.id
        WHERE rt.token_hash = %s
          AND rt.revoked = FALSE
          AND rt.expires_at > NOW()
    """, (token_hash,))
    row = cur.fetchone()
    if not row:
        cur.close(); conn.close()
        raise HTTPException(status_code=401, detail="refresh token이 유효하지 않습니다")
    user_id, email = row
    # 기존 토큰 revoke (rotation)
    cur.execute("UPDATE refresh_tokens SET revoked=TRUE WHERE token_hash=%s", (token_hash,))
    conn.commit(); cur.close(); conn.close()

    new_access = create_access_token(user_id, email)
    new_refresh = create_refresh_token(user_id)
    return {"access_token": new_access, "refresh_token": new_refresh, "token_type": "bearer"}


@router.post("/logout")
def logout(body: RefreshRequest):
    """Refresh token revoke"""
    token_hash = hashlib.sha256(body.refresh_token.encode()).hexdigest()
    conn = get_connection()
    if conn:
        cur = conn.cursor()
        cur.execute("UPDATE refresh_tokens SET revoked=TRUE WHERE token_hash=%s", (token_hash,))
        conn.commit(); cur.close(); conn.close()
    return {"message": "로그아웃 완료"}


@router.delete("/me")
def delete_me(current_user: dict = Depends(get_current_user)):
    """회원탈퇴"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("DELETE FROM users WHERE id = %s", (current_user["user_id"],))
    conn.commit()
    cur.close()
    conn.close()
    return {"message": "탈퇴 완료"}


@router.get("/me")
def get_me(current_user: dict = Depends(get_current_user)):
    """내 정보 조회"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("""
        SELECT u.id, u.email, u.nickname, u.profile_image, u.created_at,
               us.notify_game_start, us.notify_score_change,
               us.notify_game_end, us.notify_my_team_only,
               u.phone_number, u.phone_verified,
               us.notify_streak, us.notify_rank_change,
               us.notify_roster, us.notify_comment,
               us.notify_pennant_race,
               us.notify_fav_hr, us.notify_walkoff, us.notify_starter_ko
        FROM users u
        LEFT JOIN user_settings us ON u.id = us.user_id
        WHERE u.id = %s
    """, (current_user["user_id"],))
    row = cur.fetchone()
    cur.close()
    conn.close()

    if not row:
        raise HTTPException(status_code=404, detail="유저를 찾을 수 없습니다")

    return {
        "id":             row[0],
        "email":          row[1],
        "nickname":       row[2],
        "profile_image":  row[3],
        "created_at":     str(row[4]),
        "phone_number":   row[9],
        "phone_verified": row[10] or False,
        "settings": {
            "notify_game_start":   row[5],
            "notify_score_change": row[6],
            "notify_game_end":     row[7],
            "notify_my_team_only": row[8],
            "notify_streak":        row[11] if row[11] is not None else True,
            "notify_rank_change":   row[12] if row[12] is not None else True,
            "notify_roster":        row[13] if row[13] is not None else True,
            "notify_comment":       row[14] if row[14] is not None else True,
            "notify_pennant_race":  row[15] if row[15] is not None else True,
            "notify_fav_hr":        row[16] if row[16] is not None else True,
            "notify_walkoff":       row[17] if row[17] is not None else True,
            "notify_starter_ko":    row[18] if row[18] is not None else True,
        }
    }