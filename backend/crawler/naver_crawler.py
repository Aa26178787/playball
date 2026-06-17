import re
import requests
import sys
import os
from datetime import datetime

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from database.connection import get_connection

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    "Referer": "https://sports.naver.com/"
}

BASE_API = "https://api-gw.sports.naver.com/schedule/games"

KBO_TEAM_CODES = {"HH", "HT", "LG", "LT", "NC", "OB", "SK", "SS", "WO", "KT"}

STADIUM_NAME_MAP = {
    '잠실': '서울종합운동장 야구장',
    '고척': '고척 스카이돔',
    '수원': '수원 KT 위즈 파크',
    '인천': '인천 SSG 랜더스필드',
    '문학': '인천 SSG 랜더스필드',
    '대전': '대전 한화생명 볼파크',
    '광주': '광주-기아 챔피언스 필드',
    '대구': '대구 삼성 라이온즈 파크',
    '창원': '창원NC파크',
    '사직': '사직 야구장',
    '부산': '사직 야구장',
}

POSITION_MAP = {
    '투': '투수', '포': '포수',
    '一': '1루수', '二': '2루수', '三': '3루수',
    '유': '유격수', '좌': '좌익수', '중': '중견수', '우': '우익수',
    '지': '지명타자', '주': '주자', '타': '대타',
    '二三': '2·3루수', '一二': '1·2루수', '二一': '2·1루수',
    '三二': '3·2루수', '一三': '1·3루수', '三유': '3루·유격',
    '유三': '유격·3루', '중좌': '중·좌익', '좌중': '좌·중견',
    '우중': '우·중견', '중우': '중·우익', '一유': '1루·유격',
    '유一': '유격·1루', '二유': '2루·유격', '유二': '유격·2루',
    '주一': '주자→1루', '주二': '주자→2루', '주三': '주자→3루',
    '주유': '주자→유격', '주좌': '주자→좌익',
    '주중': '주자→중견', '주우': '주자→우익', '주포': '주자→포수',
    '타포': '대타→포수', '타유': '대타→유격', '타一': '대타→1루',
    '타二': '대타→2루', '타三': '대타→3루', '타좌': '대타→좌익',
    '타중': '대타→중견', '타우': '대타→우익', '타지': '대타→지명',
}


def save_game_pitches(db_game_id, naver_game_id, inning):
    """진행 중인 경기 투구 데이터 저장"""
    try:
        url = f"https://api-gw.sports.naver.com/schedule/games/{naver_game_id}/relay?inning={inning}"
        res = requests.get(url, headers=HEADERS, timeout=10)
        res.raise_for_status()
        data = res.json()
        relay = data.get('result', {}).get('textRelayData', {})
        text_relays = relay.get('textRelays', [])

        if not text_relays:
            return

        conn = get_connection()
        if not conn:
            return
        cur = conn.cursor()

        # 이닝 단위 replace — seqno는 Naver 부여값이라 크롤마다 불안정(투수판 이탈/마운드 방문/투수교체
        # 등 사후삽입 이벤트가 뒤 seqno 시프트). 옛 ON CONFLICT(...,seqno,type) 방식은 시프트된 동일
        # 이벤트를 새 행으로 INSERT → 이닝 통째 offset 중복 누적(325 6회 사례). Naver relay는 누적
        # 발행이라 매 크롤이 직전 이상 완전 → DELETE 후 fresh INSERT가 안전(단일 클린 카피).
        # win_rate(결과행만 보유, 과거 크롤만 가진 경우 有)는 DELETE 전 보존 후 NULL일 때만 재병합.
        cur.execute("""SELECT inning_half, text, home_win_rate, away_win_rate
                       FROM game_pitches WHERE game_id=%s AND inning=%s AND type=13
                         AND (home_win_rate IS NOT NULL OR away_win_rate IS NOT NULL)""",
                    (db_game_id, inning))
        _wr_keep = {(r[0], r[1]): (r[2], r[3]) for r in cur.fetchall()}
        cur.execute("DELETE FROM game_pitches WHERE game_id=%s AND inning=%s", (db_game_id, inning))

        current_batter = None
        current_pitcher = None
        prev_inning_half = None
        pitcher_cache = {}

        for item in reversed(text_relays):
            text_options = item.get('textOptions', [])
            if not text_options:
                continue

            inning_half = item.get('homeOrAway', '0')
            # 승률(metricOption)은 textRelays 항목(타석) 레벨에 있음 — textOptions 내부 아님.
            # (2026-06-11 발견: 5/9 개편 후 win_rate 전부 NULL이던 원인 = 조회 레벨 착오)
            item_metric = item.get('metricOption') or {}

            if prev_inning_half is not None and inning_half != prev_inning_half:
                current_batter = None
                current_pitcher = None
            prev_inning_half = inning_half

            for opt in text_options:
                rtype = opt.get('type')
                seqno = opt.get('seqno')
                text = opt.get('text', '') or ''

                # currentGameState.pitcher로 투수 추적
                state = opt.get('currentGameState', {}) or {}
                pitcher_naver_id = state.get('pitcher')
                if pitcher_naver_id:
                    pitcher_naver_id = str(pitcher_naver_id)
                    if pitcher_naver_id not in pitcher_cache:
                        cur.execute(
                            "SELECT name FROM players WHERE naver_player_id = %s LIMIT 1",
                            (pitcher_naver_id,)
                        )
                        row = cur.fetchone()
                        if row:
                            pitcher_cache[pitcher_naver_id] = row[0]
                    if pitcher_naver_id in pitcher_cache:
                        current_pitcher = pitcher_cache[pitcher_naver_id]

                batter_record = opt.get('batterRecord') or {}
                if batter_record.get('name'):
                    current_batter = batter_record.get('name')
                elif rtype == 8 and text:
                    m = re.match(r'^(?:\d+번타자|대타)\s+(\S+)', text)
                    if m:
                        current_batter = m.group(1).strip()

                if rtype is None:
                    continue

                # 타석 결과(13) 행에만 승률 기록 — '타석 종료 후 승률' 의미 유지
                # (PA 파서가 before=직전 13행, after=현재 13행으로 해석)
                metric = opt.get('metricOption') or (item_metric if rtype == 13 else {})
                home_win_rate = metric.get('homeTeamWinRate')
                away_win_rate = metric.get('awayTeamWinRate')
                # 이번 크롤이 win_rate 미제공이면 보존값(과거 크롤분) 재병합 — replace로 유실 방지
                if rtype == 13 and home_win_rate is None and away_win_rate is None:
                    _kept = _wr_keep.get((inning_half, text))
                    if _kept:
                        home_win_rate, away_win_rate = _kept

                cur.execute("""
                    INSERT INTO game_pitches (
                        game_id, inning, inning_half, seqno,
                        batter_name, pitcher_name,
                        pitch_num, pitch_result, stuff, speed,
                        strike, ball, out,
                        base1, base2, base3,
                        home_score, away_score,
                        title, text, type,
                        home_win_rate, away_win_rate
                    ) VALUES (
                        %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,
                        %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s
                    )
                    ON CONFLICT (game_id, inning, inning_half, seqno, type)
                    WHERE seqno IS NOT NULL
                    DO UPDATE SET
                        batter_name = EXCLUDED.batter_name,
                        pitcher_name = EXCLUDED.pitcher_name,
                        home_win_rate = COALESCE(EXCLUDED.home_win_rate, game_pitches.home_win_rate),
                        away_win_rate = COALESCE(EXCLUDED.away_win_rate, game_pitches.away_win_rate)
                """, (
                    db_game_id, inning, inning_half, seqno,
                    current_batter, current_pitcher,
                    opt.get('pitchNum'),
                    opt.get('pitchResult'),
                    opt.get('stuff') or None,
                    int(opt.get('speed', 0) or 0),
                    int(state.get('strike', 0) or 0),
                    int(state.get('ball', 0) or 0),
                    int(state.get('out', 0) or 0),
                    state.get('base1') not in [None, '0', 0],
                    state.get('base2') not in [None, '0', 0],
                    state.get('base3') not in [None, '0', 0],
                    state.get('homeScore'),
                    state.get('awayScore'),
                    text,
                    item.get('title', ''),
                    rtype,
                    home_win_rate,
                    away_win_rate,
                ))

        conn.commit()
        cur.close()
        conn.close()
        print(f"경기 {db_game_id} {inning}회 투구 데이터 저장")

    except Exception as e:
        print(f"투구 데이터 저장 오류: {e}")


