import os
import hmac
import hashlib
import random
import string
import time
import requests

API_KEY = os.environ.get('COOLSMS_API_KEY', '')
API_SECRET = os.environ.get('COOLSMS_API_SECRET', '')
SENDER = os.environ.get('COOLSMS_SENDER', '')


def generate_code() -> str:
    return ''.join(random.choices(string.digits, k=6))


def send_verification_sms(phone: str, code: str) -> bool:
    if not API_KEY or not API_SECRET or not SENDER:
        print(f'[SMS Dev] {phone} → 인증번호: {code}')
        return True
    try:
        timestamp = str(int(time.time() * 1000))
        salt = ''.join(random.choices(string.ascii_letters + string.digits, k=16))
        signature_msg = f'{timestamp}{salt}'
        signature = hmac.new(
            API_SECRET.encode('utf-8'),
            signature_msg.encode('utf-8'),
            hashlib.sha256
        ).hexdigest()

        headers = {
            'Authorization': f'HMAC-SHA256 apiKey={API_KEY}, date={timestamp}, salt={salt}, signature={signature}',
            'Content-Type': 'application/json',
        }
        payload = {
            'message': {
                'to': phone,
                'from': SENDER,
                'text': f'[PlayBall] 인증번호: {code} (5분 내 입력)',
            }
        }
        res = requests.post(
            'https://api.coolsms.co.kr/messages/v4/send',
            json=payload,
            headers=headers,
            timeout=10,
        )
        return res.status_code == 200
    except Exception as e:
        print(f'[SMS Error] {e}')
        return False
