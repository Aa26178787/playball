import requests
import sys
import os
import time
import re

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from database.connection import get_connection

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    "Referer": "https://sports.naver.com/",
}

BASE_API = "https://api-gw.sports.naver.com/statistics/categories/kbo/seasons"


def crawl_kbo_register():
    """KBO 전체 등록현황에서 팀별 선수 크롤링"""
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options
    from selenium.webdriver.chrome.service import Service
    from selenium.webdriver.common.by import By
    from webdriver_manager.chrome import ChromeDriverManager
    import re

    TEAM_SHORT_MAP = {
        'KT': 1, 'KIA': 2, '롯데': 4, '한화': 5,
        'NC': 6, '두산': 7, '키움': 8, 'LG': 9,
        'SSG': 10, '삼성': 11,
    }

    options = Options()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_experimental_option('prefs', {
        'profile.managed_default_content_settings.images': 2,
    })

    driver = webdriver.Chrome(
        service=Service(ChromeDriverManager().install()), options=options
    )

    conn = get_connection()
    if not conn:
        driver.quit()
        return

    cur = conn.cursor()

    # 전체 선수 is_registered 초기화
    cur.execute("UPDATE players SET is_registered = FALSE")
    conn.commit()

    driver.get('https://www.koreabaseball.com/Player/RegisterAll.aspx')
    time.sleep(2)
    text = driver.find_element(By.TAG_NAME, 'body').text
    lines = [l.strip() for l in text.split('\n') if l.strip()]
    driver.quit()

    total_updated = 0
    i = 0

    while i < len(lines):
        line = lines[i]

        if line.startswith('구단 감독('):
            counts = {}
            for pos in ['감독', '코치', '투수', '포수', '내야수', '외야수']:
                m = re.search(rf'{pos}\((\d+)\)', line)
                counts[pos] = int(m.group(1)) if m else 0

            i += 1
            if i >= len(lines):
                break

            team_name = lines[i].strip()
            team_id = TEAM_SHORT_MAP.get(team_name)
            i += 1

            if i < len(lines) and lines[i].endswith('명'):
                i += 1

            if not team_id:
                continue

            team_updated = 0

            skip_count = counts.get('감독', 0) + counts.get('코치', 0)
            i += skip_count

            for _ in range(counts.get('투수', 0)):
                if i >= len(lines):
                    break
                player_line = lines[i]
                i += 1
                m = re.match(r'^(.+)\((\d+)\)$', player_line)
                if m:
                    name = m.group(1).strip()
                    number = int(m.group(2))
                    _upsert_player(cur, name, number, team_id, '투수')
                    team_updated += 1

            for _ in range(counts.get('포수', 0)):
                if i >= len(lines):
                    break
                player_line = lines[i]
                i += 1
                m = re.match(r'^(.+)\((\d+)\)$', player_line)
                if m:
                    name = m.group(1).strip()
                    number = int(m.group(2))
                    _upsert_player(cur, name, number, team_id, '타자')
                    team_updated += 1

            for _ in range(counts.get('내야수', 0)):
                if i >= len(lines):
                    break
                player_line = lines[i]
                i += 1
                m = re.match(r'^(.+)\((\d+)\)$', player_line)
                if m:
                    name = m.group(1).strip()
                    number = int(m.group(2))
                    _upsert_player(cur, name, number, team_id, '타자')
                    team_updated += 1

            for _ in range(counts.get('외야수', 0)):
                if i >= len(lines):
                    break
                player_line = lines[i]
                i += 1
                m = re.match(r'^(.+)\((\d+)\)$', player_line)
                if m:
                    name = m.group(1).strip()
                    number = int(m.group(2))
                    _upsert_player(cur, name, number, team_id, '타자')
                    team_updated += 1

            conn.commit()
            total_updated += team_updated
            print(f'{team_name}: {team_updated}명 업데이트')

        else:
            i += 1

    cur.close()
    conn.close()
    print(f'KBO 등록현황 총 {total_updated}명 업데이트 완료')