def convert_position(pos):
    if not pos:
        return ''
    return POSITION_MAP.get(pos, pos)


def get_games_by_date(date_str=None):
    if date_str is None:
        date_str = datetime.today().strftime("%Y-%m-%d")

    url = (
        f"{BASE_API}?fields=basic%2Cschedule%2Cbaseball%2CmanualRelayUrl"
        f"&upperCategoryId=kbaseball"
        f"&fromDate={date_str}&toDate={date_str}&size=500"
    )

    try:
        res = requests.get(url, headers=HEADERS, timeout=10)
        res.raise_for_status()
        data = res.json()

        if not data.get("success"):
            print("API 응답 실패")
            return []

        games = []
        for game in data["result"]["games"]:
            games.append({
                "game_id":        game.get("gameId"),
                "round_code":     game.get("roundCode"),  # kbo_r 정규 / kbo_e 시범 / kbo_ps_* PS
                "game_date":      game.get("gameDate"),
                "game_datetime":  game.get("gameDateTime"),
                "stadium":        game.get("stadium"),
                "status":         game.get("statusCode"),
                "status_info":    game.get("statusInfo"),
                "home_team":      game.get("homeTeamName"),
                "home_team_code": game.get("homeTeamCode"),
                "home_score":     game.get("homeTeamScore"),
                "away_team":      game.get("awayTeamName"),
                "away_team_code": game.get("awayTeamCode"),
                "away_score":     game.get("awayTeamScore"),
                "winner":         game.get("winner"),
                "home_starter":   game.get("homeStarterName"),
                "away_starter":   game.get("awayStarterName"),
                "win_pitcher":    game.get("winPitcherName"),
                "lose_pitcher":   game.get("losePitcherName"),
                "start_time": game.get("gameDateTime", "").split("T")[1][:5] if game.get("gameDateTime") else None,
            })

        return games

    except Exception as e:
        print(f"크롤링 오류: {e}")
        return []


def save_teams(games):
    conn = get_connection()
    if not conn:
        return

    cur = conn.cursor()
    teams = set()

    for g in games:
        if g.get("home_team_code") in KBO_TEAM_CODES:
            teams.add((g["home_team"], g["home_team_code"]))
        if g.get("away_team_code") in KBO_TEAM_CODES:
            teams.add((g["away_team"], g["away_team_code"]))

    for name, code in teams:
        cur.execute("""
            INSERT INTO teams (name, short_name)
            VALUES (%s, %s)
            ON CONFLICT (name) DO NOTHING
        """, (name, code))

    conn.commit()
    cur.close()
    conn.close()
    print(f"팀 {len(teams)}개 저장 완료")


def save_games(games):
    conn = get_connection()
    if not conn:
        return

    cur = conn.cursor()

    for g in games:
        if g.get("home_team_code") not in KBO_TEAM_CODES or \
           g.get("away_team_code") not in KBO_TEAM_CODES:
            continue

        cur.execute("SELECT id FROM teams WHERE name = %s", (g["home_team"],))
        home = cur.fetchone()
        cur.execute("SELECT id FROM teams WHERE name = %s", (g["away_team"],))
        away = cur.fetchone()

        if not home or not away:
            continue

        status = g.get("status", "예정")
        status_info = g.get("status_info", "")

        if status_info == "경기취소":
            status = "취소"
        elif status not in ["예정", "진행", "종료", "취소"]:
            status_map = {
                "BEFORE": "예정", "READY": "예정",
                "LIVE": "진행", "STARTED": "진행",
                "RESULT": "종료", "ENDED": "종료",
            }
            status = status_map.get(status, "예정")

        stadium_id = None
        stadium_name = g.get("stadium", "").strip()
        if stadium_name:
            mapped_name = STADIUM_NAME_MAP.get(stadium_name)
            if mapped_name:
                cur.execute("SELECT id FROM stadiums WHERE name LIKE %s", (f"%{mapped_name}%",))
                stadium_row = cur.fetchone()
                if stadium_row:
                    stadium_id = stadium_row[0]

        cur.execute("""
            INSERT INTO games (
                naver_game_id, home_team_id, away_team_id,
                game_date, start_time, status, home_score, away_score,
                stadium_id
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (naver_game_id) DO UPDATE SET
                status = CASE
                    WHEN games.status = '취소' THEN '취소'
                    WHEN games.status = '종료' THEN '종료'
                    ELSE EXCLUDED.status
                END,
                home_score = EXCLUDED.home_score,
                away_score = EXCLUDED.away_score,
                start_time = EXCLUDED.start_time,
                stadium_id = COALESCE(EXCLUDED.stadium_id, games.stadium_id),
                updated_at = NOW()
        """, (
            g["game_id"], home[0], away[0],
            g["game_date"], g.get("start_time"),
            status, g["home_score"], g["away_score"],
            stadium_id
        ))

    conn.commit()
    cur.close()
    conn.close()
    print(f"경기 {len(games)}개 저장 완료")


def get_team_rankings(season=2026):
    url = f"https://api-gw.sports.naver.com/statistics/categories/kbo/seasons/{season}/teams"
    try:
        res = requests.get(url, headers=HEADERS, timeout=10)
        res.raise_for_status()
        data = res.json()

        if not data.get("success"):
            print("API 응답 실패")
            return []

        teams = []
        for t in data["result"]["seasonTeamStats"]:
            teams.append({
                "team_code":    t.get("teamId"),
                "team_name":    t.get("teamName"),
                "ranking":      t.get("ranking", 0),
                "wins":         t.get("winGameCount", 0),
                "losses":       t.get("loseGameCount", 0),
                "draws":        t.get("drawnGameCount", 0),
                "games_behind": t.get("gameBehind", 0),
                "win_rate":     round(t.get("wra", 0) or 0, 3),
                "logo_url":     t.get("teamImageUrl"),
            })

        return teams

    except Exception as e:
        print(f"팀 순위 크롤링 오류: {e}")
        return []


