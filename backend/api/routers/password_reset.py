from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from datetime import datetime, timedelta
from database.connection import get_connection
from api.email_service import send_verification_email
from api.routers.auth import hash_password, validate_password
import secrets

router = APIRouter()
MAX_VERIFY_ATTEMPTS = 5


def _generate_code() -> str:
    return f'{secrets.randbelow(1_000_000):06d}'


class SendCodeRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254)


class ResetRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    code: str = Field(pattern=r'^\d{6}$')
    new_password: str = Field(min_length=8, max_length=128)


@router.post("/send-code")
def send_reset_code(req: SendCodeRequest):
    email = req.email.strip().lower()
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()

    cur.execute("SELECT id FROM users WHERE email = %s", (email,))
    row = cur.fetchone()
    if not row:
        cur.close()
        conn.close()
        # 보안상 이메일 존재 여부 노출 금지
        return {'message': '이메일이 발송되었습니다'}
    user_id = row[0]

    # rate limit: 1분 내 재발송 차단
    cur.execute(
        """SELECT created_at FROM phone_verifications
           WHERE user_id=%s AND used=FALSE AND expires_at > NOW()
           ORDER BY created_at DESC LIMIT 1""",
        (user_id,)
    )
    last = cur.fetchone()
    if last:
        elapsed = (datetime.now() - last[0]).total_seconds()
        if elapsed < 60:
            cur.close()
            conn.close()
            raise HTTPException(status_code=429, detail=f"{int(60 - elapsed)}초 후 재발송 가능합니다")

    code = _generate_code()
    expires_at = datetime.now() + timedelta(minutes=10)
    cur.execute(
        'INSERT INTO phone_verifications (user_id, phone_number, code, expires_at) VALUES (%s, %s, %s, %s)',
        (user_id, email, code, expires_at)
    )
    if not send_verification_email(email, code):
        cur.execute(
            'UPDATE phone_verifications SET used=TRUE '
            'WHERE user_id=%s AND phone_number=%s AND code=%s',
            (user_id, email, code),
        )
    conn.commit()
    cur.close()
    conn.close()
    return {'message': '이메일이 발송되었습니다'}


@router.post("/reset")
def reset_password(req: ResetRequest):
    email = req.email.strip().lower()
    validate_password(req.new_password)

    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()

    cur.execute("SELECT id FROM users WHERE email = %s", (email,))
    row = cur.fetchone()
    if not row:
        cur.close()
        conn.close()
        raise HTTPException(status_code=400, detail="인증번호가 올바르지 않거나 만료되었습니다")
    user_id = row[0]

    cur.execute(
        """SELECT id FROM phone_verifications
           WHERE user_id=%s AND phone_number=%s AND code=%s
             AND COALESCE(attempts, 0) < %s
             AND expires_at > NOW() AND used=FALSE
           ORDER BY created_at DESC LIMIT 1 FOR UPDATE""",
        (user_id, email, req.code, MAX_VERIFY_ATTEMPTS)
    )
    vrow = cur.fetchone()
    if not vrow:
        cur.execute(
            """SELECT id, COALESCE(attempts, 0) FROM phone_verifications
               WHERE user_id=%s AND phone_number=%s
                 AND expires_at > NOW() AND used=FALSE
               ORDER BY created_at DESC LIMIT 1 FOR UPDATE""",
            (user_id, email),
        )
        active = cur.fetchone()
        if active:
            invalidate = active[1] + 1 >= MAX_VERIFY_ATTEMPTS
            cur.execute(
                "UPDATE phone_verifications "
                "SET attempts=COALESCE(attempts,0)+1, used=%s WHERE id=%s",
                (invalidate, active[0]),
            )
            conn.commit()
        cur.close()
        conn.close()
        raise HTTPException(status_code=400, detail="인증번호가 올바르지 않거나 만료되었습니다")

    hashed = hash_password(req.new_password)
    cur.execute('UPDATE phone_verifications SET used=TRUE WHERE id=%s', (vrow[0],))
    cur.execute('UPDATE users SET password_hash=%s WHERE id=%s', (hashed, user_id))
    cur.execute('UPDATE refresh_tokens SET revoked=TRUE WHERE user_id=%s', (user_id,))
    conn.commit()
    cur.close()
    conn.close()

    return {'message': '비밀번호가 변경되었습니다'}