def _upsert_player(cur, name, number, team_id, player_type):
    """선수 정보 upsert"""
    cur.execute("""
        SELECT id FROM players
        WHERE name = %s AND team_id = %s
        LIMIT 1
    """, (name, team_id))
    existing = cur.fetchone()

    if existing:
        cur.execute("""
            UPDATE players SET
                number = %s,
                player_type = %s,
                is_registered = TRUE
            WHERE id = %s
        """, (number, player_type, existing[0]))
    else:
        cur.execute("""
            INSERT INTO players (name, team_id, player_type, number, is_registered)
            VALUES (%s, %s, %s, %s, TRUE)
            ON CONFLICT DO NOTHING
        """, (name, team_id, player_type, number))


def get_hitter_stats(season=2026):
    """타자 시즌 기록 가져오기"""
    url = f"{BASE_API}/{season}/players?sortField=hitterHra&sortDirection=desc&playerType=HITTER&pageSize=500"
    try:
        res = requests.get(url, headers=HEADERS, timeout=10)
        res.raise_for_status()
        data = res.json()

        if not data.get("success"):
            print("API 응답 실패")
            return []

        players = []
        for p in data["result"]["seasonPlayerStats"]:
            import json as json_lib

            profile_str = p.get("profile", "{}")
            try:
                profile_data = json_lib.loads(profile_str)
                position = profile_data.get("position", "")
            except Exception:
                position = ""
            players.append({
                "player_id":       p.get("playerId"),
                "name":            p.get("playerName"),
                "team_code":       p.get("teamId"),
                "team_name":       p.get("teamName"),
                "player_type":     "타자",
                "position":        position,
                "number":          p.get("backNumber"),
                "season":          season,
                "games":           p.get("hitterGameCount", 0),
                "at_bats":         p.get("hitterAb", 0),
                "runs":            p.get("hitterRun", 0),
                "hits":            p.get("hitterHit", 0),
                "doubles":         p.get("hitterH2", 0),
                "triples":         p.get("hitterH3", 0),
                "home_runs":       p.get("hitterHr", 0),
                "rbis":            p.get("hitterRbi", 0),
                "walks":           p.get("hitterBb", 0),
                "strikeouts":      p.get("hitterKk", 0),
                "stolen_bases":    p.get("hitterSb", 0),
                "avg":             round(p.get("hitterHra", 0) or 0, 3),
                "obp":             round(p.get("hitterObp", 0) or 0, 3),
                "slg":             round(p.get("hitterSlg", 0) or 0, 3),
                "ops":             round(p.get("hitterOps", 0) or 0, 3),
                "woba":            round(p.get("hitterWoba", 0) or 0, 3),
                "wrc_plus":        int(p.get("hitterWrcPlus", 0) or 0),
                "babip":           round(p.get("hitterBabip", 0) or 0, 3),
                "iso":             round(p.get("hitterIsop", 0) or 0, 3),
                "war":             round(p.get("hitterWar", 0) or 0, 2),
                "profile_image":   p.get("playerImageUrl"),
                "height":          p.get("height"),
                "weight":          p.get("weight"),
                "naver_player_id": p.get("playerId"),
            })
        return players

    except Exception as e:
        print(f"타자 기록 크롤링 오류: {e}")
        return []


def parse_innings_str(inn_str):
    """'7 2/3' 형태의 이닝 문자열을 소수로 변환"""
    if not inn_str:
        return 0.0
    inn_str = str(inn_str).strip()
    try:
        if ' ' in inn_str:
            parts = inn_str.split(' ')
            full = float(parts[0])
            frac = parts[1]
            if frac == '1/3':
                return full + 0.1
            elif frac == '2/3':
                return full + 0.2
            return full
        return float(inn_str)
    except Exception:
        return 0.0