def save_team_rankings(teams):
    conn = get_connection()
    if not conn:
        return

    cur = conn.cursor()
    updated = 0

    for t in teams:
        cur.execute("""
            UPDATE teams
            SET rank = %s,
                wins = %s,
                losses = %s,
                draws = %s,
                games_behind = %s,
                win_rate = %s,
                logo_url = %s
            WHERE short_name = %s
        """, (
            t["ranking"], t["wins"], t["losses"], t["draws"],
            t["games_behind"], t["win_rate"], t["logo_url"], t["team_code"]
        ))
        if cur.rowcount > 0:
            updated += 1

    conn.commit()
    cur.close()
    conn.close()
    print(f"팀 순위 {updated}개 업데이트 완료")


def get_game_record(game_id):
    url = f"https://api-gw.sports.naver.com/schedule/games/{game_id}/record"
    try:
        res = requests.get(url, headers=HEADERS, timeout=10)
        res.raise_for_status()
        data = res.json()

        if not data.get("success"):
            return None

        return data["result"]["recordData"]

    except Exception as e:
        print(f"경기 상세 크롤링 오류 ({game_id}): {e}")
        return None


def parse_innings(inn_str):
    if not inn_str:
        return 0.0
    inn_str = str(inn_str).strip()

    fraction_map = {'⅓': 0.1, '⅔': 0.2, '¼': 0.1, '½': 0.2, '¾': 0.2}

    try:
        for frac, val in fraction_map.items():
            if frac in inn_str:
                parts = inn_str.replace(frac, '').strip()
                base = float(parts) if parts else 0.0
                return base + val
        return float(inn_str)
    except Exception:
        return 0.0


def save_game_record(game_id, record):
    conn = get_connection()
    if not conn:
        return

    cur = conn.cursor()

    cur.execute("SELECT id FROM games WHERE id = %s", (game_id,))
    game = cur.fetchone()
    if not game:
        conn.close()
        return

    db_game_id = game[0]

    game_info = record.get("gameInfo", {})
    stadium_name = game_info.get("stadium")
    if stadium_name:
        cur.execute("SELECT id FROM stadiums WHERE name LIKE %s", (f"%{stadium_name}%",))
        stadium = cur.fetchone()
        if stadium:
            cur.execute("UPDATE games SET stadium_id = %s WHERE id = %s", (stadium[0], db_game_id))

    score_board = record.get("scoreBoard", {})
    inn_data = score_board.get("inn", {})
    home_innings = inn_data.get("home", [])
    away_innings = inn_data.get("away", [])

    if not home_innings:
        home_innings = score_board.get("homeTeamScoreByInning") or record.get("homeTeamScoreByInning", [])
    if not away_innings:
        away_innings = score_board.get("awayTeamScoreByInning") or record.get("awayTeamScoreByInning", [])

    max_innings = max(len(home_innings), len(away_innings))
    for i in range(max_innings):
        try:
            h = home_innings[i] if i < len(home_innings) else 0
            a = away_innings[i] if i < len(away_innings) else 0
            h_score = int(h) if str(h).isdigit() else 0
            a_score = int(a) if str(a).isdigit() else 0
            cur.execute("""
                INSERT INTO game_innings (game_id, inning, home_runs, away_runs)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (game_id, inning) DO UPDATE SET
                    home_runs = EXCLUDED.home_runs,
                    away_runs = EXCLUDED.away_runs
            """, (db_game_id, i + 1, h_score, a_score))
        except Exception:
            continue

    pitchers_box = record.get("pitchersBoxscore", {})
    pitching_result = record.get("pitchingResult", [])
    wls_map = {p["name"]: p for p in pitching_result}

    for side in ["home", "away"]:
        cur.execute("DELETE FROM game_pitchers WHERE game_id = %s AND team_side = %s", (db_game_id, side))
        team_code = game_info.get("hCode") if side == "home" else game_info.get("aCode")
        cur.execute("SELECT id FROM teams WHERE short_name = %s", (team_code,))
        team = cur.fetchone()
        team_id = team[0] if team else None

        for order, p in enumerate(pitchers_box.get(side, [])):
            player_name = p.get("name")
            if not player_name:
                continue

            player = None
            if team_id:
                cur.execute("""
                    SELECT id FROM players
                    WHERE name = %s AND team_id = %s AND player_type = '투수'
                    LIMIT 1
                """, (player_name, team_id))
                player = cur.fetchone()

                if not player:
                    cur.execute("""
                        SELECT id FROM players
                        WHERE name = %s AND team_id = %s LIMIT 1
                    """, (player_name, team_id))
                    player = cur.fetchone()

            if not player:
                cur.execute("SELECT id FROM players WHERE name = %s LIMIT 1", (player_name,))
                player = cur.fetchone()

            if not player:
                if team_id:
                    cur.execute("""
                        INSERT INTO players (name, team_id, player_type)
                        VALUES (%s, %s, '투수') RETURNING id
                    """, (player_name, team_id))
                    player = cur.fetchone()
                    print(f"신규 투수 추가: {player_name}")
                else:
                    continue

            if not player:
                continue

            wls_info = wls_map.get(player_name, {})
            wls = wls_info.get("wls", "")
            result_map = {"W": "승", "L": "패", "S": "세이브", "H": "홀드"}
            result = result_map.get(wls, "")

            try:
                inn_float = parse_innings(p.get("inn", "0"))
            except Exception:
                inn_float = 0

            cur.execute("""
                INSERT INTO game_pitchers (
                    game_id, player_id, team_side, result,
                    innings_pitched, hits_allowed, earned_runs, runs_allowed,
                    walks, strikeouts, home_runs_allowed, pitch_count,
                    pitching_order
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                    result = EXCLUDED.result,
                    innings_pitched = EXCLUDED.innings_pitched,
                    hits_allowed = EXCLUDED.hits_allowed,
                    earned_runs = EXCLUDED.earned_runs,
                    runs_allowed = EXCLUDED.runs_allowed,
                    walks = EXCLUDED.walks,
                    strikeouts = EXCLUDED.strikeouts,
                    home_runs_allowed = EXCLUDED.home_runs_allowed,
                    pitch_count = EXCLUDED.pitch_count,
                    pitching_order = EXCLUDED.pitching_order
            """, (
                db_game_id, player[0], side, result,
                inn_float, p.get("hit", 0), p.get("er", 0), p.get("r", 0),
                p.get("bb", 0), p.get("kk", 0),
                p.get("hr", 0), p.get("bf", 0),
                order,
            ))

    batters_box = record.get("battersBoxscore", {})

    for side in ["home", "away"]:
        team_code = game_info.get("hCode") if side == "home" else game_info.get("aCode")
        cur.execute("SELECT id FROM teams WHERE short_name = %s", (team_code,))
        team = cur.fetchone()
        team_id = team[0] if team else None

        for b in batters_box.get(side, []):
            player_name = b.get("name")
            if not player_name:
                continue

            pos = b.get("pos", "")
            if pos in ("투", "투수"):
                continue

            player = None
            if team_id:
                cur.execute("""
                    SELECT id FROM players
                    WHERE name = %s AND team_id = %s LIMIT 1
                """, (player_name, team_id))
                player = cur.fetchone()

            if not player:
                cur.execute("SELECT id FROM players WHERE name = %s LIMIT 1", (player_name,))
                player = cur.fetchone()

            if not player:
                if team_id:
                    cur.execute("""
                        INSERT INTO players (name, team_id, player_type)
                        VALUES (%s, %s, '타자') RETURNING id
                    """, (player_name, team_id))
                    player = cur.fetchone()
                    print(f"신규 타자 추가: {player_name}")
                else:
                    continue

            if not player:
                continue

            try:
                avg = float(b.get("hra", 0) or 0)
            except Exception:
                avg = 0

            cur.execute("""
                INSERT INTO game_batters (
                    game_id, player_id, team_side, batting_order,
                    position, at_bats, runs, hits, rbis,
                    home_runs, walks, strikeouts, stolen_bases, avg
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (game_id, player_id, team_side, batting_order) DO UPDATE SET
                    position = EXCLUDED.position,
                    at_bats = EXCLUDED.at_bats,
                    runs = EXCLUDED.runs,
                    hits = EXCLUDED.hits,
                    rbis = EXCLUDED.rbis,
                    home_runs = EXCLUDED.home_runs,
                    walks = EXCLUDED.walks,
                    strikeouts = EXCLUDED.strikeouts,
                    stolen_bases = EXCLUDED.stolen_bases,
                    avg = EXCLUDED.avg
            """, (
                db_game_id, player[0], side,
                b.get("batOrder", 0), convert_position(b.get("pos", "")),
                b.get("ab", 0), b.get("run", 0),
                b.get("hit", 0), b.get("rbi", 0),
                b.get("hr", 0), b.get("bb", 0),
                b.get("kk", 0), b.get("sb", 0), avg
            ))

    etc_records = record.get("etcRecords", [])
    for e in etc_records:
        cur.execute("""
            INSERT INTO game_events (game_id, event_type, description)
            VALUES (%s, %s, %s)
            ON CONFLICT DO NOTHING
        """, (db_game_id, e.get("how"), e.get("result")))

    rheb = score_board.get("rheb", {})
    home_rheb = rheb.get("home", {})
    away_rheb = rheb.get("away", {})

    cur.execute("""
        UPDATE games SET
            home_hits = %s,
            away_hits = %s,
            home_errors = %s,
            away_errors = %s
        WHERE id = %s
    """, (
        home_rheb.get("h", 0), away_rheb.get("h", 0),
        home_rheb.get("e", 0), away_rheb.get("e", 0),
        db_game_id
    ))

    conn.commit()
    cur.close()
    conn.close()
    print(f"경기 {game_id} 상세 기록 저장 완료")


