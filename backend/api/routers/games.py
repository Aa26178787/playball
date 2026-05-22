from fastapi import APIRouter, HTTPException
from database.connection import get_connection
from api.weather_service import get_weather, get_forecast_at

router = APIRouter()


def _batch_recent5(cur, team_ids: list) -> dict:
    """team_id → ['W','L','D',...] 최신순 5개"""
    if not team_ids:
        return {}
    cur.execute("""
        SELECT team_id, result FROM (
            SELECT
                t.team_id,
                CASE
                    WHEN g.home_team_id = t.team_id THEN
                        CASE WHEN g.home_score > g.away_score THEN 'W'
                             WHEN g.home_score < g.away_score THEN 'L'
                             ELSE 'D' END
                    ELSE
                        CASE WHEN g.away_score > g.home_score THEN 'W'
                             WHEN g.away_score < g.home_score THEN 'L'
                             ELSE 'D' END
                END as result,
                ROW_NUMBER() OVER (
                    PARTITION BY t.team_id
                    ORDER BY g.game_date DESC, g.id DESC
                ) as rn
            FROM UNNEST(%s::int[]) AS t(team_id)
            JOIN games g ON (g.home_team_id = t.team_id OR g.away_team_id = t.team_id)
            WHERE g.status = '종료'
        ) sub
        WHERE rn <= 5
        ORDER BY team_id, rn
    """, (team_ids,))
    result: dict = {}
    for tid, res in cur.fetchall():
        result.setdefault(tid, []).append(res)
    return result

import requests as req

NAVER_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    "Referer": "https://sports.naver.com/"
}