def get_pitcher_stats(season=2026):
    """투수 시즌 기록 가져오기"""
    url = f"{BASE_API}/{season}/players?sortField=pitcherEra&sortDirection=asc&playerType=PITCHER&pageSize=500"
    try:
        res = requests.get(url, headers=HEADERS, timeout=10)
        res.raise_for_status()
        data = res.json()

        if not data.get("success"):
            print("API 응답 실패")
            return []

        players = []
        for p in data["result"]["seasonPlayerStats"]:
            import json as json_lib

            profile_str = p.get("profile", "{}")
            try:
                profile_data = json_lib.loads(profile_str)
                position = profile_data.get("position", "")
            except Exception:
                position = ""
            players.append({
                "player_id":         p.get("playerId"),
                "name":              p.get("playerName"),
                "team_code":         p.get("teamId"),
                "team_name":         p.get("teamName"),
                "player_type":       "투수",
                "position":          position,
                "number":            p.get("backNumber"),
                "season":            season,
                "games":             p.get("pitcherGameCount", 0),
                "wins":              p.get("pitcherWin", 0),
                "losses":            p.get("pitcherLose", 0),
                "saves":             p.get("pitcherSave", 0),
                "holds":             p.get("pitcherHold", 0) or 0,
                "innings_pitched":   parse_innings_str(p.get("pitcherInning", "0")),
                "hits_allowed":      p.get("pitcherHit", 0),
                "runs_allowed":      p.get("pitcherR", 0),
                "earned_runs":       p.get("pitcherEr", 0),
                "walks":             p.get("pitcherBb", 0),
                "strikeouts":        p.get("pitcherKk", 0),
                "home_runs_allowed": p.get("pitcherHr", 0),
                "era":               round(p.get("pitcherEra", 0) or 0, 2),
                "whip":              round(p.get("pitcherWhip", 0) or 0, 2),
                "war":               round(p.get("pitcherWar", 0) or 0, 2),
                "profile_image":     p.get("playerImageUrl"),
                "height":            p.get("height"),
                "weight":            p.get("weight"),
                "naver_player_id":   p.get("playerId"),
            })
        return players

    except Exception as e:
        print(f"투수 기록 크롤링 오류: {e}")
        return []


