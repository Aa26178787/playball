from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
import os, time, re, psycopg2

DB_CONFIG = {
    'host': 'localhost', 'port': 5433,
    'database': 'playball', 'user': 'playball_user',
    'password': os.environ.get('DB_PASSWORD', '')
}

def get_connection():
    return psycopg2.connect(**DB_CONFIG)

PITCH_RESULT_MAP = {
    '볼': 'B', '스트라이크': 'T', '헛스윙': 'S',
    '파울': 'F', '타격': 'H', '번트헛스윙': 'V', '번트파울': 'W'
}
STUFF_MAP = {
    '직구': '직구', '투심': '투심', '커터': '커터', '슬라이더': '슬라이더',
    '체인지업': '체인지업', '커브': '커브', '포크': '포크', '스플리터': '스플리터',
    '스위퍼': '스위퍼', '싱커': '싱커', '너클볼': '너클볼'
}

def is_inning_header(line):
    return bool(re.match(r'^\d+회\s*(초|말)\s+\S+\s*공\s*격', line))

def is_stat_line(line):
    return bool(
        re.match(r'^(타석|타수|안타|득점|타점|홈런|볼넷|피삼진)\d+', line) or
        re.match(r'^투구\s*위치\s*보기', line) or
        re.match(r'^기록\s*펼치기', line)
    )

def is_ui_noise(line):
    ui_set = {
        '볼 카운트', '구', '1루', '2루', '3루', 'OUT', 'IN', 'O', 'B', 'S',
        '투수', '포수', '1루수', '2루수', '3루수', '유격수',
        '좌익수', '중견수', '우익수', '지명타자', '타자',
        '초', '말', '회', '자동 업데이트', '새로고침', '주루 정보',
        '중계', '선수엔드 바로가기', '대기타석', '득점 상세로 이동',
        '맨 위로', '경기가 종료되었습니다.',
    }
    if line in ui_set:
        return True
    if re.match(r'^\d+회$', line):
        return True
    if re.match(r'^\d+ - \d+$', line):
        return True
    if re.match(r'^\d+km/h', line):
        return True
    if re.match(r'.*승리\s*확률.*업데이트\s*중', line):
        return True
    if re.match(r'^\d+\.\S+', line):
        return True
    if re.match(r'^투구수\s*\d+', line):
        return True
    if re.match(r'^타석보기$', line):
        return True
    if re.match(r'^(투수|포수|1루수|2루수|3루수|유격수|좌익수|중견수|우익수|지명타자)\s*:\s*.+', line):
        return True
    if re.match(r'^\d루\s*주자\s*:\s*.+', line) and not any(x in line for x in ['진루', '아웃', '홈인', '도루', '태그', '견제']):
        return True
    if any(x in line for x in [
        'NAVER', '스포츠', '뉴스', '순위', '일정', '메뉴', '전력', '응원',
        '라인업', '영상', '기록', '농구', '배구', '축구', '골프', '로그인',
        '고객센터', '대표이사', '주소', '전화', '이메일', '사업자', '통신판매',
        '기사배열', '청소년', '저작권', 'Copyright', '분당구', '성남시',
        '1588', 'ccnaver', '220-81', '경기 선택', '경기종료', '경기 주요',
        '스코어보드', '팀명', '한 줄평', '베타', '안내', '접기', '좋아요',
        '댓글', '가장 핫한', '자세히보기', '경기 상세', '경기가 종료',
        '승 승리투수', '패 패전투수', '점수', 'R H E B', '선수 페이지',
    ]):
        return True
    return False

def get_event_type(line):
    if re.match(r'^(코칭스태프|포수)\s*마운드\s*방문', line):
        return 7, line
    if re.match(r'^투수\s*투수판\s*이탈', line):
        return 7, line
    if re.match(r'^(대주자|대타|지명타자|포수|투수|1루수|2루수|3루수|유격수|좌익수|중견수|우익수)\s+\S+.*수비위치\s*변경', line):
        return 24, line
    if re.match(r'^\d+회\s*\d+번\s*타순.*판독', line):
        return 22, line
    if re.match(r'^\d루\s*주자.*:\s*(홈인|진루|아웃|태그아웃|포스아웃|견제사아웃|도루)', line):
        return 24, line
    if re.match(r'^\d루\s*주자.*:\s*.+', line):
        return 14, line
    return None, None

