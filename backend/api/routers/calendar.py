from fastapi import APIRouter, HTTPException
from database.connection import get_connection

router = APIRouter()


@router.get("/{year}/{month}")
def get_calendar(year: int, month: int):
    """월별 경기 일정 반환"""
    if not (1 <= month <= 12):
        raise HTTPException(status_code=400, detail="월은 1~12 사이여야 합니다")

    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT
                g.id,
                g.game_date,
                g.status,
                g.home_score,
                g.away_score,
                g.start_time,
                ht.name  AS home_team,
                ht.short_name AS home_team_code,
                at.name  AS away_team,
                at.short_name AS away_team_code,
                g.current_inning,
                g.inning_half,
                g.home_team_id,
                g.away_team_id
            FROM games g
            JOIN teams ht ON ht.id = g.home_team_id
            JOIN teams at ON at.id = g.away_team_id
            WHERE EXTRACT(YEAR  FROM g.game_date) = %s
              AND EXTRACT(MONTH FROM g.game_date) = %s
            ORDER BY g.game_date, g.start_time
        """, (year, month))
        rows = cur.fetchall()
        cur.close()
    finally:
        conn.close()

    games: dict = {}
    for row in rows:
        (gid, game_date, status, home_score, away_score, start_time,
         home_team, home_team_code, away_team, away_team_code,
         current_inning, inning_half, home_team_id, away_team_id) = row

        date_key = game_date.strftime("%Y-%m-%d")

        start_time_str = None
        if start_time is not None:
            # start_time may be a timedelta (psycopg2) or time object
            try:
                start_time_str = start_time.strftime("%H:%M")
            except AttributeError:
                # timedelta fallback
                total_seconds = int(start_time.total_seconds())
                h, rem = divmod(total_seconds, 3600)
                m = rem // 60
                start_time_str = f"{h:02d}:{m:02d}"

        game_entry = {
            "id": gid,
            "home_team": home_team,
            "away_team": away_team,
            "home_team_code": home_team_code,
            "away_team_code": away_team_code,
            "home_team_id": home_team_id,
            "away_team_id": away_team_id,
            "home_score": home_score,
            "away_score": away_score,
            "status": status,
            "start_time": start_time_str,
            "current_inning": current_inning,
            "inning_half": inning_half,
        }

        games.setdefault(date_key, []).append(game_entry)

    return {"year": year, "month": month, "games": games}