@router.get("/{game_id}/relay_all")
def get_game_relay_all(game_id: int):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()

    cur.execute("""
        SELECT naver_game_id, status, current_inning
        FROM games WHERE id = %s
    """, (game_id,))
    row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="경기를 찾을 수 없습니다")

    naver_game_id, status, current_inning = row

    cur.execute("""
        SELECT inning, home_runs, away_runs
        FROM game_innings WHERE game_id = %s ORDER BY inning
    """, (game_id,))
    innings = cur.fetchall()
    cur.close()
    conn.close()

    inning_scores = {
        "home": {str(r[0]): str(r[1]) for r in innings},
        "away": {str(r[0]): str(r[2]) for r in innings},
    }

    if status == '진행':
        pitcher_cache = {}

        def get_pitcher_name(naver_id):
            if not naver_id:
                return None
            naver_id = str(naver_id)
            if naver_id in pitcher_cache:
                return pitcher_cache[naver_id]
            conn2 = get_connection()
            if conn2:
                cur2 = conn2.cursor()
                cur2.execute(
                    "SELECT name FROM players WHERE naver_player_id = %s LIMIT 1",
                    (naver_id,)
                )
                row2 = cur2.fetchone()
                cur2.close()
                conn2.close()
                if row2:
                    pitcher_cache[naver_id] = row2[0]
                    return row2[0]
            return None

        all_relays = []
        current_batter = None
        current_pitcher = None
        prev_inning_half = None
        batter_last_pitch = {}
        last_win_rate = None

        try:
            for inning in range(1, (current_inning or 1) + 1):
                batter_last_pitch = {}
                prev_inning_half = None
                url = f"https://api-gw.sports.naver.com/schedule/games/{naver_game_id}/relay?inning={inning}"
                res = req.get(url, headers=NAVER_HEADERS, timeout=10)
                if res.status_code != 200:
                    continue
                data = res.json()
                relay = data.get('result', {}).get('textRelayData', {})
                text_relays = relay.get('textRelays', [])
                if relay.get('lastValidMetricOption'):
                    last_win_rate = relay.get('lastValidMetricOption')

                for item in reversed(text_relays):
                    inning_half = item.get('homeOrAway', '0')

                    if prev_inning_half is not None and inning_half != prev_inning_half:
                        current_batter = None
                        current_pitcher = None
                        batter_last_pitch = {}
                    prev_inning_half = inning_half

                    for opt in item.get('textOptions', []):
                        rtype = opt.get('type')

                        state = opt.get('currentGameState', {}) or {}
                        pitcher_naver_id = state.get('pitcher')
                        if pitcher_naver_id:
                            pitcher_name = get_pitcher_name(pitcher_naver_id)
                            if pitcher_name:
                                current_pitcher = pitcher_name

                        batter_record = opt.get('batterRecord') or {}
                        if batter_record.get('name'):
                            new_batter = batter_record.get('name')
                            if new_batter != current_batter:
                                if current_batter in batter_last_pitch:
                                    del batter_last_pitch[current_batter]
                            current_batter = new_batter

                        if rtype is None:
                            continue

                        pitch_num = opt.get('pitchNum')
                        if current_batter and pitch_num:
                            last = batter_last_pitch.get(current_batter, 0)
                            if pitch_num <= last:
                                pitch_num = last + 1
                            batter_last_pitch[current_batter] = pitch_num

                        all_relays.append({
                            "inning": inning,
                            "inning_half": inning_half,
                            "seqno": opt.get('seqno'),
                            "batter_name": current_batter,
                            "pitcher_name": current_pitcher,
                            "pitch_num": pitch_num,
                            "pitch_result": opt.get('pitchResult'),
                            "stuff": opt.get('stuff') or None,
                            "speed": int(opt.get('speed', 0) or 0),
                            "state": {
                                "strike": int(state.get('strike', 0) or 0),
                                "ball": int(state.get('ball', 0) or 0),
                                "out": int(state.get('out', 0) or 0),
                                "base1": state.get('base1') not in [None, '0', 0],
                                "base2": state.get('base2') not in [None, '0', 0],
                                "base3": state.get('base3') not in [None, '0', 0],
                                "home_score": state.get('homeScore'),
                                "away_score": state.get('awayScore'),
                            },
                            "title": opt.get('text', ''),
                            "text": item.get('title', ''),
                            "type": rtype,
                        })

            return {
                "relays": all_relays,
                "inning_scores": inning_scores,
                "source": "api"
            }

        except Exception as e:
            raise HTTPException(status_code=500, detail=f"중계 조회 실패: {str(e)}")

    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()

    cur.execute("""
        SELECT inning, inning_half, seqno, batter_name, pitcher_name,
               pitch_num, pitch_result, stuff, speed,
               strike, ball, out, base1, base2, base3,
               home_score, away_score, title, text, type
        FROM game_pitches
        WHERE game_id = %s
        ORDER BY inning, inning_half, seqno NULLS LAST
    """, (game_id,))
    pitches = cur.fetchall()

    cur.execute("""
        SELECT gp.team_side, p.name, gp.pitching_order
        FROM game_pitchers gp
        JOIN players p ON gp.player_id = p.id
        WHERE gp.game_id = %s
        ORDER BY gp.team_side, gp.pitching_order
    """, (game_id,))
    pitcher_rows = cur.fetchall()

    home_pitchers = [r[1] for r in pitcher_rows if r[0] == 'home']
    away_pitchers = [r[1] for r in pitcher_rows if r[0] == 'away']

    cur.close()
    conn.close()

    import re
    pitch_title_pattern = re.compile(r'^(\d+)구\s+(.+?)\s+(\d+)km/h\s+(.+)$')

    def parse_pitch_result(title):
        if not title:
            return None
        if '헛스윙' in title: return 'S'
        if '스트라이크' in title: return 'S'
        if '볼' in title and 'km/h' in title: return 'B'
        if '파울' in title: return 'F'
        if '타격' in title: return 'X'
        return None

    relay_list = []
    current_batter = None
    home_pitcher_idx = 0
    away_pitcher_idx = 0

    for p in pitches:
        inning = p[0]
        inning_half = p[1]
        title = p[17]
        text = p[18]
        rtype = p[19]
        pitch_num = p[5]
        pitch_result = p[6]
        speed = p[8]
        stuff = p[7]
        batter_name = p[3]

        if rtype == 8 and title and '번타자' in str(title):
            parts = title.split(' ')
            if len(parts) >= 2:
                current_batter = parts[-1]
        if batter_name:
            current_batter = batter_name
        elif current_batter:
            batter_name = current_batter

        if title and rtype == 1:
            m = pitch_title_pattern.match(title)
            if m:
                pitch_num = pitch_num or int(m.group(1))
                pitch_result = pitch_result or parse_pitch_result(title)
                stuff = stuff or m.group(4)
                speed = speed or int(m.group(3))

        if rtype == 2 and title and '투수' in title and '교체' in title:
            if inning_half == '0':
                home_pitcher_idx = min(home_pitcher_idx + 1, len(home_pitchers) - 1)
            else:
                away_pitcher_idx = min(away_pitcher_idx + 1, len(away_pitchers) - 1)

        pitcher_name = p[4]
        if not pitcher_name:
            if inning_half == '0':
                pitcher_name = home_pitchers[min(home_pitcher_idx, len(home_pitchers) - 1)] if home_pitchers else None
            else:
                pitcher_name = away_pitchers[min(away_pitcher_idx, len(away_pitchers) - 1)] if away_pitchers else None

        relay_list.append({
            "inning": inning,
            "inning_half": inning_half,
            "seqno": p[2],
            "batter_name": batter_name,
            "pitcher_name": pitcher_name,
            "pitch_num": pitch_num,
            "pitch_result": pitch_result,
            "stuff": stuff,
            "speed": speed,
            "state": {
                "strike": p[9] or 0,
                "ball": p[10] or 0,
                "out": p[11] or 0,
                "base1": p[12] or False,
                "base2": p[13] or False,
                "base3": p[14] or False,
                "home_score": p[15],
                "away_score": p[16],
            },
            "title": title,
            "text": text,
            "type": rtype,
        })

    # 이미 conn 닫혔으니 새 연결
    conn3 = get_connection()
    cur3 = conn3.cursor()
    cur3.execute("""
        SELECT home_win_rate, away_win_rate
        FROM game_pitches
        WHERE game_id = %s
        AND home_win_rate IS NOT NULL
        ORDER BY inning DESC, inning_half DESC, seqno DESC NULLS LAST
        LIMIT 1
    """, (game_id,))
    wr = cur3.fetchone()
    cur3.close()
    conn3.close()

    win_rate = None
    if wr:
        win_rate = {
            "homeTeamWinRate": float(wr[0]),
            "awayTeamWinRate": float(wr[1]),
        }
    else:
        # DB에 없으면 네이버 API에서 직접 가져오기
        try:
            last_inning = max((p[0] for p in pitches), default=1)
            wr_url = f"https://api-gw.sports.naver.com/schedule/games/{naver_game_id}/relay?inning={last_inning}"
            wr_res = req.get(wr_url, headers=NAVER_HEADERS, timeout=5)
            wr_data = wr_res.json().get('result', {}).get('textRelayData', {})
            metric = wr_data.get('lastValidMetricOption')
            if metric:
                win_rate = {
                    "homeTeamWinRate": metric.get('homeTeamWinRate'),
                    "awayTeamWinRate": metric.get('awayTeamWinRate'),
                }
        except Exception:
            pass

    return {
        "relays": relay_list,
        "inning_scores": inning_scores,
        "win_rate": win_rate,
        "source": "db",
    }