def parse_sub_block(lines, i):
    out_pos = None
    out_player = None
    in_pos = None
    in_player = None
    while i < len(lines):
        l = lines[i]
        if l == 'OUT':
            i += 1
            continue
        if l == 'IN':
            i += 1
            break
        m = re.match(r'^(투수|포수|1루수|2루수|3루수|유격수|좌익수|중견수|우익수|지명타자|대주자|\d루\s*주자)\s*:\s*(.+)', l)
        if m:
            pos = m.group(1).strip()
            player = m.group(2).strip()
            if out_player is None:
                out_pos = pos
                out_player = player
            else:
                in_pos = pos
                in_player = player
            i += 1
        else:
            break
    if out_player and in_player:
        title = f'{out_pos} {out_player} : {in_pos} {in_player} (으)로 교체'
    elif in_player:
        title = f'교체 -> {in_player}'
    else:
        title = '교체'
    return title, i

def get_pitchers_from_lineup(driver, home_team, away_team):
    buttons = driver.find_elements(By.TAG_NAME, 'button')
    for btn in buttons:
        if btn.text.strip() == '라인업':
            btn.click()
            time.sleep(3)
            break

    text = driver.find_element(By.TAG_NAME, 'body').text
    lines = [l.strip() for l in text.split('\n') if l.strip()]

    home_starter = None
    away_starter = None
    current_side = None
    i = 0

    while i < len(lines):
        line = lines[i]

        if '불펜투수' in line or '후보야수' in line:
            break

        if re.match(r'.+선발$', line) and len(line) < 20:
            team_name = line.replace('선발', '').strip()
            if home_team and (team_name in home_team or home_team in team_name):
                current_side = 'home'
            elif away_team and (team_name in away_team or away_team in team_name):
                current_side = 'away'
            i += 1
            continue

        if line == '선발' and current_side:
            i += 1
            if i < len(lines):
                pitcher_name = lines[i].strip()
                if current_side == 'home':
                    home_starter = pitcher_name
                else:
                    away_starter = pitcher_name
                i += 1
                if i < len(lines) and re.match(r'^[좌우][투완언]', lines[i]):
                    i += 1
            continue

        i += 1

    return home_starter, away_starter