def get_season_schedule(year=2026):
    import calendar
    all_games = []

    for month in range(3, 11):
        last_day = calendar.monthrange(year, month)[1]
        from_date = f"{year}-{month:02d}-01"
        to_date = f"{year}-{month:02d}-{last_day}"

        url = (
            f"https://api-gw.sports.naver.com/schedule/games"
            f"?fields=basic%2Cschedule%2Cbaseball%2CmanualRelayUrl"
            f"&upperCategoryId=kbaseball"
            f"&fromDate={from_date}&toDate={to_date}&size=500"
        )

        try:
            res = requests.get(url, headers=HEADERS, timeout=10)
            res.raise_for_status()
            data = res.json()

            if not data.get("success"):
                continue

            for game in data["result"]["games"]:
                status_map = {
                    "BEFORE": "예정", "READY": "예정",
                    "LIVE": "진행", "STARTED": "진행",
                    "RESULT": "종료", "ENDED": "종료",
                }
                all_games.append({
                    "game_id":        game.get("gameId"),
                    "game_date":      game.get("gameDate"),
                    "stadium":        game.get("stadium"),
                    "status":         status_map.get(game.get("statusCode"), "예정"),
                    "home_team":      game.get("homeTeamName"),
                    "home_team_code": game.get("homeTeamCode"),
                    "home_score":     game.get("homeTeamScore") or 0,
                    "away_team":      game.get("awayTeamName"),
                    "away_team_code": game.get("awayTeamCode"),
                    "away_score":     game.get("awayTeamScore") or 0,
                    "start_time": game.get("gameDateTime", "").split("T")[1][:5] if game.get("gameDateTime") else None,
                })

            print(f"{month}월 경기 {len(data['result']['games'])}개 수집")

        except Exception as e:
            print(f"{month}월 수집 오류: {e}")
            continue

    return all_games


def _parse_naver_lineup(lines):
    """네이버 라인업 페이지 파싱"""
    PITCH_STYLES = {'좌완투수', '우완투수', '우완사이드', '우완언더', '좌완사이드'}
    PITCH_TYPE_MAP = {
        '좌투': '좌완투수', '우투': '우완투수',
        '좌언': '좌완사이드', '우언': '우완언더', '우사': '우완사이드'
    }

    result = {
        'home': {'starter_pitcher': None, 'batters': [], 'backup_batters': [], 'bullpen': []},
        'away': {'starter_pitcher': None, 'batters': [], 'backup_batters': [], 'bullpen': []},
    }

    away_team = None
    start_idx = 0
    for i, line in enumerate(lines):
        if line == '라인업' and i > 0:
            start_idx = i + 1
            break
    lines = lines[start_idx:]

    current_side = None
    current_section = None
    i = 0

    while i < len(lines):
        line = lines[i]

        if line.endswith('선발') and not line.startswith('선발') and len(line) > 2:
            team_name = line[:-2]
            if away_team is None:
                away_team = team_name
                current_side = 'away'
            else:
                current_side = 'home'
            current_section = 'starter'
            i += 1
            if i < len(lines) and lines[i] == '선발':
                i += 1
            continue

        if line == '후보야수':
            i += 1
            continue
        if '후보야수' in line:
            team_name = line.replace(' 후보야수', '').strip()
            current_side = 'away' if team_name == away_team else 'home'
            current_section = 'backup'
            i += 1
            continue

        if line == '불펜투수':
            i += 1
            continue
        if '불펜투수' in line:
            team_name = line.replace(' 불펜투수', '').strip()
            current_side = 'away' if team_name == away_team else 'home'
            current_section = 'bullpen'
            i += 1
            continue

        if '공지' in line or line in ('홈', '야구', '해외야구'):
            break

        if current_side is None or current_section is None:
            i += 1
            continue

        if current_section == 'starter':
            if i + 1 < len(lines) and lines[i + 1] in PITCH_TYPE_MAP:
                result[current_side]['starter_pitcher'] = {
                    'name': line,
                    'pitching_style': PITCH_TYPE_MAP[lines[i + 1]],
                }
                i += 2
                continue
            if line.isdigit() and i + 2 < len(lines):
                pos = lines[i + 2].split(',')[0].strip().split(' ,')[0].strip()
                result[current_side]['batters'].append({
                    'batting_order': int(line),
                    'name': lines[i + 1],
                    'position': pos,
                })
                i += 3
                continue

        elif current_section == 'backup':
            if ',' in line and any(p in line for p in ['우타', '좌타', '양타']):
                i += 1
                continue
            if i + 1 < len(lines):
                next_line = lines[i + 1]
                if ',' in next_line and any(p in next_line for p in ['우타', '좌타', '양타']):
                    pos = next_line.split(',')[0].strip()
                    result[current_side]['backup_batters'].append({
                        'name': line,
                        'position': pos,
                    })
                    i += 2
                    continue

        elif current_section == 'bullpen':
            if line in PITCH_STYLES:
                i += 1
                continue
            if i + 1 < len(lines) and lines[i + 1] in PITCH_STYLES:
                result[current_side]['bullpen'].append({
                    'name': line,
                    'pitching_style': lines[i + 1],
                })
                i += 2
                continue

        i += 1

    return result