def save_players_and_stats(players, player_type):
    """선수 정보 + 통계 DB 저장"""
    
    deduped = {}
    for p in players:
        nid = p.get("naver_player_id")
        if not nid:
            continue
        if nid not in deduped or p.get('games', 0) > deduped[nid].get('games', 0):
            deduped[nid] = p
    players = list(deduped.values())
            
    conn = get_connection()
    if not conn:
        return

    cur = conn.cursor()
    saved_players = 0
    saved_stats = 0

    for p in players:
        try:
            cur.execute("SELECT id FROM teams WHERE short_name = %s", (p["team_code"],))
            team = cur.fetchone()
            if not team:
                continue

            player_db_id = None
            naver_id = p.get("naver_player_id")

            if naver_id:
                cur.execute("SELECT id FROM players WHERE naver_player_id = %s", (naver_id,))
                existing = cur.fetchone()
                if existing:
                    player_db_id = existing[0]

            if not player_db_id:
                cur.execute("SELECT id FROM players WHERE name = %s AND team_id = %s", (p["name"], team[0]))
                existing = cur.fetchone()
                if existing:
                    player_db_id = existing[0]

            if player_db_id:
                cur.execute("""
                    UPDATE players SET
                        number = %s, profile_image = %s, position = %s,
                        height = %s, weight = %s, team_id = %s,
                        player_type = %s, naver_player_id = %s
                    WHERE id = %s
                """, (
                    p["number"], p.get("profile_image"), p.get("position"),
                    p.get("height"), p.get("weight"), team[0],
                    "타자" if player_type == "HITTER" else "투수",
                    naver_id, player_db_id
                ))
            else:
                cur.execute("""
                    INSERT INTO players (name, team_id, player_type, number, profile_image, position, height, weight, naver_player_id)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                    RETURNING id
                """, (
                    p["name"], team[0], "타자" if player_type == "HITTER" else "투수",
                    p["number"], p.get("profile_image"), p.get("position"),
                    p.get("height"), p.get("weight"), naver_id
                ))
                result = cur.fetchone()
                if result:
                    player_db_id = result[0]
                else:
                    continue

            saved_players += 1

            if player_type == "HITTER":
                cur.execute("""
                    INSERT INTO batter_stats (
                        player_id, season, games, at_bats, runs, hits,
                        doubles, triples, home_runs, rbis, walks, strikeouts,
                        stolen_bases, avg, obp, slg, ops, woba, wrc_plus, babip, iso, war
                    ) VALUES (
                        %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s
                    )
                    ON CONFLICT (player_id, season) DO UPDATE SET
                        games        = GREATEST(EXCLUDED.games,        batter_stats.games),
                        at_bats      = GREATEST(EXCLUDED.at_bats,      batter_stats.at_bats),
                        runs         = GREATEST(EXCLUDED.runs,         batter_stats.runs),
                        hits         = GREATEST(EXCLUDED.hits,         batter_stats.hits),
                        doubles      = GREATEST(EXCLUDED.doubles,      batter_stats.doubles),
                        triples      = GREATEST(EXCLUDED.triples,      batter_stats.triples),
                        home_runs    = GREATEST(EXCLUDED.home_runs,    batter_stats.home_runs),
                        rbis         = GREATEST(EXCLUDED.rbis,         batter_stats.rbis),
                        walks        = GREATEST(EXCLUDED.walks,        batter_stats.walks),
                        strikeouts   = GREATEST(EXCLUDED.strikeouts,   batter_stats.strikeouts),
                        stolen_bases = GREATEST(EXCLUDED.stolen_bases, batter_stats.stolen_bases),
                        avg          = EXCLUDED.avg,
                        obp          = EXCLUDED.obp,
                        slg          = EXCLUDED.slg,
                        ops          = EXCLUDED.ops,
                        woba         = EXCLUDED.woba,
                        wrc_plus     = EXCLUDED.wrc_plus,
                        babip        = EXCLUDED.babip,
                        iso          = EXCLUDED.iso,
                        war          = EXCLUDED.war
                """, (
                    player_db_id, p["season"], p["games"], p["at_bats"],
                    p["runs"], p["hits"], p["doubles"], p["triples"],
                    p["home_runs"], p["rbis"], p["walks"], p["strikeouts"],
                    p["stolen_bases"], p["avg"], p["obp"], p["slg"], p["ops"],
                    p["woba"], p["wrc_plus"], p["babip"], p["iso"], p["war"],
                ))
            else:
                cur.execute("""
                    INSERT INTO pitcher_stats (
                        player_id, season, games, wins, losses, saves, holds,
                        innings_pitched, hits_allowed, runs_allowed, earned_runs,
                        walks, strikeouts, home_runs_allowed, era, whip, war
                    ) VALUES (
                        %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s
                    )
                    ON CONFLICT (player_id, season) DO UPDATE SET
                        games              = GREATEST(EXCLUDED.games,              pitcher_stats.games),
                        wins               = GREATEST(COALESCE(EXCLUDED.wins, 0),  COALESCE(pitcher_stats.wins, 0)),
                        losses             = GREATEST(COALESCE(EXCLUDED.losses, 0),COALESCE(pitcher_stats.losses, 0)),
                        saves              = GREATEST(COALESCE(EXCLUDED.saves, 0), COALESCE(pitcher_stats.saves, 0)),
                        holds              = COALESCE(EXCLUDED.holds,              pitcher_stats.holds),
                        innings_pitched    = GREATEST(EXCLUDED.innings_pitched,    pitcher_stats.innings_pitched),
                        hits_allowed       = GREATEST(EXCLUDED.hits_allowed,       pitcher_stats.hits_allowed),
                        runs_allowed       = GREATEST(EXCLUDED.runs_allowed,       pitcher_stats.runs_allowed),
                        earned_runs        = GREATEST(EXCLUDED.earned_runs,        pitcher_stats.earned_runs),
                        walks              = GREATEST(EXCLUDED.walks,              pitcher_stats.walks),
                        strikeouts         = GREATEST(EXCLUDED.strikeouts,         pitcher_stats.strikeouts),
                        home_runs_allowed  = GREATEST(EXCLUDED.home_runs_allowed,  pitcher_stats.home_runs_allowed),
                        era                = EXCLUDED.era,
                        whip               = EXCLUDED.whip,
                        war                = EXCLUDED.war
                """, (
                    player_db_id, p["season"], p["games"], p["wins"],
                    p["losses"], p["saves"], p["holds"], p["innings_pitched"],
                    p["hits_allowed"], p["runs_allowed"], p["earned_runs"],
                    p["walks"], p["strikeouts"], p["home_runs_allowed"],
                    p["era"], p["whip"], p["war"],
                ))
            saved_stats += 1

        except Exception as e:
            print(f"선수 저장 오류 ({p.get('name')}): {e}")
            conn.rollback()
            cur = conn.cursor()
            continue

    conn.commit()
    cur.close()
    conn.close()
    print(f"선수 {saved_players}명 신규 저장, 통계 {saved_stats}개 저장 완료")