@router.get("/{game_id}/preview")
def get_game_preview(game_id: int):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("SELECT naver_game_id FROM games WHERE id = %s", (game_id,))
    row = cur.fetchone()
    cur.close()
    conn.close()

    if not row:
        raise HTTPException(status_code=404, detail="경기를 찾을 수 없습니다")

    naver_game_id = row[0]
    try:
        url = f"https://api-gw.sports.naver.com/schedule/games/{naver_game_id}/preview"
        res = req.get(url, headers=NAVER_HEADERS, timeout=10)
        res.raise_for_status()
        data = res.json()
        preview = data["result"]["previewData"]

        def parse_starter(starter):
            if not starter:
                return None
            info = starter.get("playerInfo", {})
            season = starter.get("currentSeasonStats", {})
            vs = starter.get("currentSeasonStatsOnOpponents", {})
            pit_kinds = starter.get("currentPitKindStats", [])
            return {
                "name":        info.get("name"),
                "back_number": info.get("backnum"),
                "hit_type":    info.get("hitType"),
                "height":      info.get("height"),
                "weight":      info.get("weight"),
                "season_stats": {
                    "games":   season.get("gameCount"),
                    "wins":    season.get("w"),
                    "losses":  season.get("l"),
                    "era":     season.get("era"),
                    "innings": season.get("inn"),
                    "kk":      season.get("kk"),
                    "bb":      season.get("bb"),
                    "whip":    season.get("whip"),
                },
                "vs_stats": {
                    "games":   vs.get("gameCount"),
                    "era":     vs.get("era"),
                    "innings": vs.get("inn"),
                    "kk":      vs.get("kk"),
                    "bb":      vs.get("bb"),
                },
                "pitch_kinds": [
                    {
                        "type":  pk.get("type"),
                        "ratio": pk.get("pit_rt"),
                        "speed": pk.get("speed"),
                    }
                    for pk in pit_kinds
                ],
            }

        def parse_top_player(top):
            if not top:
                return None
            info = top.get("playerInfo", {})
            season = top.get("currentSeasonStats", {})
            game = top.get("currentGamePlayerStats", {})
            hot_cold = top.get("hotColdZone", [])
            return {
                "name":        info.get("name"),
                "back_number": info.get("backnum"),
                "hit_type":    info.get("hitType"),
                "season_stats": {
                    "avg":  season.get("hra"),
                    "hr":   season.get("hr"),
                    "rbi":  season.get("rbi"),
                    "obp":  season.get("obp"),
                    "games": season.get("gameCount"),
                },
                "game_stats": {
                    "ab":     game.get("ab"),
                    "hit":    game.get("hit"),
                    "hr":     game.get("hr"),
                    "rbi":    game.get("rbi"),
                    "result": game.get("batResult"),
                },
                "hot_cold_zone": hot_cold,
            }

        season_vs = preview.get("seasonVsResult", {})

        return {
            "home_starter":    parse_starter(preview.get("homeStarter")),
            "away_starter":    parse_starter(preview.get("awayStarter")),
            "home_top_player": parse_top_player(preview.get("homeTopPlayer")),
            "away_top_player": parse_top_player(preview.get("awayTopPlayer")),
            "season_vs": {
                "home_wins":   season_vs.get("hw", 0),
                "home_losses": season_vs.get("hl", 0),
                "home_draws":  season_vs.get("hd", 0),
                "away_wins":   season_vs.get("aw", 0),
                "away_losses": season_vs.get("al", 0),
                "away_draws":  season_vs.get("ad", 0),
            },
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"프리뷰 조회 실패: {str(e)}")


