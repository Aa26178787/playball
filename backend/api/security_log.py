"""보안 이벤트 로거 — 파일 + stdout 동시 출력"""
import logging
import os
from datetime import datetime

_LOG_DIR = os.environ.get("LOG_DIR", "/home/ubuntu/playball/logs")
os.makedirs(_LOG_DIR, exist_ok=True)

_logger = logging.getLogger("playball.security")
if not _logger.handlers:
    _logger.setLevel(logging.INFO)
    fmt = logging.Formatter("%(asctime)s [SECURITY] %(levelname)s %(message)s",
                            datefmt="%Y-%m-%dT%H:%M:%S")
    # 파일 핸들러 (일별 로테이션 없이 단순 파일)
    fh = logging.FileHandler(os.path.join(_LOG_DIR, "security.log"), encoding="utf-8")
    fh.setFormatter(fmt)
    _logger.addHandler(fh)
    # stdout 핸들러
    sh = logging.StreamHandler()
    sh.setFormatter(fmt)
    _logger.addHandler(sh)


def log_login_fail(ip: str, email: str):
    _logger.warning("LOGIN_FAIL ip=%s email=%s", ip, email)


def log_login_ok(ip: str, user_id: int, email: str):
    _logger.info("LOGIN_OK ip=%s user_id=%d email=%s", ip, user_id, email)


def log_upload(ip: str, user_id: int, filename: str, size: int):
    _logger.info("UPLOAD ip=%s user_id=%d file=%s bytes=%d", ip, user_id, filename, size)


def log_admin_access(ip: str, endpoint: str, action: str, result: str):
    _logger.warning("ADMIN_ACCESS ip=%s endpoint=%s action=%s result=%s",
                    ip, endpoint, action, result)


def log_auth_fail(ip: str, detail: str):
    _logger.warning("AUTH_FAIL ip=%s detail=%s", ip, detail)