def crawl_player_info_selenium():
    """셀레니움으로 선수 팀/생년월일/포지션 크롤링"""
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options
    from selenium.webdriver.chrome.service import Service
    from selenium.webdriver.common.by import By
    from webdriver_manager.chrome import ChromeDriverManager
    import re

    TEAM_NAME_MAP = {
        'KIA 타이거즈': 2, 'KT 위즈': 1, 'LG 트윈스': 9,
        'NC 다이노스': 6, 'SSG 랜더스': 10, '두산 베어스': 7,
        '롯데 자이언츠': 4, '삼성 라이온즈': 11, '키움 히어로즈': 8,
        '한화 이글스': 5,
    }

    options = Options()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--blink-settings=imagesEnabled=false')
    options.add_experimental_option('prefs', {
        'profile.managed_default_content_settings.images': 2,
        'profile.managed_default_content_settings.stylesheets': 2,
    })

    driver = webdriver.Chrome(
        service=Service(ChromeDriverManager().install()),
        options=options
    )

    conn = get_connection()
    if not conn:
        driver.quit()
        return

    cur = conn.cursor()
    cur.execute("""
        SELECT DISTINCT p.id, p.name, p.naver_player_id, p.player_type, p.birth_date
        FROM players p
        WHERE p.naver_player_id IS NOT NULL
        AND (p.position IS NULL OR p.position = '')
        AND EXISTS (
            SELECT 1 FROM game_rosters gr WHERE gr.player_id = p.id
        )
        ORDER BY p.id
    """)
    players = cur.fetchall()
    print(f"크롤링 대상: {len(players)}명")

    updated = 0
    for (db_id, name, naver_id, player_type, birth_date) in players:
        try:
            if player_type == '타자':
                url = f"https://www.koreabaseball.com/Record/Player/HitterDetail/Basic.aspx?playerId={naver_id}"
            else:
                url = f"https://www.koreabaseball.com/Record/Player/PitcherDetail/Basic.aspx?playerId={naver_id}"

            driver.get(url)
            time.sleep(1.5)
            text = driver.find_element(By.TAG_NAME, 'body').text

            team_id = None
            for team_name, tid in TEAM_NAME_MAP.items():
                if team_name in text:
                    team_id = tid
                    break

            new_birth_date = None
            match = re.search(r'생년월일:\s*(\d{4})년\s*(\d{2})월\s*(\d{2})일', text)
            if match:
                new_birth_date = f"{match.group(1)}-{match.group(2)}-{match.group(3)}"

            number = None
            match_num = re.search(r'등번호[:\s]*No\.(\d+)', text)
            if match_num:
                number = match_num.group(1)

            height = None
            weight = None
            match_hw = re.search(r'신장/체중[:\s]*(\d{3})cm/(\d{2,3})kg', text)
            if match_hw:
                height = match_hw.group(1)
                weight = match_hw.group(2)

            position = None
            match_pos = re.search(r'포지션[:\s]*([^\n]+)', text)
            if match_pos:
                position = match_pos.group(1).strip().split('(')[0].strip()

            if team_id or new_birth_date or number or height or position:
                cur.execute("""
                    UPDATE players SET
                        team_id = COALESCE(%s, team_id),
                        birth_date = COALESCE(%s, birth_date),
                        number = COALESCE(%s, number),
                        height = COALESCE(%s, height),
                        weight = COALESCE(%s, weight),
                        position = COALESCE(%s, position),
                        profile_image = COALESCE(profile_image, %s)
                    WHERE id = %s
                """, (
                    team_id, new_birth_date, number, height, weight, position,
                    f"https://sports-phinf.pstatic.net/player/kbo/default/{naver_id}.png",
                    db_id
                ))
                updated += 1
                print(f"{name}: 팀={team_id}, 포지션={position}")

            conn.commit()

        except Exception as e:
            print(f"오류 ({name}): {e}")
            try:
                conn.rollback()
            except:
                pass
            continue

    driver.quit()
    cur.close()
    conn.close()
    print(f"총 {updated}명 업데이트 완료")