def crawl_naver_lineup(naver_game_id):
    """네이버 모바일 라인업 페이지 크롤링"""
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options
    from selenium.webdriver.chrome.service import Service
    from selenium.webdriver.common.by import By
    from webdriver_manager.chrome import ChromeDriverManager
    import time

    options = Options()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_experimental_option('prefs', {
        'profile.managed_default_content_settings.images': 2,
    })
    from crawler.driver_util import arm_or_wdm_chrome
    driver = arm_or_wdm_chrome(options)

    try:
        driver.get(f'https://m.sports.naver.com/game/{naver_game_id}/lineup')
        time.sleep(3)
        text = driver.find_element(By.TAG_NAME, 'body').text
        lines = [l.strip() for l in text.split('\n') if l.strip()]
    finally:
        driver.quit()

    return _parse_naver_lineup(lines)


def reconcile_starter_positions(cur, db_game_id):
    """대타/대주자가 starter로 잘못 표기되고 실제 포지션 선수가 backup으로 빠진 경우 교정.
    같은 batting_order의 backup 중 실제 포지션 가진 첫 row를 starter로 promote + 대타/대주자 starter 강등.
    여러 크롤(라인업/preview/entry)이 순서 무관하게 backup을 추가해도, 최종 호출 시점 기준으로 일관 보정.
    → save_game_roster뿐 아니라 backup을 나중에 추가하는 preview/entry 크롤 끝에서도 호출 필요
      (안 하면 fixup이 stale → 선발에 1루수 등 누락, 필드뷰 포지션 빔)."""
    cur.execute("""
        WITH targets AS (
          SELECT DISTINCT ON (gr.game_id, gr.team_side, gr.batting_order) gr.id
          FROM game_rosters gr
          JOIN game_rosters s ON s.game_id=gr.game_id
            AND s.team_side=gr.team_side
            AND s.batting_order=gr.batting_order
            AND s.is_starter=TRUE
            AND s.position IN ('대타', '대주자')
          WHERE gr.game_id = %s
            AND gr.is_starter = FALSE
            AND gr.roster_type = 'batter'
            AND gr.position IS NOT NULL
            AND gr.position NOT IN ('대타', '대주자', '')
          ORDER BY gr.game_id, gr.team_side, gr.batting_order, gr.id
        )
        UPDATE game_rosters SET is_starter = TRUE WHERE id IN (SELECT id FROM targets)
    """, (db_game_id,))
    cur.execute("""
        UPDATE game_rosters SET is_starter = FALSE
        WHERE game_id = %s
          AND roster_type = 'batter'
          AND is_starter = TRUE
          AND position IN ('대타', '대주자')
          AND EXISTS (
            SELECT 1 FROM game_rosters g2
            WHERE g2.game_id = game_rosters.game_id
              AND g2.team_side = game_rosters.team_side
              AND g2.batting_order = game_rosters.batting_order
              AND g2.is_starter = TRUE
              AND g2.position NOT IN ('대타', '대주자', '')
              AND g2.id != game_rosters.id
          )
    """, (db_game_id,))
    # 타자 선발은 항상 타순 1-9 보유 → batting_order=0 인 batter starter는 벤치 오플래그 → 강등
    # (선발 투수는 roster_type='pitcher' batting_order NULL 이므로 영향 없음. 라인업 탭 선발 목록 오염 방지)
    cur.execute("""
        UPDATE game_rosters SET is_starter = FALSE
        WHERE game_id = %s
          AND roster_type = 'batter'
          AND is_starter = TRUE
          AND batting_order = 0
    """, (db_game_id,))


def save_preview_roster(db_game_id, naver_game_id):
    """preview API 기반 경기 전 풀 로스터 (2026-06-07)
    — homeTeamLineUp/awayTeamLineUp: fullLineUp(선발투수 포함) + pitcherBullpen + batterCandidate.
    경기 ~2시간 전 preview 생성 시점부터 사용 가능 (relay entry는 경기 시작 후에만)."""
    import requests as _rq
    try:
        url = f"{BASE_API}/{naver_game_id}/preview"
        res = _rq.get(url, headers=HEADERS, timeout=5)
        if res.status_code != 200:
            return
        pd = ((res.json().get('result') or {}).get('previewData') or {})
        conn = get_connection()
        if not conn:
            return
        cur = conn.cursor()

        # 경기 양팀 team_id (신규 선수 자동생성 시 소속 배정용)
        cur.execute("SELECT home_team_id, away_team_id FROM games WHERE id = %s", (db_game_id,))
        _tr = cur.fetchone()
        _team_of = {'home': _tr[0] if _tr else None, 'away': _tr[1] if _tr else None}

        def _pid(pcode, name, side=None, ptype='선수'):
            if pcode:
                cur.execute("SELECT id FROM players WHERE naver_player_id = %s LIMIT 1", (str(pcode),))
                r = cur.fetchone()
                if r:
                    return r[0]
            if name:
                cur.execute("SELECT id FROM players WHERE name = %s LIMIT 1", (name,))
                r = cur.fetchone()
                if r:
                    # naver_player_id 보강 (다음부터 코드 매칭)
                    if pcode:
                        cur.execute("UPDATE players SET naver_player_id = %s WHERE id = %s AND (naver_player_id IS NULL OR naver_player_id = '')", (str(pcode), r[0]))
                    return r[0]
            # 미등록 — 자동 생성 (신규 외국인 선발 등 누락 방지, 2026-06-11)
            if name and side and _team_of.get(side):
                cur.execute("""
                    INSERT INTO players (name, team_id, player_type, naver_player_id)
                    VALUES (%s, %s, %s, %s) RETURNING id
                """, (name, _team_of[side], ptype, str(pcode) if pcode else None))
                r = cur.fetchone()
                if r:
                    print(f"신규 선수 자동 추가(preview): {name} (팀={_team_of[side]}, code={pcode})")
                    return r[0]
            return None

        n = 0
        for side in ('home', 'away'):
            lu = pd.get(f'{side}TeamLineUp') or {}
            # 선발투수 (fullLineUp 내 positionName '선발투수')
            for e in (lu.get('fullLineUp') or []):
                if (e.get('positionName') or '') != '선발투수':
                    continue
                pid = _pid(e.get('playerCode'), e.get('playerName'), side, '투수')
                if pid is None:
                    continue
                cur.execute("""
                    INSERT INTO game_rosters (
                        game_id, player_id, team_side, roster_type,
                        batting_order, position, pitching_style, is_starter
                    ) VALUES (%s, %s, %s, 'pitcher', NULL, '투수', %s, TRUE)
                    ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                        is_starter = TRUE, roster_type = 'pitcher',
                        pitching_style = COALESCE(EXCLUDED.pitching_style, game_rosters.pitching_style)
                """, (db_game_id, pid, side, e.get('hitType')))
                n += 1
            # 불펜
            for e in (lu.get('pitcherBullpen') or []):
                pid = _pid(e.get('playerCode'), e.get('playerName'), side, '투수')
                if pid is None:
                    continue
                cur.execute("""
                    INSERT INTO game_rosters (
                        game_id, player_id, team_side, roster_type,
                        batting_order, position, pitching_style, is_starter
                    ) VALUES (%s, %s, %s, 'pitcher', NULL, '투수', %s, FALSE)
                    ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                        pitching_style = COALESCE(game_rosters.pitching_style, EXCLUDED.pitching_style)
                """, (db_game_id, pid, side, e.get('hitType')))
                n += 1
            # 후보 야수
            for e in (lu.get('batterCandidate') or []):
                pid = _pid(e.get('playerCode'), e.get('playerName'), side, '타자')
                if pid is None:
                    continue
                cur.execute("""
                    INSERT INTO game_rosters (
                        game_id, player_id, team_side, roster_type,
                        batting_order, position, pitching_style, is_starter
                    ) VALUES (%s, %s, %s, 'batter', NULL, %s, NULL, FALSE)
                    ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                        position = COALESCE(game_rosters.position, EXCLUDED.position)
                """, (db_game_id, pid, side, e.get('position')))
                n += 1
        # backup 추가 후 선발 포지션 재보정 (대주자/대타 starter → 실포지션 backup promote)
        reconcile_starter_positions(cur, db_game_id)
        conn.commit()
        cur.close()
        conn.close()
        if n:
            print(f"경기 {db_game_id} preview 로스터 저장 ({n}명)")
    except Exception as e:
        print(f"preview 로스터 오류 game={db_game_id}: {e}")


