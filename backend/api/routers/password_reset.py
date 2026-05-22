from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from datetime import datetime, timedelta
from database.connection import get_connection
from api.email_service import send_verification_email
from api.routers.auth import hash_password
import random
import string

router = APIRouter()


def _generate_code() -> str:
    return ''.join(random.choices(string.digits, k=6))


class SendCodeRequest(BaseModel):
    email: str


class ResetRequest(BaseModel):
    email: str
    code: str
    new_password: str


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
    conn.commit()
    cur.close()
    conn.close()

    send_verification_email(email, code)
    return {'message': '이메일이 발송되었습니다'}


@router.post("/reset")
def reset_password(req: ResetRequest):
    email = req.email.strip().lower()
    if len(req.new_password) < 6:
        raise HTTPException(status_code=400, detail="비밀번호는 6자 이상이어야 합니다")

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
             AND expires_at > NOW() AND used=FALSE
           ORDER BY created_at DESC LIMIT 1""",
        (user_id, email, req.code)
    )
    vrow = cur.fetchone()
    if not vrow:
        cur.close()
        conn.close()
        raise HTTPException(status_code=400, detail="인증번호가 올바르지 않거나 만료되었습니다")

    hashed = hash_password(req.new_password)
    cur.execute('UPDATE phone_verifications SET used=TRUE WHERE id=%s', (vrow[0],))
    cur.execute('UPDATE users SET password_hash=%s WHERE id=%s', (hashed, user_id))
    conn.commit()
    cur.close()
    conn.close()

    return {'message': '비밀번호가 변경되었습니다'}
