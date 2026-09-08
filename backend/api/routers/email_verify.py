from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, Field
from datetime import datetime, timedelta
from database.connection import get_connection
from api.routers.auth import get_current_user
from api.email_service import send_verification_email
import secrets

router = APIRouter()

RATE_LIMIT_SECONDS = 60   # 1분 내 재발송 차단
CLEANUP_KEEP_DAYS = 1     # 만료 레코드 1일 후 삭제
MAX_VERIFY_ATTEMPTS = 5   # 코드당 검증 실패 허용 횟수 (초과 시 코드 무효화)


def _generate_code() -> str:
    return f'{secrets.randbelow(1_000_000):06d}'


def _cleanup_expired(cur):
    cur.execute(
        "DELETE FROM phone_verifications WHERE expires_at < NOW() - INTERVAL '%s days'",
        (CLEANUP_KEEP_DAYS,)
    )


@router.post("/send-code")
def send_code(current_user: dict = Depends(get_current_user)):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()

    cur.execute("SELECT email FROM users WHERE id = %s", (current_user["user_id"],))
    row = cur.fetchone()
    if not row:
        cur.close()
        conn.close()
        raise HTTPException(status_code=404, detail="유저를 찾을 수 없습니다")
    email = row[0]

    # Rate limit: 1분 내 이미 발송된 코드 있으면 차단
    cur.execute(
        """SELECT created_at FROM phone_verifications
           WHERE user_id=%s AND used=FALSE AND expires_at > NOW()
           ORDER BY created_at DESC LIMIT 1""",
        (current_user["user_id"],)
    )
    last = cur.fetchone()
    if last:
        elapsed = (datetime.now() - last[0]).total_seconds()
        if elapsed < RATE_LIMIT_SECONDS:
            wait = int(RATE_LIMIT_SECONDS - elapsed)
            cur.close()
            conn.close()
            raise HTTPException(status_code=429, detail=f"{wait}초 후 재발송 가능합니다")

    _cleanup_expired(cur)

    code = _generate_code()
    expires_at = datetime.now() + timedelta(minutes=5)
    cur.execute(
        'INSERT INTO phone_verifications (user_id, phone_number, code, expires_at) VALUES (%s, %s, %s, %s)',
        (current_user["user_id"], email, code, expires_at)
    )
    ok = send_verification_email(email, code)
    if not ok:
        cur.execute(
            'UPDATE phone_verifications SET used=TRUE '
            'WHERE user_id=%s AND phone_number=%s AND code=%s',
            (current_user["user_id"], email, code),
        )
    conn.commit()
    cur.close()
    conn.close()
    if not ok:
        raise HTTPException(status_code=500, detail="이메일 발송 실패")
    return {'message': '인증번호가 발송되었습니다', 'email': email}


class VerifyRequest(BaseModel):
    code: str = Field(pattern=r'^\d{6}$')


@router.post("/verify")
def verify_code(req: VerifyRequest, current_user: dict = Depends(get_current_user)):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()

    cur.execute("SELECT email FROM users WHERE id = %s", (current_user["user_id"],))
    row = cur.fetchone()
    if not row:
        cur.close()
        conn.close()
        raise HTTPException(status_code=404, detail="유저를 찾을 수 없습니다")
    email = row[0]

    cur.execute(
        '''SELECT id FROM phone_verifications
           WHERE user_id=%s AND phone_number=%s AND code=%s
             AND expires_at > NOW() AND used=FALSE
           ORDER BY created_at DESC LIMIT 1 FOR UPDATE''',
        (current_user["user_id"], email, req.code)
    )
    vrow = cur.fetchone()
    if not vrow:
        # 실패 시도 카운트 — 활성 코드에 5회 실패 누적 시 코드 무효화 (brute-force 차단)
        cur.execute(
            '''SELECT id, COALESCE(attempts, 0) FROM phone_verifications
               WHERE user_id=%s AND phone_number=%s AND expires_at > NOW() AND used=FALSE
               ORDER BY created_at DESC LIMIT 1 FOR UPDATE''',
            (current_user["user_id"], email)
        )
        active = cur.fetchone()
        if active:
            if active[1] + 1 >= MAX_VERIFY_ATTEMPTS:
                cur.execute('UPDATE phone_verifications SET used=TRUE WHERE id=%s', (active[0],))
                conn.commit()
                cur.close()
                conn.close()
                raise HTTPException(status_code=400, detail="시도 횟수를 초과했습니다. 인증번호를 다시 발송해주세요")
            cur.execute('UPDATE phone_verifications SET attempts=COALESCE(attempts,0)+1 WHERE id=%s', (active[0],))
            conn.commit()
        cur.close()
        conn.close()
        raise HTTPException(status_code=400, detail="인증번호가 올바르지 않거나 만료되었습니다")

    cur.execute('UPDATE phone_verifications SET used=TRUE WHERE id=%s', (vrow[0],))
    cur.execute('UPDATE users SET phone_verified=TRUE WHERE id=%s', (current_user["user_id"],))
    _cleanup_expired(cur)
    conn.commit()
    cur.close()
    conn.close()

    return {'message': '인증 완료'}