def crawl_missing_player_ids():
    """naver_player_id 없는 선수들 KBO에서 검색해서 업데이트"""
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options
    from selenium.webdriver.chrome.service import Service
    from selenium.webdriver.common.by import By
    from selenium.webdriver.support.ui import Select
    from webdriver_manager.chrome import ChromeDriverManager

    options = Options()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_experimental_option('prefs', {
        'profile.managed_default_content_settings.images': 2,
    })

    driver = webdriver.Chrome(
        service=Service(ChromeDriverManager().install()), options=options
    )

    conn = get_connection()
    if not conn:
        driver.quit()
        return

    cur = conn.cursor()
    cur.execute("""
        SELECT p.id, p.name, t.name AS team
        FROM players p
        JOIN teams t ON p.team_id = t.id
        WHERE p.naver_player_id IS NULL
        ORDER BY t.name, p.name
    """)
    players = cur.fetchall()
    print(f'naver_player_id 없는 선수: {len(players)}명')

    team_players = {}
    teams = ['KIA', 'KT', 'LG', 'SSG', '삼성', 'NC', '두산', '한화', '키움', '롯데']

    for team in teams:
        try:
            driver.get('https://www.koreabaseball.com/Player/Search.aspx')
            time.sleep(1.5)
            selects = driver.find_elements(By.CSS_SELECTOR, 'select')
            if selects:
                Select(selects[0]).select_by_visible_text(team)
                time.sleep(1.5)
            links = driver.find_elements(By.CSS_SELECTOR, 'a[href*="playerId"]')
            team_players[team] = {}
            for link in links:
                name = link.text.strip()
                href = link.get_attribute('href') or ''
                if 'playerId=' in href:
                    player_id = href.split('playerId=')[-1]
                    team_players[team][name] = player_id
            print(f'{team}: {len(team_players[team])}명 수집')
        except Exception as e:
            print(f'{team} 오류: {e}')
            continue

    driver.quit()

    updated = 0
    for (db_id, name, team) in players:
        if team not in team_players:
            continue
        player_id = team_players[team].get(name)
        if not player_id:
            continue

        cur.execute("""
            UPDATE players SET
                naver_player_id = %s,
                profile_image = %s
            WHERE id = %s
        """, (
            player_id,
            f"https://sports-phinf.pstatic.net/player/kbo/default/{player_id}.png",
            db_id
        ))
        updated += 1
        print(f'{name} ({team}): {player_id}')

    conn.commit()
    cur.close()
    conn.close()
    print(f'총 {updated}명 업데이트 완료')


def _collect_players_from_page(driver):
    """현재 페이지에서 선수 목록 수집"""
    from selenium.webdriver.common.by import By
    players = []
    links = driver.find_elements(By.CSS_SELECTOR, 'a[href*="playerId"]')
    for link in links:
        name = link.text.strip()
        href = link.get_attribute('href') or ''
        if 'playerId=' not in href or not name:
            continue
        naver_id = href.split('playerId=')[-1]
        player_type = '타자' if 'Hitter' in href else '투수'
        players.append({
            'name': name,
            'naver_player_id': naver_id,
            'player_type': player_type,
        })
    return players