@router.get("/{game_id}/record_detail")
def get_game_record_detail(game_id: int):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("SELECT naver_game_id FROM games WHERE id = %s", (game_id,))
    row = cur.fetchone()
    cur.close()
    conn.close()

    if not row:
        raise HTTPException(status_code=404, detail="경기를 찾을 수 없습니다")

    naver_game_id = row[0]
    try:
        url = f"https://api-gw.sports.naver.com/schedule/games/{naver_game_id}/record"
        res = req.get(url, headers=NAVER_HEADERS, timeout=10)
        res.raise_for_status()
        data = res.json()
        record = data["result"]["recordData"]

        team_pitching = record.get("teamPitchingBoxscore", {})
        key_stats = record.get("todayKeyStats", {})
        etc_records = record.get("etcRecords", [])
        recent_vs = record.get("recentVsGames", [])

        def parse_team_pitching(box):
            if not box:
                return {}
            if isinstance(box, dict):
                return {
                    "innings":     box.get("inn"),
                    "hits":        box.get("hit"),
                    "runs":        box.get("r"),
                    "earned_runs": box.get("er"),
                    "walks":       box.get("bbhp"),
                    "strikeouts":  box.get("kk"),
                    "home_runs":   box.get("hr"),
                    "at_bats":     box.get("ab"),
                    "pitch_count": box.get("bf"),
                }
            return {}

        return {
            "key_stats": {
                "home": {
                    "strikeouts":   key_stats.get("home", {}).get("kk"),
                    "hits":         key_stats.get("home", {}).get("hit"),
                    "errors":       key_stats.get("home", {}).get("err"),
                    "home_runs":    key_stats.get("home", {}).get("hr"),
                    "stolen_bases": key_stats.get("home", {}).get("sb"),
                },
                "away": {
                    "strikeouts":   key_stats.get("away", {}).get("kk"),
                    "hits":         key_stats.get("away", {}).get("hit"),
                    "errors":       key_stats.get("away", {}).get("err"),
                    "home_runs":    key_stats.get("away", {}).get("hr"),
                    "stolen_bases": key_stats.get("away", {}).get("sb"),
                },
            },
            "team_pitching": {
                "home": parse_team_pitching(team_pitching.get("home", [])),
                "away": parse_team_pitching(team_pitching.get("away", [])),
            },
            "etc_records": [
                {
                    "type":        e.get("how"),
                    "description": e.get("result"),
                }
                for e in etc_records
            ],
            "recent_vs": recent_vs,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"상세 기록 조회 실패: {str(e)}")


@router.get("/{game_id}/roster")
def get_game_roster(game_id: int):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("""
        SELECT p.name, p.number, p.profile_image,
               gr.team_side, gr.roster_type,
               gr.batting_order, gr.position, gr.pitching_style,
               gr.is_starter
        FROM game_rosters gr
        JOIN players p ON gr.player_id = p.id
        WHERE gr.game_id = %s
        ORDER BY gr.team_side, gr.roster_type,
                 gr.is_starter DESC,
                 gr.batting_order NULLS LAST,
                 p.name
    """, (game_id,))
    rows = cur.fetchall()
    cur.close()
    conn.close()

    home_batters = []
    home_pitchers = []
    away_batters = []
    away_pitchers = []

    for r in rows:
        player = {
            "name":           r[0],
            "number":         r[1],
            "profile_image":  r[2],
            "position":       r[6],
            "batting_order":  r[5] if r[5] and r[5] != 0 else None,
            "pitching_style": r[7],
            "is_starter":     r[8],
        }
        if r[3] == 'home' and r[4] == 'batter':
            home_batters.append(player)
        elif r[3] == 'home' and r[4] == 'pitcher':
            home_pitchers.append(player)
        elif r[3] == 'away' and r[4] == 'batter':
            away_batters.append(player)
        elif r[3] == 'away' and r[4] == 'pitcher':
            away_pitchers.append(player)

    return {
        "home": {"batters": home_batters, "pitchers": home_pitchers},
        "away": {"batters": away_batters, "pitchers": away_pitchers},
    }