def save_entry_roster(db_game_id, naver_game_id):
    """relay entry(homeEntry/awayEntry) 기반 후보 야수/불펜 로스터 보강 (2026-06-07)
    — 라인업 페이지 크롤(save_game_roster)은 선발만 파싱하던 한계 보완.
    기존 선발 행은 보존(is_starter 유지), pitching_style만 보충."""
    import requests as _rq
    try:
        url = f"{BASE_API}/{naver_game_id}/relay?inning=1"
        res = _rq.get(url, headers=HEADERS, timeout=5)
        if res.status_code != 200:
            return
        relay = (res.json().get('result') or {}).get('textRelayData') or {}
        conn = get_connection()
        if not conn:
            return
        cur = conn.cursor()
        n = 0
        for side in ('home', 'away'):
            entry = relay.get(f'{side}Entry') or {}
            for kind, rtype in (('batter', 'batter'), ('pitcher', 'pitcher')):
                for e in (entry.get(kind) or []):
                    name = e.get('name')
                    if not name:
                        continue
                    pcode = str(e.get('pcode') or '')
                    pos = e.get('pos') or ('투수' if rtype == 'pitcher' else None)
                    style = e.get('pitchingStyle')
                    pid = None
                    if pcode:
                        cur.execute("SELECT id FROM players WHERE naver_player_id = %s LIMIT 1", (pcode,))
                        r = cur.fetchone()
                        pid = r[0] if r else None
                    if pid is None:
                        cur.execute("SELECT id FROM players WHERE name = %s LIMIT 1", (name,))
                        r = cur.fetchone()
                        pid = r[0] if r else None
                    if pid is None:
                        continue
                    cur.execute("""
                        INSERT INTO game_rosters (
                            game_id, player_id, team_side, roster_type,
                            batting_order, position, pitching_style, is_starter
                        ) VALUES (%s, %s, %s, %s, NULL, %s, %s, FALSE)
                        ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                            pitching_style = COALESCE(game_rosters.pitching_style, EXCLUDED.pitching_style)
                    """, (db_game_id, pid, side, rtype, pos, style))
                    n += 1
        # backup 추가 후 선발 포지션 재보정
        reconcile_starter_positions(cur, db_game_id)
        conn.commit()
        cur.close()
        conn.close()
        print(f"경기 {db_game_id} entry 로스터 보강 ({n}명)")
    except Exception as e:
        print(f"entry 로스터 오류 game={db_game_id}: {e}")


def save_game_roster(db_game_id, naver_game_id):
    """네이버 라인업 페이지 기반 로스터 저장"""
    try:
        lineup = crawl_naver_lineup(naver_game_id)
        if not lineup:
            return

        conn = get_connection()
        if not conn:
            return
        cur = conn.cursor()

        cur.execute("""
            SELECT g.home_team_id, g.away_team_id
            FROM games g WHERE g.id = %s
        """, (db_game_id,))
        game = cur.fetchone()
        if not game:
            cur.close()
            conn.close()
            return
        home_team_id, away_team_id = game

        def find_player(name, team_id, player_type=None):
            cur.execute("""
                SELECT id FROM players
                WHERE name = %s AND team_id = %s LIMIT 1
            """, (name, team_id))
            row = cur.fetchone()
            if row:
                return row[0]

            cur.execute("SELECT id FROM players WHERE name = %s LIMIT 1", (name,))
            row = cur.fetchone()
            if row:
                return row[0]

            ptype = player_type or '선수'
            cur.execute("""
                INSERT INTO players (name, team_id, player_type)
                VALUES (%s, %s, %s) RETURNING id
            """, (name, team_id, ptype))
            row = cur.fetchone()
            print(f"신규 선수 자동 추가: {name} (팀={team_id}, 타입={ptype})")
            return row[0] if row else None

        for side, team_id in [('home', home_team_id), ('away', away_team_id)]:
            data = lineup[side]

            sp = data.get('starter_pitcher')
            if sp:
                player_id = find_player(sp['name'], team_id, '투수')
                if player_id:
                    cur.execute("""
                        INSERT INTO game_rosters (
                            game_id, player_id, team_side, roster_type,
                            batting_order, position, pitching_style, is_starter
                        ) VALUES (%s, %s, %s, 'pitcher', NULL, '투수', %s, TRUE)
                        ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                            pitching_style = EXCLUDED.pitching_style,
                            is_starter = TRUE,
                            roster_type = 'pitcher'
                    """, (db_game_id, player_id, side, sp['pitching_style']))

            batters = data.get('batters', [])
            if not batters:
                cur.execute("""
                    SELECT DISTINCT ON (gb.batting_order)
                        gb.batting_order, gb.position, p.name, p.id
                    FROM game_batters gb
                    JOIN players p ON gb.player_id = p.id
                    WHERE gb.game_id = %s
                    AND gb.team_side = %s
                    AND gb.batting_order IS NOT NULL
                    AND gb.batting_order BETWEEN 1 AND 9
                    ORDER BY gb.batting_order, gb.at_bats DESC
                """, (db_game_id, side))
                batter_rows = cur.fetchall()
                for (batting_order, position, name, player_id) in batter_rows:
                    pos = convert_position(position) if position else ''
                    cur.execute("""
                        INSERT INTO game_rosters (
                            game_id, player_id, team_side, roster_type,
                            batting_order, position, pitching_style, is_starter
                        ) VALUES (%s, %s, %s, 'batter', %s, %s, NULL, TRUE)
                        ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                            batting_order = EXCLUDED.batting_order,
                            position = EXCLUDED.position,
                            is_starter = TRUE,
                            roster_type = 'batter'
                    """, (db_game_id, player_id, side, batting_order, pos))
            else:
                for b in batters:
                    player_id = find_player(b['name'], team_id, '타자')
                    if player_id:
                        cur.execute("""
                            INSERT INTO game_rosters (
                                game_id, player_id, team_side, roster_type,
                                batting_order, position, pitching_style, is_starter
                            ) VALUES (%s, %s, %s, 'batter', %s, %s, NULL, TRUE)
                            ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                                batting_order = EXCLUDED.batting_order,
                                position = EXCLUDED.position,
                                is_starter = TRUE,
                                roster_type = 'batter'
                        """, (db_game_id, player_id, side, b['batting_order'], b['position']))

            for b in data.get('backup_batters', []):
                player_id = find_player(b['name'], team_id, '타자')
                if player_id:
                    cur.execute("""
                        INSERT INTO game_rosters (
                            game_id, player_id, team_side, roster_type,
                            batting_order, position, pitching_style, is_starter
                        ) VALUES (%s, %s, %s, 'batter', NULL, %s, NULL, FALSE)
                        ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                            position = EXCLUDED.position,
                            batting_order = NULL,
                            is_starter = FALSE,
                            roster_type = 'batter'
                    """, (db_game_id, player_id, side, b['position']))

            for p in data.get('bullpen', []):
                player_id = find_player(p['name'], team_id, '투수')
                if player_id:
                    cur.execute("""
                        INSERT INTO game_rosters (
                            game_id, player_id, team_side, roster_type,
                            batting_order, position, pitching_style, is_starter
                        ) VALUES (%s, %s, %s, 'pitcher', NULL, '투수', %s, FALSE)
                        ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                            pitching_style = EXCLUDED.pitching_style,
                            is_starter = FALSE,
                            roster_type = 'pitcher'
                    """, (db_game_id, player_id, side, p['pitching_style']))

        # ── starter position fixup (공용 함수) ──
        reconcile_starter_positions(cur, db_game_id)

        conn.commit()
        cur.close()
        conn.close()
        print(f"경기 {db_game_id} 로스터 저장 완료")

    except Exception as e:
        print(f"로스터 저장 오류 ({naver_game_id}): {e}")
        import traceback
        traceback.print_exc()


