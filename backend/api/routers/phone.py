from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from datetime import datetime, timedelta
from database.connection import get_connection
from api.routers.auth import get_current_user
from api.sms_service import generate_code, send_verification_sms

router = APIRouter()


class SendCodeRequest(BaseModel):
    phone_number: str


class VerifyCodeRequest(BaseModel):
    phone_number: str
    code: str


@router.post("/send-code")
def send_code(req: SendCodeRequest, current_user: dict = Depends(get_current_user)):
    phone = req.phone_number.strip().replace('-', '').replace(' ', '')
    if not phone.startswith('0') or len(phone) < 10:
        raise HTTPException(status_code=400, detail="올바른 전화번호를 입력하세요")

    code = generate_code()
    expires_at = datetime.now() + timedelta(minutes=5)

    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute(
        'INSERT INTO phone_verifications (user_id, phone_number, code, expires_at) VALUES (%s, %s, %s, %s)',
        (current_user["user_id"], phone, code, expires_at)
    )
    conn.commit()
    cur.close()
    conn.close()

    ok = send_verification_sms(phone, code)
    if not ok:
        raise HTTPException(status_code=500, detail="SMS 발송 실패")
    return {'message': '인증번호가 발송되었습니다'}


@router.post("/verify")
def verify_code(req: VerifyCodeRequest, current_user: dict = Depends(get_current_user)):
    phone = req.phone_number.strip().replace('-', '').replace(' ', '')

    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()

    cur.execute(
        '''SELECT id FROM phone_verifications
           WHERE user_id=%s AND phone_number=%s AND code=%s
             AND expires_at > NOW() AND used=FALSE
           ORDER BY created_at DESC LIMIT 1''',
        (current_user["user_id"], phone, req.code)
    )
    row = cur.fetchone()
    if not row:
        cur.close()
        conn.close()
        raise HTTPException(status_code=400, detail="인증번호가 올바르지 않거나 만료되었습니다")

    cur.execute('UPDATE phone_verifications SET used=TRUE WHERE id=%s', (row[0],))
    cur.execute(
        'UPDATE users SET phone_number=%s, phone_verified=TRUE WHERE id=%s',
        (phone, current_user["user_id"])
    )
    conn.commit()
    cur.close()
    conn.close()

    return {'message': '인증 완료'}
