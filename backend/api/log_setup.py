"""중앙 로깅 설정 — api(uvicorn)와 scheduler 양 프로세스 공통.

서비스 모듈(fcm/weather/email/sms 등)은 `logging.getLogger(__name__)`만 쓰고,
엔트리포인트(main.py / scheduler.py __main__)에서 setup_logging()을 1회 호출한다.
uvicorn은 root logger에 핸들러를 달지 않아(level WARNING 유지) 기본 상태로는
logger.info가 출력되지 않으므로, root에 INFO 핸들러를 명시적으로 설정한다.
출력은 stdout → journalctl 캡처(기존 print 동작과 동일).
"""
import logging
import sys

_configured = False


def setup_logging(level: int = logging.INFO) -> None:
    global _configured
    if _configured:
        return
    root = logging.getLogger()
    if not root.handlers:
        logging.basicConfig(
            level=level,
            format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
            stream=sys.stdout,
        )
    else:
        # uvicorn 등이 이미 핸들러를 단 경우: level만 보정
        root.setLevel(level)
    _configured = True
