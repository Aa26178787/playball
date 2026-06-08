
import os, sys, time, re
import psycopg2
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By

DB_CONFIG = {
    "host": "localhost",
    "port": 5433,  # SSH 터널
    "database": "playball",
    "user": "playball_user",
    "password": os.environ.get("DB_PASSWORD", "playball1234"),
}

def get_connection():
    try:
        return psycopg2.connect(**DB_CONFIG)
    except Exception as e:
        print(f"DB 연결 오류: {e}")
        return None

def get_driver():
    options = Options()
    options.add_experimental_option('prefs', {
        'profile.managed_default_content_settings.images': 2,
        'profile.managed_default_content_settings.stylesheets': 2,
    })
    return webdriver.Chrome(options=options)

def safe_int(val):
    try:
        return int(val)
    except:
        return None

def safe_float(val):
    try:
        return float(val)
    except:
        return None

def parse_innings(ip_raw, next_val=None):
    try:
        if ip_raw in ['1/3', '2/3']:
            return 0.1 if ip_raw == '1/3' else 0.2
        if next_val in ['1/3', '2/3']:
            return float(ip_raw) + (0.1 if next_val == '1/3' else 0.2)
        return float(ip_raw)
    except:
        return 0.0

def parse_daily_hitter(lines):
    """타자 일자별 기록 파싱"""
    records = []
    in_section = False

    for line in lines:
        line = line.strip()
        if not line:
            continue
        if '개인정보' in line or 'Copyright' in line:
            break
        if line.startswith('합계'):
            continue

        # 월별 헤더 감지
        if re.match(r'^\d+월\s+상대', line):
            in_section = True
            continue

        if not in_section:
            continue

        vals = line.split()
        if len(vals) < 3:
            continue

        # 날짜 형식 MM.DD
        if not re.match(r'^\d{2}\.\d{2}$', vals[0]):
            continue

        try:
            date_str = f"2026-{vals[0].replace('.', '-')}"
            records.append({
                'game_date': date_str,
                'opponent': vals[1],
                'stat_type': 'hitter',
                'avg': safe_float(vals[2]),
                'pa': safe_int(vals[3]),
                'ab': safe_int(vals[4]),
                'runs': safe_int(vals[5]),
                'hits': safe_int(vals[6]),
                'doubles': safe_int(vals[7]),
                'triples': safe_int(vals[8]),
                'home_runs': safe_int(vals[9]),
                'rbi': safe_int(vals[10]),
                'sb': safe_int(vals[11]),
                'cs': safe_int(vals[12]),
                'walks': safe_int(vals[13]),
                'hbp': safe_int(vals[14]),
                'strikeouts': safe_int(vals[15]),
                'gdp': safe_int(vals[16]) if len(vals) > 16 else None,
            })
        except:
            continue

    return records

def parse_daily_pitcher(lines):
    """투수 일자별 기록 파싱"""
    records = []
    in_section = False

    for line in lines:
        line = line.strip()
        if not line:
            continue
        if '개인정보' in line or 'Copyright' in line:
            break
        if line.startswith('합계'):
            continue

        if re.match(r'^\d+월\s+상대', line):
            in_section = True
            continue

        if not in_section:
            continue

        vals = line.split()
        if len(vals) < 3:
            continue

        if not re.match(r'^\d{2}\.\d{2}$', vals[0]):
            continue

        try:
            date_str = f"2026-{vals[0].replace('.', '-')}"
            # 투수: 일자 상대 결과 ERA TBF IP H HR BB HBP SO R ER AVG
            result = vals[2] if vals[2] in ['승', '패', '세이브', '홀드', '블론'] else None
            offset = 1 if result else 0

            ip_raw = vals[3 + offset]
            next_v = vals[4 + offset] if 4 + offset < len(vals) else None
            ip = parse_innings(ip_raw, next_v)
            ip_offset = 1 if next_v in ['1/3', '2/3'] else 0

            base = 4 + offset + ip_offset
            records.append({
                'game_date': date_str,
                'opponent': vals[1],
                'result': result,
                'stat_type': 'pitcher',
                'era': safe_float(vals[2 + offset]) if not result else safe_float(vals[3]),
                'pa': safe_int(vals[base - 1]) if base > 4 else None,
                'ip': ip,
                'h': safe_int(vals[base]),
                'hr': safe_int(vals[base + 1]),
                'bb': safe_int(vals[base + 2]),
                'so': safe_int(vals[base + 4]),
                'r': safe_int(vals[base + 5]),
                'er': safe_int(vals[base + 6]),
            })
        except:
            continue

    return records