def parse_inning_relay(lines, inning, inning_half, pitchers, pitcher_idx=0):

    def get_p(idx):
        if not pitchers:
            return None
        return pitchers[min(idx, len(pitchers) - 1)]

    # 1단계: 타자 블록과 타자 사이 교체 수집
    at_bats_raw = []
    current_batter = None
    current_events = []
    # 타자 사이 교체 수 (역순 기준, 현재 타자 이전까지)
    inter_changes = 0
    i = 0

    while i < len(lines):
        line = lines[i]

        if is_stat_line(line) or is_ui_noise(line):
            i += 1
            continue

        if is_inning_header(line) or '공지' in line:
            break

        if line == '교체':
            i += 1
            title, i = parse_sub_block(lines, i)
            is_pc = '투수' in title and title != '교체'

            if current_batter is not None:
                # 현재 타자 블록 내 교체
                current_events.append(('sub', title, is_pc))
            else:
                # 타자 블록 사이 교체 (이닝 시작 전이거나 타자 사이)
                pass

            if is_pc:
                inter_changes += 1
            continue

        etype, etitle = get_event_type(line)

        batter_match = re.match(r'^(.+?)(\d+번\s*타자\s*타율)', line)
        if batter_match:
            if current_batter is not None:
                # 현재 타자 블록 내 교체 수
                intra_changes = sum(1 for e in current_events if e[0] == 'sub' and e[2])
                # 이 타자 이전까지의 타자 사이 교체 수 = 전체 교체수 - 이 타자 블록 내 교체수
                at_bats_raw.append((current_batter, current_events, inter_changes - intra_changes))
            current_batter = batter_match.group(1).strip()
            current_events = []
            i += 1
            while i < len(lines) and is_stat_line(lines[i]):
                i += 1
            continue

        if etype is not None and current_batter is not None:
            current_events.append(('event', etype, etitle))
            i += 1
            continue

        if current_batter and ' : ' in line and not re.match(r'^\d루\s*주자', line):
            current_events.append(('result', line))
            i += 1
            if i < len(lines) and re.match(r'^기록\s*펼치기', lines[i]):
                i += 1
            if i < len(lines) and '승리 확률' in lines[i] and '업데이트 중' not in lines[i]:
                wr_match = re.search(r'(\d+\.?\d*)%', lines[i])
                if wr_match:
                    current_events.append(('winrate', float(wr_match.group(1))))
                i += 1
            continue

        if current_batter and re.match(r'^\d+$', line) and i + 1 < len(lines) and re.match(r'^구\s*$', lines[i+1]):
            pitch_num = int(line)
            i += 2
            pitch_result_text = lines[i] if i < len(lines) else ''
            pitch_result = PITCH_RESULT_MAP.get(pitch_result_text)
            i += 1
            speed = 0
            stuff = None
            if i < len(lines):
                sm = re.match(r'(\d+)km/h(.+)', lines[i])
                if sm:
                    speed = int(sm.group(1))
                    stuff = STUFF_MAP.get(sm.group(2).strip(), sm.group(2).strip())
                    i += 1
            if i < len(lines) and re.match(r'^볼\s*카운트', lines[i]):
                i += 1
            if i < len(lines) and re.match(r'^\d+ - \d+$', lines[i]):
                i += 1
            current_events.append(('pitch', pitch_num, pitch_result, stuff, speed, pitch_result_text))
            continue

        i += 1

    if current_batter is not None:
        intra_changes = sum(1 for e in current_events if e[0] == 'sub' and e[2])
        at_bats_raw.append((current_batter, current_events, inter_changes - intra_changes))

    total_inter_changes = inter_changes

    # 2단계: 역순 → 정순
    at_bats_raw.reverse()

    records = []
    seqno = 0
    running_pitcher_idx = pitcher_idx

    for batter_name, events, changes_after_inter in at_bats_raw:
        # 정순 기준 이 타자 이전까지의 타자 사이 교체 수
        # = 전체 타자 사이 교체 수 - 역순 기준 이 타자 이후의 타자 사이 교체 수
        base_idx = pitcher_idx + (total_inter_changes - changes_after_inter)

        def get_pitcher(extra=0):
            if not pitchers:
                return None
            return pitchers[min(base_idx + extra, len(pitchers) - 1)]

        # type=8
        seqno += 1
        records.append({
            'inning': inning, 'inning_half': inning_half, 'seqno': seqno,
            'batter_name': batter_name, 'pitcher_name': get_pitcher(0),
            'pitch_num': None, 'pitch_result': None, 'stuff': None, 'speed': 0,
            'title': f'타자 {batter_name}', 'type': 8,
            'home_win_rate': None, 'away_win_rate': None,
        })

        # 이벤트 분류
        pre_events = []
        pitches = []
        post_events = []
        result_event = None
        winrate_event = None
        in_pitches = False

        for ev in events:
            if ev[0] == 'result':
                result_event = ev
            elif ev[0] == 'winrate':
                winrate_event = ev
            elif ev[0] == 'pitch':
                in_pitches = True
                pitches.append(ev)
            elif ev[0] == 'sub':
                if not in_pitches:
                    pre_events.append(ev)
                else:
                    post_events.append(ev)
            elif ev[0] == 'event':
                if not in_pitches:
                    pre_events.append(ev)
                else:
                    post_events.append(ev)

        # 타석 전 이벤트
        cur_pre_pc = 0
        for ev in pre_events:
            seqno += 1
            if ev[0] == 'sub':
                _, title, is_pc = ev
                if is_pc:
                    cur_pre_pc += 1
                records.append({
                    'inning': inning, 'inning_half': inning_half, 'seqno': seqno,
                    'batter_name': batter_name, 'pitcher_name': get_pitcher(cur_pre_pc),
                    'pitch_num': None, 'pitch_result': None, 'stuff': None, 'speed': 0,
                    'title': title, 'type': 2,
                    'home_win_rate': None, 'away_win_rate': None,
                })
            else:
                _, etype, etitle = ev
                records.append({
                    'inning': inning, 'inning_half': inning_half, 'seqno': seqno,
                    'batter_name': batter_name, 'pitcher_name': get_pitcher(cur_pre_pc),
                    'pitch_num': None, 'pitch_result': None, 'stuff': None, 'speed': 0,
                    'title': etitle, 'type': etype,
                    'home_win_rate': None, 'away_win_rate': None,
                })

        # 투구 역순 → 정순
        pitches.reverse()

        # 투구
        for p in pitches:
            seqno += 1
            records.append({
                'inning': inning, 'inning_half': inning_half, 'seqno': seqno,
                'batter_name': batter_name, 'pitcher_name': get_pitcher(cur_pre_pc),
                'pitch_num': p[1], 'pitch_result': p[2],
                'stuff': p[3], 'speed': p[4],
                'title': f'{p[1]}구 {p[5]}',
                'type': 1,
                'home_win_rate': None, 'away_win_rate': None,
            })

        # 투구 사이 이벤트
        post_pc = cur_pre_pc
        for ev in post_events:
            seqno += 1
            if ev[0] == 'sub':
                _, title, is_pc = ev
                if is_pc:
                    post_pc += 1
                records.append({
                    'inning': inning, 'inning_half': inning_half, 'seqno': seqno,
                    'batter_name': batter_name, 'pitcher_name': get_pitcher(post_pc),
                    'pitch_num': None, 'pitch_result': None, 'stuff': None, 'speed': 0,
                    'title': title, 'type': 2,
                    'home_win_rate': None, 'away_win_rate': None,
                })
            else:
                _, etype, etitle = ev
                records.append({
                    'inning': inning, 'inning_half': inning_half, 'seqno': seqno,
                    'batter_name': batter_name, 'pitcher_name': get_pitcher(post_pc),
                    'pitch_num': None, 'pitch_result': None, 'stuff': None, 'speed': 0,
                    'title': etitle, 'type': etype,
                    'home_win_rate': None, 'away_win_rate': None,
                })

        # 타석 결과
        if result_event:
            win_h = None
            win_a = None
            if winrate_event:
                rate = winrate_event[1]
                if inning_half == '1':
                    win_h, win_a = rate, round(100 - rate, 1)
                else:
                    win_a, win_h = rate, round(100 - rate, 1)
            seqno += 1
            records.append({
                'inning': inning, 'inning_half': inning_half, 'seqno': seqno,
                'batter_name': batter_name, 'pitcher_name': get_pitcher(post_pc),
                'pitch_num': None, 'pitch_result': None, 'stuff': None, 'speed': 0,
                'title': result_event[1], 'type': 13,
                'home_win_rate': win_h, 'away_win_rate': win_a,
            })

        running_pitcher_idx = base_idx + post_pc

    return records, running_pitcher_idx


