from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from datetime import datetime, timedelta
from database.connection import get_connection
from api.routers.auth import get_current_user
from api.email_service import send_verification_email
import random
import string

router = APIRouter()

RATE_LIMIT_SECONDS = 60   # 1분 내 재발송 차단
CLEANUP_KEEP_DAYS = 1     # 만료 레코드 1일 후 삭제


def _generate_code() -> str:
    return ''.join(random.choices(string.digits, k=6))


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
    conn.commit()
    cur.close()
    conn.close()

    ok = send_verification_email(email, code)
    if not ok:
        raise HTTPException(status_code=500, detail="이메일 발송 실패")
    return {'message': '인증번호가 발송되었습니다', 'email': email}


class VerifyRequest(BaseModel):
    code: str


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
           ORDER BY created_at DESC LIMIT 1''',
        (current_user["user_id"], email, req.code)
    )
    vrow = cur.fetchone()
    if not vrow:
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
