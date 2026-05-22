import smtplib
import os
from email.message import EmailMessage

EMAIL_USER = os.environ.get('EMAIL_USER', '')
EMAIL_PASS = os.environ.get('EMAIL_PASS', '')


def send_verification_email(to: str, code: str) -> bool:
    if not EMAIL_USER or not EMAIL_PASS:
        print(f'[Email Dev] {to} → 인증번호: {code}')
        return True
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
        with smtplib.SMTP_SSL('smtp.gmail.com', 465) as smtp:
            smtp.login(EMAIL_USER, EMAIL_PASS)
            smtp.send_message(msg)
        return True
    except Exception as e:
        print(f'[Email Error] {e}')
        return False