def save_records(cur, db_game_id, records):
    for r in records:
        cur.execute("""
            INSERT INTO game_pitches (
                game_id, inning, inning_half, seqno,
                batter_name, pitcher_name,
                pitch_num, pitch_result, stuff, speed,
                strike, ball, out, base1, base2, base3,
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
            db_game_id, r['inning'], r['inning_half'], r['seqno'],
            r['batter_name'], r['pitcher_name'],
            r['pitch_num'], r['pitch_result'], r['stuff'], r['speed'],
            0, 0, 0, False, False, False, None, None,
            r['title'], '', r['type'],
            r['home_win_rate'], r['away_win_rate'],
        ))


def crawl_game(driver, db_game_id, naver_game_id, max_inning, home_team, away_team):
    conn = get_connection()
    cur = conn.cursor()

    driver.get(f'https://m.sports.naver.com/game/{naver_game_id}/relay')
    time.sleep(8)

    home_starter, away_starter = get_pitchers_from_lineup(driver, home_team, away_team)

    cur.execute("""
        SELECT p.name, gp.team_side, gp.pitching_order
        FROM game_pitchers gp
        JOIN players p ON gp.player_id = p.id
        WHERE gp.game_id = %s
        ORDER BY gp.team_side, gp.pitching_order
    """, (db_game_id,))
    pitcher_rows = cur.fetchall()

    home_pitchers_db = [r[0] for r in pitcher_rows if r[1] == 'home']
    away_pitchers_db = [r[0] for r in pitcher_rows if r[1] == 'away']

    if home_starter and home_starter in home_pitchers_db:
        home_pitchers_db.insert(0, home_pitchers_db.pop(home_pitchers_db.index(home_starter)))
    elif home_starter:
        home_pitchers_db.insert(0, home_starter)
    home_pitchers = home_pitchers_db

    if away_starter and away_starter in away_pitchers_db:
        away_pitchers_db.insert(0, away_pitchers_db.pop(away_pitchers_db.index(away_starter)))
    elif away_starter:
        away_pitchers_db.insert(0, away_starter)
    away_pitchers = away_pitchers_db

    print(f'  홈({home_team}) 투수: {home_pitchers[:3]}')
    print(f'  원정({away_team}) 투수: {away_pitchers[:3]}')

    buttons = driver.find_elements(By.TAG_NAME, 'button')
    for btn in buttons:
        if btn.text.strip() == '중계':
            btn.click()
            time.sleep(2)
            break

    cur.execute("DELETE FROM game_pitches WHERE game_id = %s", (db_game_id,))

    total = 0
    home_pitcher_idx = 0
    away_pitcher_idx = 0

    for inning in range(1, (max_inning or 9) + 1):
        buttons = driver.find_elements(By.TAG_NAME, 'button')
        for btn in buttons:
            if btn.text.strip() == f'{inning}회':
                btn.click()
                time.sleep(3)
                break

        text = driver.find_element(By.TAG_NAME, 'body').text
        lines = [l.strip() for l in text.split('\n') if l.strip()]

        sections = {}
        for half, pattern in [
            ('0', rf'^{inning}회\s*초\s+\S+\s*공\s*격'),
            ('1', rf'^{inning}회\s*말\s+\S+\s*공\s*격'),
        ]:
            start = -1
            end = len(lines)
            for idx, line in enumerate(lines):
                if re.match(pattern, line) and start == -1:
                    start = idx + 1
                elif start > 0 and is_inning_header(line) and idx > start:
                    end = idx
                    break
                elif start > 0 and '공지' in line:
                    end = idx
                    break
            if start > 0:
                sections[half] = lines[start:end]

        for half, pitchers, idx_key in [
            ('0', home_pitchers, 'home'),
            ('1', away_pitchers, 'away'),
        ]:
            if half not in sections:
                continue
            section = sections[half]
            cur_idx = home_pitcher_idx if idx_key == 'home' else away_pitcher_idx
            records, new_idx = parse_inning_relay(section, inning, half, pitchers, cur_idx)
            if idx_key == 'home':
                home_pitcher_idx = new_idx
            else:
                away_pitcher_idx = new_idx
            save_records(cur, db_game_id, records)
            total += len(records)

        print(f'  {inning}회 완료', flush=True)

    conn.commit()
    cur.close()
    conn.close()
    return total


def main():
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT g.id, g.naver_game_id, g.current_inning,
               ht.name, at.name
        FROM games g
        JOIN teams ht ON g.home_team_id = ht.id
        JOIN teams at ON g.away_team_id = at.id
        WHERE g.status = '종료'
        AND g.game_date < '2026-05-09'
        AND g.naver_game_id IS NOT NULL
        ORDER BY g.game_date
    """)
    games = cur.fetchall()
    cur.close()
    conn.close()

    print(f'크롤링 대상: {len(games)}개 경기')

    options = Options()
    driver = webdriver.Chrome(options=options)

    for idx, (db_id, naver_id, max_inning, home_team, away_team) in enumerate(games):
        try:
            total = crawl_game(driver, db_id, naver_id, max_inning, home_team, away_team)
            print(f'[{idx+1}/{len(games)}] {naver_id} 완료 ({total}개)', flush=True)
            time.sleep(1)
        except Exception as e:
            print(f'오류 ({naver_id}): {e}', flush=True)
            try:
                driver.quit()
            except:
                pass
            driver = webdriver.Chrome(options=options)
            continue

    driver.quit()
    print('전체 완료!')


# crawl_all_games.py 맨 아래 if __name__ == '__main__': 부분을 이렇게 수정
if __name__ == '__main__':
    main()