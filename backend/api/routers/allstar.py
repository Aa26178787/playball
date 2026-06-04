"""올스타 팬투표 현황 API."""
from fastapi import APIRouter
from datetime import date
from database.connection import get_connection

router = APIRouter()


@router.get('/current')
def get_current_vote():
    """현재 진행 중인 올스타 팬투표 이벤트 반환 (없으면 null)."""
    conn = get_connection()
    if not conn:
        return {"event": None}
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT season, opens_at, closes_at, vote_url
            FROM allstar_vote_events
            WHERE closes_at >= CURRENT_DATE
            ORDER BY opens_at ASC
            LIMIT 1
        """)
        row = cur.fetchone()
        cur.close()
        if not row:
            return {"event": None}
        season, opens_at, closes_at, vote_url = row
        today = date.today()
        if today < opens_at:
            status = 'upcoming'
            days_left = (opens_at - today).days
        elif today <= closes_at:
            status = 'open'
            days_left = (closes_at - today).days
        else:
            status = 'closed'
            days_left = 0
        return {
            "event": {
                "season": season,
                "opens_at": opens_at.isoformat(),
                "closes_at": closes_at.isoformat(),
                "vote_url": vote_url or "",
                "status": status,
                "days_left": days_left,
            }
        }
    finally:
        conn.close()
