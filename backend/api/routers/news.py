from fastapi import APIRouter, Query
from database.connection import get_connection

router = APIRouter(prefix="/news", tags=["news"])


@router.get("/team/{team_id}")
async def get_team_news(team_id: int, limit: int = Query(20, le=50)):
    conn = get_connection()
    if not conn:
        return {"news": []}
    cur = conn.cursor()
    cur.execute("""
        SELECT id, title, url, thumbnail, media, published_at, crawled_at
        FROM team_news
        WHERE team_id = %s
        ORDER BY COALESCE(published_at, crawled_at) DESC
        LIMIT %s
    """, (team_id, limit))
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return {
        "news": [
            {
                "id": r[0], "title": r[1], "url": r[2],
                "thumbnail": r[3], "media": r[4],
                "published_at": r[5].isoformat() if r[5] else None,
                "crawled_at": r[6].isoformat() if r[6] else None,
            }
            for r in rows
        ]
    }


@router.get("/")
async def get_news(team_id: int | None = Query(None), limit: int = Query(30, le=100)):
    conn = get_connection()
    if not conn:
        return {"news": []}
    cur = conn.cursor()
    if team_id:
        cur.execute("""
            SELECT n.id, n.title, n.url, n.thumbnail, n.media,
                   n.published_at, n.crawled_at, t.name
            FROM team_news n
            LEFT JOIN teams t ON n.team_id = t.id
            WHERE n.team_id = %s
            ORDER BY COALESCE(n.published_at, n.crawled_at) DESC
            LIMIT %s
        """, (team_id, limit))
    else:
        cur.execute("""
            SELECT n.id, n.title, n.url, n.thumbnail, n.media,
                   n.published_at, n.crawled_at, t.name
            FROM team_news n
            LEFT JOIN teams t ON n.team_id = t.id
            ORDER BY COALESCE(n.published_at, n.crawled_at) DESC
            LIMIT %s
        """, (limit,))
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return {
        "news": [
            {
                "id": r[0], "title": r[1], "url": r[2],
                "thumbnail": r[3], "media": r[4],
                "published_at": r[5].isoformat() if r[5] else None,
                "crawled_at": r[6].isoformat() if r[6] else None,
                "team_name": r[7],
            }
            for r in rows
        ]
    }
