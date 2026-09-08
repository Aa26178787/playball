import smtplib
import os
import logging
from email.message import EmailMessage

logger = logging.getLogger(__name__)
EMAIL_USER = os.environ.get('EMAIL_USER', '')
EMAIL_PASS = os.environ.get('EMAIL_PASS', '')
_ALLOW_DEV_CODES = os.environ.get('ALLOW_DEV_VERIFICATION_CODES') == '1'


def send_verification_email(to: str, code: str) -> bool:
    if not EMAIL_USER or not EMAIL_PASS:
        if _ALLOW_DEV_CODES:
            logger.warning('[Email Dev] verification code for %s: %s', to, code)
            return True
        logger.error('[Email] credentials are not configured')
        return False
    try:
        msg = EmailMessage()
        msg['Subject'] = '[PlayBall] 이메일 인증번호'
        msg['From'] = EMAIL_USER
        msg['To'] = to
        msg.set_content(
            f'PlayBall 이메일 인증번호: {code}\n\n'
            f'5분 내에 입력해 주세요.\n'
            f'본인이 요청하지 않은 경우 이 이메일을 무시하세요.'
        )
        with smtplib.SMTP_SSL('smtp.gmail.com', 465, timeout=10) as smtp:
            smtp.login(EMAIL_USER, EMAIL_PASS)
            smtp.send_message(msg)
        return True
    except Exception as e:
        logger.error(f'[Email Error] {e}')
        return False