def save_daily_stats(cur, player_id, records):
    saved = 0
    for r in records:
        try:
            cur.execute("""
                INSERT INTO player_daily_stats (
                    player_id, game_date, opponent, result, stat_type,
                    avg, pa, ab, runs, hits, doubles, triples, home_runs,
                    rbi, sb, cs, walks, hbp, strikeouts, gdp,
                    era, ip, h, hr, bb, so, r, er
                ) VALUES (
                    %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s, %s, %s, %s
                )
                ON CONFLICT (player_id, game_date, opponent, stat_type) DO UPDATE SET
                    avg = EXCLUDED.avg, pa = EXCLUDED.pa, ab = EXCLUDED.ab,
                    runs = EXCLUDED.runs, hits = EXCLUDED.hits,
                    era = EXCLUDED.era, ip = EXCLUDED.ip
            """, (
                player_id, r.get('game_date'), r.get('opponent'),
                r.get('result'), r.get('stat_type'),
                r.get('avg'), r.get('pa'), r.get('ab'),
                r.get('runs'), r.get('hits'), r.get('doubles'),
                r.get('triples'), r.get('home_runs'), r.get('rbi'),
                r.get('sb'), r.get('cs'), r.get('walks'), r.get('hbp'),
                r.get('strikeouts'), r.get('gdp'),
                r.get('era'), r.get('ip'), r.get('h'), r.get('hr'),
                r.get('bb'), r.get('so'), r.get('r'), r.get('er'),
            ))
            saved += 1
        except:
            continue
    return saved

def main():
    conn = get_connection()
    if not conn:
        print("DB 연결 실패! SSH 터널 확인하세요.")
        return

    cur = conn.cursor()

    # daily_stats 없는 선수만
    cur.execute("""
        SELECT p.id, p.name, p.naver_player_id, p.player_type
        FROM players p
        WHERE p.naver_player_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1 FROM player_daily_stats pds WHERE pds.player_id = p.id
        )
        ORDER BY p.id
    """)
    players = cur.fetchall()
    cur.close()
    conn.close()

    print(f"크롤링 대상: {len(players)}명")

    driver = get_driver()
    updated = 0
    errors = 0

    for idx, (player_id, name, naver_id, player_type) in enumerate(players):
        try:
            ptype = 'Hitter' if player_type == '타자' else 'Pitcher'
            base_url = f"https://www.koreabaseball.com/Record/Player/{ptype}Detail"

            # 일자별 기록
            driver.get(f"{base_url}/Daily.aspx?playerId={naver_id}")
            time.sleep(1.5)
            daily_lines = driver.find_element(By.TAG_NAME, 'body').text.split('\n')

            if player_type == '타자':
                daily_records = parse_daily_hitter(daily_lines)
            else:
                daily_records = parse_daily_pitcher(daily_lines)

            # DB 저장
            conn = get_connection()
            if not conn:
                continue
            cur = conn.cursor()

            daily_saved = save_daily_stats(cur, player_id, daily_records)
            

            conn.commit()
            cur.close()
            conn.close()

            updated += 1
            print(f"[{idx+1}/{len(players)}] {name} ({player_type}): "
                  f"daily={daily_saved}개")

        except Exception as e:
            errors += 1
            print(f"오류 ({name}): {e}")
            try:
                conn.rollback()
                conn.close()
            except:
                pass
            continue

    driver.quit()
    print(f"\n완료! 업데이트: {updated}명, 오류: {errors}명")

if __name__ == "__main__":
    main()