def _upsert_player(cur, name, team_id, player_type):
    """선수 조회 또는 신규 추가"""
    if team_id:
        cur.execute("SELECT id FROM players WHERE name = %s AND team_id = %s LIMIT 1", (name, team_id))
        row = cur.fetchone()
        if row:
            return row[0]
    cur.execute("SELECT id FROM players WHERE name = %s LIMIT 1", (name,))
    row = cur.fetchone()
    if row:
        return row[0]
    cur.execute("""
        INSERT INTO players (name, team_id, player_type)
        VALUES (%s, %s, %s) RETURNING id
    """, (name, team_id, player_type))
    row = cur.fetchone()
    print(f"신규 {player_type} 자동 추가: {name}")
    return row[0] if row else None


def update_live_game_players(db_game_id, naver_game_id):
    """진행 중인 경기 타자/투수 실시간 업데이트"""
    try:
        url = f"https://api-gw.sports.naver.com/schedule/games/{naver_game_id}/relay?inning=1"
        res = requests.get(url, headers=HEADERS, timeout=10)
        res.raise_for_status()
        data = res.json()
        relay = data.get('result', {}).get('textRelayData', {})

        conn = get_connection()
        if not conn:
            return
        cur = conn.cursor()

        cur.execute("SELECT home_team_id, away_team_id FROM games WHERE id = %s", (db_game_id,))
        game_row = cur.fetchone()
        home_team_id = game_row[0] if game_row else None
        away_team_id = game_row[1] if game_row else None

        for side, lineup_key, entry_key in [
            ('home', 'homeLineup', 'homeEntry'),
            ('away', 'awayLineup', 'awayEntry')
        ]:
            team_id = home_team_id if side == 'home' else away_team_id
            lineup = relay.get(lineup_key, {})
            entry = relay.get(entry_key, {})

            # lineup에서 선발(cout 없음)과 교체(cout=true) 구분
            lineup_batters = lineup.get('batter', [])
            # 선발 타자: cout이 없는 선수 (원래 선발)
            starter_names = {b.get('name') for b in lineup_batters if not b.get('cout')}
            # entry에만 있는 선수 추가
            lineup_names = {b.get('name') for b in lineup_batters}
            entry_only = [b for b in entry.get('batter', []) if b.get('name') not in lineup_names]
            all_batters = lineup_batters + entry_only
            seen_batters = set()
            for b in all_batters:
                name = b.get('name', '')
                if not name or name in seen_batters:
                    continue
                seen_batters.add(name)

                player_id = _upsert_player(cur, name, team_id, '타자')
                if not player_id:
                    continue

                # homeLineup batter → posName / homeEntry batter → pos (다른 키)
                pos_raw = b.get('posName') or b.get('pos') or ''
                pos_converted = convert_position(pos_raw)
                cur.execute("""
                    INSERT INTO game_batters (
                        game_id, player_id, team_side, batting_order,
                        position, at_bats, hits, rbis, home_runs, avg, walks
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (game_id, player_id, team_side, batting_order) DO UPDATE SET
                        position = EXCLUDED.position,
                        at_bats = EXCLUDED.at_bats,
                        hits = EXCLUDED.hits,
                        rbis = EXCLUDED.rbis,
                        home_runs = EXCLUDED.home_runs,
                        avg = EXCLUDED.avg,
                        walks = EXCLUDED.walks
                """, (
                    db_game_id, player_id, side,
                    b.get('batOrder', 0), pos_converted,
                    b.get('ab', 0), b.get('hit', 0),
                    b.get('rbi', 0) if 'rbi' in b else 0,
                    b.get('hr', 0), float(b.get('seasonHra', 0) or 0),
                    b.get('bb', 0) or 0
                ))

                # game_rosters 반영 (선발: cout 없는 선수, 교체: cout=true 또는 entry only)
                is_starter = b.get('name') in starter_names
                cur.execute("""
                    INSERT INTO game_rosters (
                        game_id, player_id, team_side, roster_type,
                        batting_order, position, is_starter
                    ) VALUES (%s, %s, %s, 'batter', %s, %s, %s)
                    ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                        batting_order = EXCLUDED.batting_order,
                        position = EXCLUDED.position,
                        is_starter = EXCLUDED.is_starter,
                        roster_type = 'batter'
                """, (
                    db_game_id, player_id, side,
                    b.get('batOrder', 0),
                    pos_converted,
                    is_starter
                ))

            seen_pitchers = set()
            all_pitchers = list(lineup.get('pitcher', [])) + list(entry.get('pitcher', []))
            for pitch_order, p in enumerate(all_pitchers, start=1):
                name = p.get('name', '')
                if not name or name in seen_pitchers:
                    continue
                seen_pitchers.add(name)

                player_id = _upsert_player(cur, name, team_id, '투수')
                if not player_id:
                    continue

                # game_rosters 반영
                cur.execute("""
                    INSERT INTO game_rosters (
                        game_id, player_id, team_side, roster_type,
                        batting_order, position, is_starter
                    ) VALUES (%s, %s, %s, 'pitcher', NULL, '투수', FALSE)
                    ON CONFLICT (game_id, player_id, team_side) DO NOTHING
                """, (db_game_id, player_id, side))

                # game_pitchers에도 실시간 스탯 저장
                inn_pitched = float(p.get('inn', 0) or 0)
                cur.execute("""
                    INSERT INTO game_pitchers (
                        game_id, player_id, team_side,
                        innings_pitched, hits_allowed, earned_runs, runs_allowed,
                        walks, strikeouts, home_runs_allowed, pitch_count,
                        pitching_order, result
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                        innings_pitched = EXCLUDED.innings_pitched,
                        hits_allowed = EXCLUDED.hits_allowed,
                        earned_runs = EXCLUDED.earned_runs,
                        runs_allowed = EXCLUDED.runs_allowed,
                        walks = EXCLUDED.walks,
                        strikeouts = EXCLUDED.strikeouts,
                        home_runs_allowed = EXCLUDED.home_runs_allowed,
                        pitch_count = EXCLUDED.pitch_count,
                        pitching_order = EXCLUDED.pitching_order
                """, (
                    db_game_id, player_id, side,
                    inn_pitched,
                    p.get('hit', 0) or 0,
                    p.get('er', 0) or 0,
                    p.get('r', 0) or 0,
                    p.get('bb', 0) or 0,
                    p.get('kk', 0) or 0,
                    p.get('hr', 0) or 0,
                    p.get('bf', 0) or 0,
                    pitch_order,
                    ''
                ))

        conn.commit()
        cur.close()
        conn.close()
        print(f"경기 {db_game_id} 실시간 선수 기록 업데이트")

        # record API에서 투수 실시간 스탯 업데이트
        _update_live_pitcher_stats(db_game_id, naver_game_id)

    except Exception as e:
        print(f"실시간 선수 업데이트 오류 ({naver_game_id}): {e}")


