import os
import hmac
import hashlib
import secrets
import string
import time
import logging
import requests

logger = logging.getLogger(__name__)
API_KEY = os.environ.get('COOLSMS_API_KEY', '')
API_SECRET = os.environ.get('COOLSMS_API_SECRET', '')
SENDER = os.environ.get('COOLSMS_SENDER', '')
_ALLOW_DEV_CODES = os.environ.get('ALLOW_DEV_VERIFICATION_CODES') == '1'


def generate_code() -> str:
    return f'{secrets.randbelow(1_000_000):06d}'


def send_verification_sms(phone: str, code: str) -> bool:
    if not API_KEY or not API_SECRET or not SENDER:
        if _ALLOW_DEV_CODES:
            logger.warning('[SMS Dev] verification code for %s: %s', phone, code)
            return True
        logger.error('[SMS] credentials are not configured')
        return False
    try:
        timestamp = str(int(time.time() * 1000))
        salt = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(16))
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
        logger.error(f'[SMS Error] {e}')
        return False