def crawl_all_kbo_players():
    """KBO 전체 선수 크롤링 및 DB 업데이트"""
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options
    from selenium.webdriver.chrome.service import Service
    from selenium.webdriver.common.by import By
    from selenium.webdriver.support.ui import Select
    from webdriver_manager.chrome import ChromeDriverManager

    TEAM_NAME_MAP = {
        'KIA': 2, 'KT': 1, 'LG': 9, 'SSG': 10, '삼성': 11,
        'NC': 6, '두산': 7, '한화': 5, '키움': 8, '롯데': 4,
    }

    options = Options()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_experimental_option('prefs', {
        'profile.managed_default_content_settings.images': 2,
    })

    driver = webdriver.Chrome(
        service=Service(ChromeDriverManager().install()), options=options
    )

    conn = get_connection()
    if not conn:
        driver.quit()
        return

    cur = conn.cursor()
    teams = ['KIA', 'KT', 'LG', 'SSG', '삼성', 'NC', '두산', '한화', '키움', '롯데']
    total_updated = 0

    for team in teams:
        print(f'\n=== {team} 선수 크롤링 ===')
        all_players = []

        try:
            driver.get('https://www.koreabaseball.com/Player/Search.aspx')
            time.sleep(2)

            selects = driver.find_elements(By.CSS_SELECTOR, 'select')
            if selects:
                Select(selects[0]).select_by_visible_text(team)
                time.sleep(2)

            page_links = driver.find_elements(By.CSS_SELECTOR, 'a[href*="btnNo"]')
            total_pages = len(page_links) if page_links else 1
            print(f'{team} 페이지 수: {total_pages}')

            all_players.extend(_collect_players_from_page(driver))

            for page_num in range(2, total_pages + 1):
                try:
                    btn = driver.find_element(By.CSS_SELECTOR, f'a[href*="btnNo{page_num}"]')
                    btn.click()
                    time.sleep(2)
                    all_players.extend(_collect_players_from_page(driver))
                except Exception as e:
                    print(f'페이지 {page_num} 오류: {e}')
                    break

        except Exception as e:
            print(f'{team} 크롤링 오류: {e}')
            continue

        print(f'{team} 총 {len(all_players)}명 수집')
        team_id = TEAM_NAME_MAP.get(team)
        if not team_id:
            continue

        for p in all_players:
            try:
                name = p['name']
                naver_id = p['naver_player_id']
                profile_image = f"https://sports-phinf.pstatic.net/player/kbo/default/{naver_id}.png"

                cur.execute("SELECT id FROM players WHERE naver_player_id = %s", (naver_id,))
                existing = cur.fetchone()

                if existing:
                    cur.execute("""
                        UPDATE players SET
                            team_id = %s,
                            profile_image = COALESCE(profile_image, %s)
                        WHERE id = %s
                    """, (team_id, profile_image, existing[0]))
                else:
                    cur.execute("""
                        SELECT id FROM players WHERE name = %s AND team_id = %s
                    """, (name, team_id))
                    existing = cur.fetchone()

                    if existing:
                        cur.execute("""
                            UPDATE players SET
                                naver_player_id = %s,
                                profile_image = COALESCE(profile_image, %s)
                            WHERE id = %s
                        """, (naver_id, profile_image, existing[0]))
                    else:
                        cur.execute("""
                            INSERT INTO players (name, team_id, naver_player_id, profile_image, player_type)
                            VALUES (%s, %s, %s, %s, %s)
                            ON CONFLICT DO NOTHING
                        """, (name, team_id, naver_id, profile_image, p.get('player_type', '투수')))

                total_updated += 1

            except Exception as e:
                print(f'선수 저장 오류 ({name}): {e}')
                conn.rollback()
                cur = conn.cursor()
                continue

        conn.commit()

    driver.quit()
    cur.close()
    conn.close()
    print(f'\n총 {total_updated}명 업데이트 완료')


if __name__ == "__main__":
    print("=== 타자 기록 수집 ===")
    hitters = get_hitter_stats(2026)
    print(f"타자 {len(hitters)}명 수집")
    save_players_and_stats(hitters, "HITTER")

    print("\n=== 투수 기록 수집 ===")
    pitchers = get_pitcher_stats(2026)
    print(f"투수 {len(pitchers)}명 수집")
    save_players_and_stats(pitchers, "PITCHER")

    print("\n=== naver_player_id 없는 선수 검색 ===")
    crawl_missing_player_ids()

    print("\n=== 선수 정보 크롤링 (셀레니움) ===")
    crawl_player_info_selenium()