@router.get("/today")
def get_today_games():
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("""
        SELECT
            g.id, g.game_date, g.status,
            g.home_score, g.away_score,
            g.current_inning, g.inning_half,
            ht.name AS home_team,
            ht.short_name AS home_team_code,
            at.name AS away_team,
            at.short_name AS away_team_code,
            s.name AS stadium,
            g.stadium_id, g.start_time,
            g.home_team_id, g.away_team_id
        FROM games g
        JOIN teams ht ON g.home_team_id = ht.id
        JOIN teams at ON g.away_team_id = at.id
        LEFT JOIN stadiums s ON g.stadium_id = s.id
        WHERE g.game_date = CURRENT_DATE
        ORDER BY g.id
    """)

    rows = cur.fetchall()

    all_team_ids = list({tid for r in rows for tid in (r[14], r[15]) if tid})
    recent5_map = _batch_recent5(cur, all_team_ids)

    cur.close()
    conn.close()

    # 구장별 날씨 캐시 (같은 구장 중복 호출 방지)
    weather_cache: dict = {}

    games = []
    for r in rows:
        stadium_id = r[12]
        start_time = r[13]

        weather = None
        if stadium_id and stadium_id not in weather_cache:
            start_hour = None
            if start_time:
                try:
                    total_sec = int(start_time.total_seconds())
                    start_hour = (total_sec // 3600 + 9) % 24  # UTC→KST
                except Exception:
                    pass
            weather_cache[stadium_id] = (
                get_forecast_at(stadium_id, start_hour) if start_hour is not None
                else get_weather(stadium_id)
            )
        weather = weather_cache.get(stadium_id)

        games.append({
            "id":             r[0],
            "game_date":      str(r[1]),
            "status":         r[2],
            "home_score":     r[3],
            "away_score":     r[4],
            "current_inning": r[5],
            "inning_half":    r[6],
            "home_team":      r[7],
            "home_team_code": r[8],
            "away_team":      r[9],
            "away_team_code": r[10],
            "stadium":        r[11],
            "stadium_id":     stadium_id,
            "weather":        weather,
            "home_team_id":   r[14],
            "away_team_id":   r[15],
            "home_recent_5":  recent5_map.get(r[14], []),
            "away_recent_5":  recent5_map.get(r[15], []),
        })

    return {"games": games, "count": len(games)}


@router.get("/{game_id}")
def get_game_detail(game_id: int):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()

    cur.execute("""
        SELECT
            g.id, g.game_date, g.status,
            g.home_score, g.away_score,
            g.current_inning, g.inning_half,
            g.home_hits, g.away_hits,
            g.home_errors, g.away_errors,
            ht.name AS home_team,
            at.name AS away_team,
            s.name AS stadium,
            g.naver_game_id,
            g.home_team_id,
            g.away_team_id
        FROM games g
        JOIN teams ht ON g.home_team_id = ht.id
        JOIN teams at ON g.away_team_id = at.id
        LEFT JOIN stadiums s ON g.stadium_id = s.id
        WHERE g.id = %s
    """, (game_id,))
    game = cur.fetchone()

    if not game:
        raise HTTPException(status_code=404, detail="경기를 찾을 수 없습니다")

    status = game[2]
    naver_game_id = game[14]
    home_team_id = game[15]
    away_team_id = game[16]

    cur.execute("""
        SELECT inning, home_runs, away_runs
        FROM game_innings
        WHERE game_id = %s
        ORDER BY inning
    """, (game_id,))
    innings = cur.fetchall()

    # 투수 - 진행 중이면 game_rosters 선발투수, 종료면 game_pitchers
    if status == '진행':
        cur.execute("""
            SELECT p.name, gp.role, gp.result,
                gp.innings_pitched, gp.strikeouts,
                gp.earned_runs, gp.team_side,
                gp.walks, gp.hits_allowed,
                gp.runs_allowed, gp.home_runs_allowed,
                gp.pitch_count, p.profile_image
            FROM game_pitchers gp
            JOIN players p ON gp.player_id = p.id
            WHERE gp.game_id = %s
            AND p.name IN (
                SELECT DISTINCT pitcher_name
                FROM game_pitches
                WHERE game_id = %s
                AND type = 1
                AND pitcher_name IS NOT NULL
            )
            ORDER BY gp.team_side, gp.pitching_order ASC
        """, (game_id, game_id))
    else:
        cur.execute("""
            SELECT p.name, gp.role, gp.result,
                gp.innings_pitched, gp.strikeouts,
                gp.earned_runs, gp.team_side,
                gp.walks, gp.hits_allowed,
                gp.runs_allowed, gp.home_runs_allowed,
                gp.pitch_count, p.profile_image
            FROM game_pitchers gp
            JOIN players p ON gp.player_id = p.id
            WHERE gp.game_id = %s
            ORDER BY gp.team_side, gp.pitching_order ASC
        """, (game_id,))
    pitchers = cur.fetchall()

    cur.execute("""
        SELECT p.name, gb.batting_order, gb.position,
            gb.at_bats, gb.hits, gb.rbis,
            gb.home_runs, gb.avg, gb.team_side
        FROM game_batters gb
        JOIN players p ON gb.player_id = p.id
        WHERE gb.game_id = %s
        AND gb.position != '투'
        AND gb.batting_order != 0
        ORDER BY gb.team_side, gb.batting_order
    """, (game_id,))
    batters = cur.fetchall()

    cur.execute("""
        SELECT
            SUM(CASE WHEN gb.team_side = 'home' THEN gb.hits ELSE 0 END),
            SUM(CASE WHEN gb.team_side = 'away' THEN gb.hits ELSE 0 END),
            SUM(CASE WHEN gb.team_side = 'home' THEN gb.walks ELSE 0 END),
            SUM(CASE WHEN gb.team_side = 'away' THEN gb.walks ELSE 0 END)
        FROM game_batters gb
        WHERE gb.game_id = %s
    """, (game_id,))
    hits_row = cur.fetchone()
    home_hits_calc = int(hits_row[0] or 0) if hits_row else 0
    away_hits_calc = int(hits_row[1] or 0) if hits_row else 0
    home_walks_calc = int(hits_row[2] or 0) if hits_row else 0
    away_walks_calc = int(hits_row[3] or 0) if hits_row else 0

    recent5_map = _batch_recent5(cur, [home_team_id, away_team_id])
    home_recent_5 = recent5_map.get(home_team_id, [])
    away_recent_5 = recent5_map.get(away_team_id, [])

    cur.close()
    conn.close()

    home_errors = game[9] or 0
    away_errors = game[10] or 0

    if status == '진행' and naver_game_id:
        try:
            inning = game[5] or 1
            url = f"https://api-gw.sports.naver.com/schedule/games/{naver_game_id}/relay?inning={inning}"
            r = req.get(url, headers=NAVER_HEADERS, timeout=5)
            relay = r.json().get('result', {}).get('textRelayData', {})
            state = relay.get('currentGameState', {}) or {}
            home_errors = int(state.get('homeError', 0) or 0)
            away_errors = int(state.get('awayError', 0) or 0)
        except Exception:
            pass

    return {
        "game": {
            "id":             game[0],
            "game_date":      str(game[1]),
            "status":         game[2],
            "home_score":     game[3],
            "away_score":     game[4],
            "current_inning": game[5],
            "inning_half":    game[6],
            "home_hits":      home_hits_calc,
            "away_hits":      away_hits_calc,
            "home_walks":     home_walks_calc,
            "away_walks":     away_walks_calc,
            "home_errors":    home_errors,
            "away_errors":    away_errors,
            "home_team":      game[11],
            "away_team":      game[12],
            "stadium":        game[13],
            "home_recent_5":  home_recent_5,
            "away_recent_5":  away_recent_5,
        },
        "innings": [
            {"inning": r[0], "home_runs": r[1], "away_runs": r[2]}
            for r in innings
        ],
        "pitchers": [
            {
                "name":              r[0],
                "role":              r[1],
                "result":            r[2],
                "innings_pitched":   float(r[3]) if r[3] else 0,
                "strikeouts":        r[4],
                "earned_runs":       r[5],
                "team_side":         r[6],
                "walks":             r[7] or 0,
                "hits_allowed":      r[8] or 0,
                "runs_allowed":      r[9] or 0,
                "home_runs_allowed": r[10] or 0,
                "pitch_count":       r[11] or 0,
                "profile_image":     r[12],
            }
            for r in pitchers
        ],
        "batters": [
            {
                "name":          r[0],
                "batting_order": r[1],
                "position":      r[2],
                "at_bats":       r[3],
                "hits":          r[4],
                "rbis":          r[5],
                "home_runs":     r[6],
                "avg":           float(r[7]) if r[7] else 0,
                "team_side":     r[8],
            }
            for r in batters
        ],
    }


@router.get("/date/{date_str}")
def get_games_by_date(date_str: str):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("""
        SELECT
            g.id, g.game_date, g.status,
            g.home_score, g.away_score,
            g.current_inning, g.inning_half,
            g.start_time,
            ht.name AS home_team,
            ht.short_name AS home_team_code,
            at.name AS away_team,
            at.short_name AS away_team_code,
            s.name AS stadium,
            wp.name AS win_pitcher,
            lp.name AS lose_pitcher,
            EXISTS (
                SELECT 1 FROM game_rosters gr
                WHERE gr.game_id = g.id
                AND gr.is_starter = TRUE
                AND gr.roster_type = 'batter'
            ) AS has_lineup,
            home_sp.name AS home_starter,
            away_sp.name AS away_starter
        FROM games g
        JOIN teams ht ON g.home_team_id = ht.id
        JOIN teams at ON g.away_team_id = at.id
        LEFT JOIN stadiums s ON g.stadium_id = s.id
        LEFT JOIN (
            SELECT gp.game_id, p.name
            FROM game_pitchers gp
            JOIN players p ON gp.player_id = p.id
            WHERE gp.result = '승'
        ) wp ON wp.game_id = g.id
        LEFT JOIN (
            SELECT gp.game_id, p.name
            FROM game_pitchers gp
            JOIN players p ON gp.player_id = p.id
            WHERE gp.result = '패'
        ) lp ON lp.game_id = g.id
        LEFT JOIN LATERAL (
            SELECT p.name FROM game_rosters gr
            JOIN players p ON gr.player_id = p.id
            WHERE gr.game_id = g.id AND gr.roster_type = 'pitcher'
            AND gr.is_starter = TRUE AND gr.team_side = 'home'
            LIMIT 1
        ) home_sp ON TRUE
        LEFT JOIN LATERAL (
            SELECT p.name FROM game_rosters gr
            JOIN players p ON gr.player_id = p.id
            WHERE gr.game_id = g.id AND gr.roster_type = 'pitcher'
            AND gr.is_starter = TRUE AND gr.team_side = 'away'
            LIMIT 1
        ) away_sp ON TRUE
        WHERE g.game_date = %s
        ORDER BY g.start_time, g.id
    """, (date_str,))

    rows = cur.fetchall()

    # stadium_id + team_id 별도 조회
    game_ids = [r[0] for r in rows]
    stadium_map: dict = {}
    home_team_id_map: dict = {}
    away_team_id_map: dict = {}
    if game_ids:
        cur.execute(
            "SELECT id, stadium_id, home_team_id, away_team_id FROM games WHERE id = ANY(%s)",
            (game_ids,)
        )
        for gid, sid, htid, atid in cur.fetchall():
            stadium_map[gid] = sid
            home_team_id_map[gid] = htid
            away_team_id_map[gid] = atid

    all_team_ids_date = list({
        tid for gid in game_ids
        for tid in (home_team_id_map.get(gid), away_team_id_map.get(gid))
        if tid
    })
    recent5_map_date = _batch_recent5(cur, all_team_ids_date)

    cur.close()
    conn.close()

    # 오늘 날짜 경기만 날씨 포함 (과거 날짜는 스킵)
    from datetime import date as _date
    is_today = (date_str == str(_date.today()))
    weather_cache: dict = {}

    seen_ids = set()
    games = []
    for r in rows:
        if r[0] in seen_ids:
            continue
        seen_ids.add(r[0])

        status = r[2]
        has_lineup = r[15]
        win_pitcher = r[13]
        lose_pitcher = r[14]

        if status == '예정' and has_lineup:
            status = '라인업'

        weather = None
        if is_today:
            stadium_id = stadium_map.get(r[0])
            if stadium_id and stadium_id not in weather_cache:
                start_time = r[7]
                start_hour = None
                if start_time:
                    try:
                        total_sec = int(start_time.total_seconds())
                        start_hour = (total_sec // 3600 + 9) % 24
                    except Exception:
                        pass
                weather_cache[stadium_id] = (
                    get_forecast_at(stadium_id, start_hour) if start_hour is not None
                    else get_weather(stadium_id)
                )
            weather = weather_cache.get(stadium_map.get(r[0]))

        games.append({
            "id":             r[0],
            "game_date":      str(r[1]),
            "status":         status,
            "home_score":     r[3],
            "away_score":     r[4],
            "current_inning": r[5],
            "inning_half":    r[6],
            "start_time":     str(r[7])[:5] if r[7] else None,
            "home_team":      r[8],
            "home_team_code": r[9],
            "away_team":      r[10],
            "away_team_code": r[11],
            "stadium":        r[12],
            "win_pitcher":    win_pitcher,
            "lose_pitcher":   lose_pitcher,
            "is_draw":        r[2] == '종료' and not win_pitcher and not lose_pitcher,
            "home_starter":   r[16],
            "away_starter":   r[17],
            "weather":        weather,
            "home_team_id":   home_team_id_map.get(r[0]),
            "away_team_id":   away_team_id_map.get(r[0]),
            "home_recent_5":  recent5_map_date.get(home_team_id_map.get(r[0]), []),
            "away_recent_5":  recent5_map_date.get(away_team_id_map.get(r[0]), []),
        })

    return {"games": games, "count": len(games)}


@router.get("/{game_id}/relay")
def get_game_relay(game_id: int):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("""
        SELECT naver_game_id, status, current_inning
        FROM games WHERE id = %s
    """, (game_id,))
    game = cur.fetchone()
    cur.close()
    conn.close()

    if not game:
        raise HTTPException(status_code=404, detail="경기를 찾을 수 없습니다")

    naver_game_id, status, current_inning = game

    if status != '진행':
        raise HTTPException(status_code=400, detail="진행 중인 경기가 아닙니다")

    inning = current_inning or 1

    try:
        url = f"https://api-gw.sports.naver.com/schedule/games/{naver_game_id}/relay?inning={inning}"
        res = req.get(url, headers=NAVER_HEADERS, timeout=10)
        res.raise_for_status()
        data = res.json()

        if not data.get("success"):
            raise HTTPException(status_code=500, detail="네이버 API 응답 실패")

        relay = data["result"]["textRelayData"]
        game_state = relay.get("currentGameState", {})

        return {
            "game_id":      game_id,
            "inning":       relay.get("inn"),
            "home_or_away": relay.get("homeOrAway"),
            "current_state": {
                "strike":     int(game_state.get("strike", 0)),
                "ball":       int(game_state.get("ball", 0)),
                "out":        int(game_state.get("out", 0)),
                "base1":      game_state.get("base1") not in [None, "0", 0],
                "base2":      game_state.get("base2") not in [None, "0", 0],
                "base3":      game_state.get("base3") not in [None, "0", 0],
                "home_score": game_state.get("homeScore"),
                "away_score": game_state.get("awayScore"),
                "home_hit":   game_state.get("homeHit"),
                "away_hit":   game_state.get("awayHit"),
                "home_error": game_state.get("homeError"),
                "away_error": game_state.get("awayError"),
            },
            "pitcher_vs_batter": relay.get("pitcherVsBatterCareerStats"),
            "home_entry": {
                "batters":  relay.get("homeEntry", {}).get("batter", []),
                "pitchers": relay.get("homeEntry", {}).get("pitcher", []),
            },
            "away_entry": {
                "batters":  relay.get("awayEntry", {}).get("batter", []),
                "pitchers": relay.get("awayEntry", {}).get("pitcher", []),
            },
            "home_lineup": relay.get("homeLineup", {}).get("batter", []),
            "away_lineup": relay.get("awayLineup", {}).get("batter", []),
            "text_relays": [
                {
                    "no":           r.get("no"),
                    "title":        r.get("title"),
                    "text":         r.get("text"),
                    "type":         r.get("type"),
                    "pitch_num":    r.get("pitchNum"),
                    "pitch_result": r.get("pitchResult"),
                    "speed":        r.get("speed"),
                    "state": {
                        "strike": int(r.get("currentGameState", {}).get("strike", 0)),
                        "ball":   int(r.get("currentGameState", {}).get("ball", 0)),
                        "out":    int(r.get("currentGameState", {}).get("out", 0)),
                        "base1":  r.get("currentGameState", {}).get("base1") not in [None, "0", 0],
                        "base2":  r.get("currentGameState", {}).get("base2") not in [None, "0", 0],
                        "base3":  r.get("currentGameState", {}).get("base3") not in [None, "0", 0],
                    } if r.get("currentGameState") else None,
                }
                for r in relay.get("textRelays", [])
            ],
            "win_rate": relay.get("lastValidMetricOption", {}),
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"중계 데이터 조회 실패: {str(e)}")


@router.get("/{game_id}/pitch-types")
def get_pitch_types(game_id: int):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("SELECT id FROM games WHERE id = %s", (game_id,))
    if not cur.fetchone():
        raise HTTPException(status_code=404, detail="경기를 찾을 수 없습니다")
    cur.execute("""
        SELECT pitcher_name, stuff, COUNT(*) as cnt
        FROM game_pitches
        WHERE game_id = %s
          AND type = 1
          AND stuff IS NOT NULL AND stuff != ''
        GROUP BY pitcher_name, stuff
        ORDER BY pitcher_name, cnt DESC
    """, (game_id,))
    rows = cur.fetchall()
    cur.close()
    conn.close()
    pitchers: dict = {}
    for pitcher_name, stuff, cnt in rows:
        pitchers.setdefault(pitcher_name, []).append({'type': stuff, 'count': int(cnt)})
    for types in pitchers.values():
        total = sum(t['count'] for t in types)
        for t in types:
            t['pct'] = round(t['count'] / total * 100)
    return {'pitchers': pitchers}



@router.get("/{game_id}/pitch-locations")
def get_pitch_locations(game_id: int):
    import math as _math
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("""
        SELECT g.naver_game_id, g.status, g.current_inning,
               GREATEST(COALESCE(MAX(gi.inning), 1), COALESCE(g.current_inning, 1))
        FROM games g
        LEFT JOIN game_innings gi ON g.id = gi.game_id
        WHERE g.id = %s
        GROUP BY g.naver_game_id, g.status, g.current_inning
    """, (game_id,))
    row = cur.fetchone()
    if not row or not row[0]:
        cur.close(); conn.close()
        raise HTTPException(status_code=404, detail="경기 없음")
    naver_game_id = row[0]
    game_status = row[1]
    max_inning = row[3] or 9

    # Build pitcher naver_id -> name cache
    cur.execute("SELECT naver_player_id, name FROM players WHERE naver_player_id IS NOT NULL")
    pitcher_cache = {str(r[0]): r[1] for r in cur.fetchall()}
    cur.close(); conn.close()

    def compute_z(p):
        try:
            y0, vy0, ay = p["y0"], p["vy0"], p["ay"]
            z0, vz0, az = p["z0"], p["vz0"], p["az"]
            A = 0.5*ay; B = vy0; C = y0
            disc = B*B - 4*A*C
            if disc < 0: return None
            t1 = (-B - _math.sqrt(disc))/(2*A); t2 = (-B + _math.sqrt(disc))/(2*A)
            valid = [t for t in [t1,t2] if t > 0]
            if not valid: return None
            t = min(valid)
            return round(z0 + vz0*t + 0.5*az*t**2, 4)
        except Exception:
            return None

    def classify(text):
        if not text: return "other"
        if "볼" in text: return "ball"
        if "헛스윙" in text or "스윙" in text: return "swing"
        if "파울" in text: return "foul"
        if "타격" in text or "안타" in text or "홈런" in text: return "hit"
        if "스트라이크" in text: return "strike"
        return "other"

    all_pitches = []
    for inning in range(1, max_inning + 1):
        try:
            url = f"https://api-gw.sports.naver.com/schedule/games/{naver_game_id}/relay?inning={inning}"
            res = req.get(url, headers=NAVER_HEADERS, timeout=8)
            if res.status_code != 200: continue
            text_relays = res.json().get("result", {}).get("textRelayData", {}).get("textRelays", [])
        except Exception:
            continue

        for item in text_relays:
            pts_opts = item.get("ptsOptions", [])
            txt_opts = item.get("textOptions", [])
            batter = item.get("title", "")
            inning_half = str(item.get("homeOrAway", ""))
            if not pts_opts: continue

            pitch_txts = [o for o in txt_opts if o.get("type") == 1]
            pitcher_name = ""
            for opt in txt_opts:
                gs = opt.get("currentGameState") or {}
                pid = str(gs.get("pitcher") or "")
                if pid and pid in pitcher_cache:
                    pitcher_name = pitcher_cache[pid]
                    break

            for i, pts in enumerate(pts_opts):
                x = pts.get("crossPlateX")
                z = compute_z(pts)
                if x is None or z is None: continue
                result_text = ""
                stuff = ""
                if i < len(pitch_txts):
                    opt = pitch_txts[i]
                    result_text = opt.get("text") or ""
                    stuff = opt.get("stuff") or ""
                all_pitches.append({
                    "inning":      inning,
                    "inning_half": inning_half,
                    "batter":      batter,
                    "pitcher":     pitcher_name,
                    "pitch_num":   i + 1,
                    "x":           round(float(x), 4),
                    "z":           z,
                    "top_sz":      pts.get("topSz"),
                    "bot_sz":      pts.get("bottomSz"),
                    "stuff":       stuff,
                    "result_text": result_text,
                    "result":      classify(result_text),
                    "stance":      pts.get("stance", "R"),
                })

    pitchers = sorted({p["pitcher"] for p in all_pitches if p["pitcher"]})
    return {"pitches": all_pitches, "pitchers": pitchers}

@router.get("/{game_id}/weather")
def get_game_weather(game_id: int):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute(
        "SELECT stadium_id, start_time, status FROM games WHERE id = %s",
        (game_id,)
    )
    row = cur.fetchone()
    cur.close()
    conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="경기를 찾을 수 없습니다")
    stadium_id, start_time, status = row
    if not stadium_id:
        return {"weather": None}
    start_hour = None
    if start_time:
        try:
            total_sec = int(start_time.total_seconds())
            start_hour = (total_sec // 3600 + 9) % 24
        except Exception:
            pass
    if status in ('예정', '라인업') and start_hour is not None:
        weather = get_forecast_at(stadium_id, start_hour)
    else:
        weather = get_weather(stadium_id)
    return {"weather": weather}