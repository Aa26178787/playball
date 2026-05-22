from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from datetime import datetime, timedelta
from database.connection import get_connection
from api.routers.auth import get_current_user
from api.email_service import send_verification_email
import random
import string

router = APIRouter()


def _generate_code() -> str:
    return ''.join(random.choices(string.digits, k=6))


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
    conn.commit()
    cur.close()
    conn.close()

    return {'message': '인증 완료'}
