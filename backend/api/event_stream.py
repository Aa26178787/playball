"""게임 도메인 이벤트 스트림 (game_event_stream 테이블)

⚠️ 기존 game_events 테이블(naver_crawler가 적재하는 경기 이벤트 텍스트)과 별개 —
이름 충돌로 game_event_stream 사용.

scheduler가 감지하는 모든 경기 사건을 단일 스트림으로 발행한다.
소비자(현재/예정): 경기 타임라인·WPA 집계·과거경기 리플레이·아침 브리핑 소재.
발행은 알림 발송 여부와 무관 — 알림은 이벤트의 한 소비 형태일 뿐.

dedup: UNIQUE(game_id, event_type, dedup_key) + ON CONFLICT DO NOTHING
→ 재시작/재크롤 시 중복 발행 안전.
"""
import json
import logging

from database.connection import get_connection

logger = logging.getLogger(__name__)


def emit_event(game_id: int, event_type: str, payload: dict | None = None,
               inning: int | None = None, inning_half: str | None = None,
               dedup_key: str = '') -> bool:
    """이벤트 1건 발행. 실패해도 호출측 흐름 막지 않음(False 반환)."""
    conn = get_connection()
    if not conn:
        return False
    try:
        cur = conn.cursor()
        cur.execute(
            """INSERT INTO game_event_stream (game_id, event_type, inning, inning_half, payload, dedup_key)
               VALUES (%s, %s, %s, %s, %s, %s)
               ON CONFLICT (game_id, event_type, dedup_key) DO NOTHING""",
            (game_id, event_type, inning, inning_half,
             json.dumps(payload or {}, ensure_ascii=False), dedup_key)
        )
        conn.commit()
        cur.close()
        return True
    except Exception as e:
        logger.error(f"[events] emit 실패 game={game_id} type={event_type}: {e}")
        try:
            conn.rollback()
        except Exception:
            pass
        return False
    finally:
        conn.close()