def _update_live_pitcher_stats(db_game_id, naver_game_id):
    """진행 중 경기 투수 실시간 스탯 업데이트 (record API 사용)"""
    try:
        url = f"https://api-gw.sports.naver.com/schedule/games/{naver_game_id}/record"
        res = requests.get(url, headers=HEADERS, timeout=10)
        res.raise_for_status()
        data = res.json()
        if not data.get('success'):
            return
        record = data['result']['recordData']
        pitchers_box = record.get('pitchersBoxscore', {})
        game_info = record.get('gameInfo', {})

        conn = get_connection()
        if not conn:
            return
        cur = conn.cursor()

        # 실제 등판한 투수 목록 (game_pitches type=1 기준)
        cur.execute("""
            SELECT DISTINCT pitcher_name FROM game_pitches
            WHERE game_id = %s AND type = 1 AND pitcher_name IS NOT NULL
        """, (db_game_id,))
        appeared_pitchers = {r[0] for r in cur.fetchall()}

        for side in ['home', 'away']:
            team_code = game_info.get('hCode') if side == 'home' else game_info.get('aCode')
            cur.execute("SELECT id FROM teams WHERE short_name = %s", (team_code,))
            team = cur.fetchone()
            team_id = team[0] if team else None

            for order, p in enumerate(pitchers_box.get(side, []), start=1):
                name = p.get('name')
                if not name:
                    continue

                # 실제 등판한 투수만 저장
                if name not in appeared_pitchers:
                    continue

                player = None
                if team_id:
                    cur.execute("""
                        SELECT id FROM players WHERE name = %s AND team_id = %s LIMIT 1
                    """, (name, team_id))
                    player = cur.fetchone()
                if not player:
                    cur.execute("SELECT id FROM players WHERE name = %s LIMIT 1", (name,))
                    player = cur.fetchone()
                if not player:
                    continue

                inn_float = parse_innings(p.get('inn', '0'))
                cur.execute("""
                    INSERT INTO game_pitchers (
                        game_id, player_id, team_side,
                        innings_pitched, hits_allowed, earned_runs, runs_allowed,
                        walks, strikeouts, home_runs_allowed, pitch_count,
                        pitching_order, result
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                        innings_pitched = EXCLUDED.innings_pitched,
                        hits_allowed = EXCLUDED.hits_allowed,
                        earned_runs = EXCLUDED.earned_runs,
                        runs_allowed = EXCLUDED.runs_allowed,
                        walks = EXCLUDED.walks,
                        strikeouts = EXCLUDED.strikeouts,
                        home_runs_allowed = EXCLUDED.home_runs_allowed,
                        pitch_count = EXCLUDED.pitch_count,
                        pitching_order = EXCLUDED.pitching_order
                """, (
                    db_game_id, player[0], side,
                    inn_float,
                    p.get('hit', 0) or 0,
                    p.get('er', 0) or 0,
                    p.get('r', 0) or 0,
                    p.get('bb', 0) or 0,
                    p.get('kk', 0) or 0,
                    p.get('hr', 0) or 0,
                    p.get('bf', 0) or 0,
                    order,
                    ''
                ))

        conn.commit()
        cur.close()
        conn.close()
        print(f"경기 {db_game_id} 투수 실시간 스탯 업데이트")

    except Exception as e:
        print(f"투수 실시간 스탯 업데이트 오류: {e}")


def update_live_game_innings(db_game_id, naver_game_id):
    """진행 중인 경기 이닝 실시간 업데이트"""
    try:
        url = f"https://api-gw.sports.naver.com/schedule/games/{naver_game_id}/relay?inning=1"
        res = requests.get(url, headers=HEADERS, timeout=10)
        res.raise_for_status()
        data = res.json()

        relay = data.get('result', {}).get('textRelayData', {})
        inning_score = relay.get('inningScore', {})
        current_inning = relay.get('inn', 0)
        home_or_away = relay.get('homeOrAway', '0')

        home_innings = inning_score.get('home', {})
        away_innings = inning_score.get('away', {})

        conn = get_connection()
        if not conn:
            return
        cur = conn.cursor()

        max_inning = max(
            max([int(k) for k in home_innings.keys()], default=0),
            max([int(k) for k in away_innings.keys()], default=0)
        )

        for i in range(1, max_inning + 1):
            h = home_innings.get(str(i), '-')
            a = away_innings.get(str(i), '-')
            h_score = int(h) if str(h).isdigit() else 0
            a_score = int(a) if str(a).isdigit() else 0

            cur.execute("""
                INSERT INTO game_innings (game_id, inning, home_runs, away_runs)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (game_id, inning) DO UPDATE SET
                    home_runs = EXCLUDED.home_runs,
                    away_runs = EXCLUDED.away_runs
            """, (db_game_id, i, h_score, a_score))

        inning_half = '초' if home_or_away == '0' else '말'
        cur.execute("""
            UPDATE games SET
                current_inning = %s,
                inning_half = %s
            WHERE id = %s
        """, (current_inning, inning_half, db_game_id))

        conn.commit()
        cur.close()
        conn.close()
        print(f"경기 {db_game_id}: {current_inning}회 {inning_half} 이닝 업데이트")

    except Exception as e:
        print(f"이닝 업데이트 오류 ({naver_game_id}): {e}")


if __name__ == "__main__":
    print("=== 2026 시즌 전체 일정 수집 ===")
    all_games = get_season_schedule(2026)
    print(f"총 {len(all_games)}경기 수집")
    save_games(all_games)

    print("\n=== 팀 순위 업데이트 ===")
    teams = get_team_rankings(2026)
    print(f"팀 {len(teams)}개 수집")
    save_team_rankings(teams)

    print("\n=== 종료된 경기 상세 기록 수집 ===")
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT id, naver_game_id FROM games
        WHERE status = '종료' AND naver_game_id IS NOT NULL
    """)
    finished_games = cur.fetchall()
    cur.close()
    conn.close()

    for (db_game_id, naver_game_id) in finished_games:
        record = get_game_record(naver_game_id)
        if record:
            save_game_record(db_game_id, record)