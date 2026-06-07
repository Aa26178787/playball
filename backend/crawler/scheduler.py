import schedule
import time
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DB_POOL_MAX', '10')  # 스케줄러는 10개로 제한 (API 서버에 나머지 할당)

from crawler.naver_crawler import (
    get_season_schedule,
    get_games_by_date,
    get_game_record,
    get_team_rankings,
    save_games,
    save_game_record,
    save_team_rankings,
    save_teams,
    update_live_game_innings,
    update_live_game_players,
    save_game_roster,
    save_entry_roster,
    save_game_pitches,
)
from crawler.statiz_crawler import (
    get_hitter_stats,
    get_pitcher_stats,
    save_players_and_stats,
)
from database.connection import get_connection
from datetime import datetime, timezone
import json

_game_hr_cache: dict = {}       # {game_id: {player_id: hr_count}} — HR 중복 알림 방지
_fav_lineup_sent: set = set()   # (game_id, player_id) — 선발출전 알림 중복 방지
_lineup_announced: set = set()  # game_id — 선발투수 발표 알림 중복 방지
_pitcher_seen: dict = {}        # {game_id: set(player_id)} — 투수 교체 알림 추적
_notified_cache: set = set()    # (game_id, ntype, sub_id) — 알림 중복 방지 (재시작 후 DB로 hydrate)


def _already_notified(game_id, ntype: str, sub_id: str = '') -> bool:
    """DB(notification_log + user_notifications) + 메모리 조합 중복 체크.
    재시작 후에도 동일 game/type/sub_id 재발송 방지.
    game_id=None이면 0으로 정규화 (팀 기반 알림 등).
    """
    gid = int(game_id) if game_id is not None else 0
    key = (gid, ntype, sub_id)
    if key in _notified_cache:
        return True
    conn = get_connection()
    if not conn:
        return False
    try:
        cur = conn.cursor()
        # 1) notification_log: targets 없어도 마킹 가능, 모든 ntype 지원
        cur.execute(
            "SELECT 1 FROM notification_log WHERE game_id=%s AND type=%s AND sub_id=%s LIMIT 1",
            (gid, ntype, sub_id)
        )
        if cur.fetchone():
            _notified_cache.add(key)
            cur.close()
            return True
        # 2) user_notifications: 과거 데이터 호환 (sub_id 없는 ntype만)
        if not sub_id and gid > 0:
            cur.execute(
                "SELECT 1 FROM user_notifications WHERE game_id=%s AND type=%s LIMIT 1",
                (gid, ntype)
            )
            if cur.fetchone():
                _notified_cache.add(key)
                cur.close()
                return True
        cur.close()
    except Exception:
        pass
    finally:
        conn.close()
    return False


def _mark_notified(game_id, ntype: str, sub_id: str = ''):
    """메모리 + DB(notification_log) 양쪽 마킹. 재시작 안전."""
    gid = int(game_id) if game_id is not None else 0
    _notified_cache.add((gid, ntype, sub_id))
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO notification_log (game_id, type, sub_id) VALUES (%s, %s, %s) "
            "ON CONFLICT (game_id, type, sub_id) DO NOTHING",
            (gid, ntype, sub_id)
        )
        conn.commit()
        cur.close()
    except Exception as e:
        print(f"[FCM] notification_log 마킹 실패: {e}")
    finally:
        conn.close()


def _parse_ip(ip_val) -> float:
    """이닝수 파싱: "6.2" → 6.67 (6이닝 2아웃)"""
    try:
        parts = str(ip_val).strip().split('.')
        inn = int(parts[0]) if parts[0] else 0
        outs = int(parts[1]) if len(parts) > 1 and parts[1] else 0
        return inn + outs / 3
    except Exception:
        return 0.0

# ===== 동명이인 후처리 =====

def _parse_naver_ip(s) -> float:
    """Naver 'inn' 문자열을 float 이닝 변환. '2 ⅓' → 2.333"""
    s = str(s).replace('⅓', '.333').replace('⅔', '.667').strip()
    if not s:
        return 0.0
    try:
        if ' ' in s:
            parts = s.split()
            return float(parts[0]) + float(parts[1])
        return float(s)
    except Exception:
        return 0.0


def _reinsert_dupe_name_rows(game_id: int, naver_game_id: str):
    """동명이인 케이스에서 naver_crawler가 1개 row로 합친 데이터를 raw stats로
    각 pcode별 별도 INSERT. game_pitchers + game_batters 둘 다 처리."""
    import requests as _req
    HEADERS = {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://sports.naver.com/'}
    try:
        url = f"https://api-gw.sports.naver.com/schedule/games/{naver_game_id}/record"
        res = _req.get(url, headers=HEADERS, timeout=5)
        rd = res.json().get('result', {}).get('recordData', {})
    except Exception as e:
        print(f"[reinsert-dupe] Naver fetch 실패 game={game_id}: {e}")
        return

    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()

        # 동명이인 name 식별
        cur.execute("""
            SELECT name FROM players
            WHERE name IS NOT NULL
            GROUP BY name HAVING COUNT(*) > 1
        """)
        dupe_names = {r[0] for r in cur.fetchall()}
        if not dupe_names:
            return

        # pcode → player_id 매핑
        cur.execute("""
            SELECT name, naver_player_id, id FROM players
            WHERE name = ANY(%s) AND naver_player_id IS NOT NULL
        """, (list(dupe_names),))
        pcode_to_id = {(r[0], r[1]): r[2] for r in cur.fetchall()}

        def _process_pitchers(side):
            rows = rd.get('pitchersBoxscore', {}).get(side, [])
            # name별 그룹화
            name_groups = {}
            for i, p in enumerate(rows, 1):
                name = p.get('name', '')
                if name in dupe_names:
                    name_groups.setdefault(name, []).append((i, p))
            for name, items in name_groups.items():
                if len(items) < 2:
                    continue  # 동명이인 raw 단일 → 단순 dupe-fix가 처리
                # DB 현재 row count
                cur.execute("""
                    SELECT COUNT(*) FROM game_pitchers gp
                    JOIN players p ON p.id = gp.player_id
                    WHERE gp.game_id = %s AND gp.team_side = %s AND p.name = %s
                """, (game_id, side, name))
                db_count = cur.fetchone()[0]
                if db_count >= len(items):
                    continue  # 이미 모두 등록
                # 부족 → 해당 name DB row 모두 DELETE 후 raw INSERT
                cur.execute("""
                    DELETE FROM game_pitchers
                    WHERE game_id = %s AND team_side = %s AND player_id IN (
                        SELECT id FROM players WHERE name = %s
                    )
                """, (game_id, side, name))
                for order, p in items:
                    pcode = str(p.get('pcode') or '')
                    pid = pcode_to_id.get((name, pcode))
                    if not pid:
                        continue
                    cur.execute("""
                        INSERT INTO game_pitchers (
                            game_id, player_id, team_side, result,
                            innings_pitched, hits_allowed, earned_runs, runs_allowed,
                            walks, strikeouts, home_runs_allowed, pitch_count, pitching_order
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                        ON CONFLICT (game_id, player_id, team_side) DO UPDATE SET
                            innings_pitched = EXCLUDED.innings_pitched,
                            pitching_order = EXCLUDED.pitching_order
                    """, (game_id, pid, side, p.get('wls', ''),
                          _parse_naver_ip(p.get('inn', 0)),
                          p.get('hit', 0), p.get('er', 0), p.get('r', 0),
                          p.get('bb', 0), p.get('kk', 0), p.get('hr', 0),
                          p.get('bf', 0), order))
                    print(f"[reinsert-dupe] game_pitchers {name} pcode={pcode} pid={pid} order={order} (game={game_id})")

        def _process_batters(side):
            rows = rd.get('battersBoxscore', {}).get(side, [])
            name_groups = {}
            for p in rows:
                name = p.get('name', '')
                if name in dupe_names:
                    name_groups.setdefault(name, []).append(p)
            for name, items in name_groups.items():
                if len(items) < 2:
                    continue
                cur.execute("""
                    SELECT COUNT(*) FROM game_batters gb
                    JOIN players p ON p.id = gb.player_id
                    WHERE gb.game_id = %s AND gb.team_side = %s AND p.name = %s
                """, (game_id, side, name))
                db_count = cur.fetchone()[0]
                if db_count >= len(items):
                    continue
                cur.execute("""
                    DELETE FROM game_batters
                    WHERE game_id = %s AND team_side = %s AND player_id IN (
                        SELECT id FROM players WHERE name = %s
                    )
                """, (game_id, side, name))
                for p in items:
                    pcode = str(p.get('playerCode') or '')
                    pid = pcode_to_id.get((name, pcode))
                    if not pid:
                        continue
                    bat_order = int(p.get('batOrder') or 0)
                    cur.execute("""
                        INSERT INTO game_batters (
                            game_id, player_id, team_side, batting_order, position,
                            at_bats, runs, hits, rbis, home_runs, walks, strikeouts,
                            stolen_bases, avg
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                        ON CONFLICT (game_id, player_id, team_side, batting_order) DO UPDATE SET
                            position = EXCLUDED.position,
                            at_bats = EXCLUDED.at_bats
                    """, (game_id, pid, side, bat_order, p.get('pos', ''),
                          p.get('ab', 0), p.get('run', 0), p.get('hit', 0),
                          p.get('rbi', 0), p.get('hr', 0), p.get('bb', 0),
                          p.get('kk', 0), p.get('sb', 0),
                          float(p.get('hra') or 0)))
                    print(f"[reinsert-dupe] game_batters {name} pcode={pcode} pid={pid} order={bat_order} (game={game_id})")

        for side in ('home', 'away'):
            _process_pitchers(side)
            _process_batters(side)

        conn.commit()
        cur.close()
    except Exception as e:
        print(f"[reinsert-dupe] 오류 game={game_id}: {e}")
    finally:
        conn.close()


def _fix_dupe_name_player_ids(game_id: int, naver_game_id: str):
    """Naver record API pcode 기준으로 game_pitchers/game_batters의
    동명이인 player_id 매칭 정정. naver_crawler는 name+team_id+type LIMIT 1로
    매칭하기 때문에 동명이인 데이터 손실 발생."""
    import requests as _req
    HEADERS = {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://sports.naver.com/'}
    try:
        url = f"https://api-gw.sports.naver.com/schedule/games/{naver_game_id}/record"
        res = _req.get(url, headers=HEADERS, timeout=5)
        rd = res.json().get('result', {}).get('recordData', {})
    except Exception as e:
        print(f"[dupe-fix] Naver record fetch 실패 game={game_id}: {e}")
        return

    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()

        # 동명이인 캐시: name → {pcode: player_id}
        # 동명이인이 있는 name만 매핑 (정상 매칭은 그대로 둠)
        cur.execute("""
            SELECT name FROM players
            WHERE name IS NOT NULL
            GROUP BY name HAVING COUNT(*) > 1
        """)
        dupe_names = {r[0] for r in cur.fetchall()}
        if not dupe_names:
            return

        cur.execute("""
            SELECT name, naver_player_id, id FROM players
            WHERE name = ANY(%s) AND naver_player_id IS NOT NULL
        """, (list(dupe_names),))
        pcode_to_id = {(r[0], r[1]): r[2] for r in cur.fetchall()}

        def _fix_table(naver_rows, key_pcode, db_table, side):
            """naver_rows: list of dict with name + pcode/playerCode.
            db_table: 'game_pitchers' or 'game_batters'.
            side: 'home' or 'away'."""
            for nr in naver_rows:
                name = nr.get('name', '')
                pcode = str(nr.get(key_pcode) or '')
                if not name or not pcode or name not in dupe_names:
                    continue
                correct_pid = pcode_to_id.get((name, pcode))
                if not correct_pid:
                    continue
                # 현재 DB에서 (game_id, team_side, name) 일치 row 확인
                cur.execute(f"""
                    SELECT gp.player_id FROM {db_table} gp
                    JOIN players p ON p.id = gp.player_id
                    WHERE gp.game_id = %s AND gp.team_side = %s AND p.name = %s
                """, (game_id, side, name))
                existing = [r[0] for r in cur.fetchall()]
                if correct_pid in existing:
                    continue  # 이미 정확
                # 잘못 매칭된 player_id 처리 — correct_pid row 유무에 따라 DELETE 또는 UPDATE
                wrong_ids = [pid for pid in existing if pid != correct_pid]
                for wid in wrong_ids:
                    # correct_pid row 이미 있으면 wrong row DELETE (이전 wrong matching 잔재)
                    cur.execute(f"""
                        SELECT 1 FROM {db_table}
                        WHERE game_id=%s AND team_side=%s AND player_id=%s
                    """, (game_id, side, correct_pid))
                    if cur.fetchone():
                        cur.execute(f"""
                            DELETE FROM {db_table}
                            WHERE game_id=%s AND team_side=%s AND player_id=%s
                        """, (game_id, side, wid))
                        print(f"[dupe-fix] {db_table} {name} DELETE wrong {wid} (correct {correct_pid} 있음, game={game_id})")
                    else:
                        cur.execute(f"""
                            UPDATE {db_table}
                            SET player_id = %s
                            WHERE game_id=%s AND team_side=%s AND player_id=%s
                        """, (correct_pid, game_id, side, wid))
                        print(f"[dupe-fix] {db_table} {name} UPDATE {wid}→{correct_pid} (game={game_id})")

        pitchers_box = rd.get('pitchersBoxscore', {})
        for side in ('home', 'away'):
            _fix_table(pitchers_box.get(side, []), 'pcode', 'game_pitchers', side)

        batters_box = rd.get('battersBoxscore', {})
        for side in ('home', 'away'):
            _fix_table(batters_box.get(side, []), 'playerCode', 'game_batters', side)

        conn.commit()
        cur.close()
    except Exception as e:
        print(f"[dupe-fix] DB 처리 오류 game={game_id}: {e}")
    finally:
        conn.close()


# ===== 헬스체크 =====
_HEALTH_FILE = os.path.join(os.path.dirname(__file__), '../health.json')
_ALERT_COOLDOWN = 3600  # 같은 오류 1시간 내 재알림 금지
_last_alert_time: float = 0.0


def _update_health(key: str):
    """크롤 성공 시 타임스탬프 갱신"""
    try:
        path = os.path.abspath(_HEALTH_FILE)
        data = {}
        if os.path.exists(path):
            with open(path, 'r') as f:
                data = json.load(f)
        data[key] = datetime.now(timezone.utc).isoformat()
        with open(path, 'w') as f:
            json.dump(data, f)
    except Exception:
        pass


def _send_alert(subject: str, body: str):
    """이메일 알림 (쿨다운 적용)"""
    global _last_alert_time
    now = datetime.now(timezone.utc).timestamp()
    if now - _last_alert_time < _ALERT_COOLDOWN:
        return
    try:
        import smtplib, os as _os
        from email.message import EmailMessage
        user = _os.environ.get('EMAIL_USER', '')
        pw   = _os.environ.get('EMAIL_PASS', '')
        admin = _os.environ.get('ADMIN_EMAIL', user)
        if not user or not pw:
            print(f'[HEALTH ALERT] {subject}: {body}')
            return
        msg = EmailMessage()
        msg['Subject'] = f'[PlayBall 알림] {subject}'
        msg['From'] = user
        msg['To'] = admin
        msg.set_content(body)
        with smtplib.SMTP_SSL('smtp.gmail.com', 465) as smtp:
            smtp.login(user, pw)
            smtp.send_message(msg)
        _last_alert_time = now
        print(f'[HEALTH] 알림 발송: {subject}')
    except Exception as e:
        print(f'[HEALTH] 알림 실패: {e}')


def _health_check():
    """15분마다 실행 — 경기 시간대에 크롤러 침묵 감지"""
    now_utc = datetime.now(timezone.utc)
    hour = now_utc.hour
    # KST 10:00~24:00 = UTC 01:00~15:00 (경기 시간대)
    if not (1 <= hour < 15):
        return
    try:
        path = os.path.abspath(_HEALTH_FILE)
        if not os.path.exists(path):
            _send_alert('크롤러 헬스파일 없음', '경기 시간대인데 health.json이 없습니다. 크롤러를 확인하세요.')
            return
        with open(path, 'r') as f:
            data = json.load(f)
        last_str = data.get('smart_update')
        if not last_str:
            _send_alert('smart_update 기록 없음', '경기 시간대인데 smart_update 성공 기록이 없습니다.')
            return
        last_dt = datetime.fromisoformat(last_str)
        elapsed = (now_utc - last_dt).total_seconds()
        if elapsed > 600:  # 10분 초과
            _send_alert(
                f'크롤러 {int(elapsed//60)}분 침묵',
                f'smart_update 마지막 성공: {last_str}\n경과: {int(elapsed//60)}분\n서버를 확인하세요.'
            )
    except Exception as e:
        print(f'[HEALTH] 헬스체크 오류: {e}')


def kill_zombie_chrome():
    """좀비 크롬 프로세스 정리"""
    import subprocess
    try:
        subprocess.run(['pkill', '-f', 'chrome'], capture_output=True)
    except Exception:
        pass


def _check_new_hrs(game_id: int, home_team_id: int, away_team_id: int):
    """HR 증가 감지 → 즐겨찾기 선수 팬에게 알림"""
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT gb.player_id, gb.home_runs, p.name, t.name
            FROM game_batters gb
            JOIN players p ON p.id = gb.player_id
            JOIN teams t ON t.id = p.team_id
            WHERE gb.game_id = %s AND gb.home_runs > 0
        """, (game_id,))
        rows = cur.fetchall()
        cur.close()
    except Exception:
        return
    finally:
        conn.close()

    # DB 기반 dedup: sub_id = "{player_id}_{hr_n}"
    # 재시작 후 첫 사이클: 기존 HR DB에 마킹 (알림 안 함)
    prev_hrs = _game_hr_cache.get(game_id)
    curr_hrs = {pid: hr for pid, hr, _, _ in rows}
    _game_hr_cache[game_id] = curr_hrs

    if prev_hrs is None:
        # 첫 실행/재시작 직후: 기존 HR 마킹만 (DB에 기록 안 된 것들)
        for player_id, hr_count, _, _ in rows:
            for hr_n in range(1, hr_count + 1):
                _mark_notified(game_id, 'fav_hr', f"{player_id}_{hr_n}")
        return

    try:
        # fav_hr 알림 비활성화 — score_change 알림(notify_score_change)에 타자/타구/타점/홈런 이미 포함됨
        # 중복 알림 방지. HR 카운트는 _game_hr_cache 갱신만 (마일스톤 체크용)
        for player_id, hr_count, *_ in rows:
            prev_hr = prev_hrs.get(player_id, 0)
            for hr_n in range(prev_hr + 1, hr_count + 1):
                _mark_notified(game_id, 'fav_hr', f"{player_id}_{hr_n}")
    except Exception as e:
        print(f"[FCM] HR 알림 오류: {e}")


def _check_game_milestones(game_id: int):
    """득점 변화 시: game_batters/game_pitchers + 이번달 daily_stats 합산 → 마일스톤 체크"""
    from datetime import date as dt_date
    today = dt_date.today()
    season = today.year
    month = today.month
    month_start = today.replace(day=1).isoformat()

    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()

        # ── 타자: game_batters + 이번달 pre-game daily_stats ──
        cur.execute("""
            SELECT gb.player_id, p.name, t.name as team_name,
                   gb.hits as g_hits, gb.home_runs as g_hr, gb.rbis as g_rbi,
                   gb.stolen_bases as g_sb,
                   COALESCE(SUM(CASE WHEN ds.stat_type='hitter' THEN ds.hits   END),0) as m_hits,
                   COALESCE(SUM(CASE WHEN ds.stat_type='hitter' THEN ds.home_runs END),0) as m_hr,
                   COALESCE(SUM(CASE WHEN ds.stat_type='hitter' THEN ds.rbi    END),0) as m_rbi,
                   COALESCE(SUM(CASE WHEN ds.stat_type='hitter' THEN ds.sb     END),0) as m_sb
            FROM game_batters gb
            JOIN players p ON p.id = gb.player_id
            JOIN teams t ON t.id = p.team_id
            LEFT JOIN player_daily_stats ds
                ON ds.player_id = gb.player_id
               AND ds.game_date >= %s
               AND ds.game_date < CURRENT_DATE
               AND ds.stat_type = 'hitter'
            WHERE gb.game_id = %s
            GROUP BY gb.player_id, p.name, t.name, gb.hits, gb.home_runs, gb.rbis, gb.stolen_bases
        """, (month_start, game_id))
        batters = cur.fetchall()

        # ── 투수: game_pitchers + 이번달 pre-game daily_stats ──
        cur.execute("""
            SELECT gp.player_id, p.name, t.name as team_name,
                   gp.strikeouts as g_so,
                   COALESCE(SUM(CASE WHEN ds.stat_type='pitcher' THEN ds.so END),0) as m_so,
                   COALESCE(SUM(CASE WHEN ds.stat_type='pitcher' THEN ds.h  END),0) as m_h
            FROM game_pitchers gp
            JOIN players p ON p.id = gp.player_id
            JOIN teams t ON t.id = p.team_id
            LEFT JOIN player_daily_stats ds
                ON ds.player_id = gp.player_id
               AND ds.game_date >= %s
               AND ds.game_date < CURRENT_DATE
               AND ds.stat_type = 'pitcher'
            WHERE gp.game_id = %s
            GROUP BY gp.player_id, p.name, t.name, gp.strikeouts
        """, (month_start, game_id))
        pitchers = cur.fetchall()
        cur.close()
    except Exception as e:
        print(f"[마일스톤] 쿼리 오류: {e}")
        return
    finally:
        conn.close()

    try:
        from api.fcm_service import notify_milestone

        # ── 타자 월간 마일스톤 ──
        BATTER_MONTHLY = {
            'monthly_hits': [20, 25, 30, 35, 40],
            'monthly_hr':   [5, 7, 10, 12, 15],
            'monthly_rbi':  [10, 15, 20, 25, 30],
            'monthly_sb':   [5, 8, 10, 15],
        }
        # ── 단일경기 최다 ──
        BATTER_GAME = {
            'game_hits': [4, 5, 6],
            'game_hr':   [3, 4],
            'game_rbi':  [5, 6, 7, 8],
            'game_sb':   [3, 4],
        }

        batter_ids = []
        batter_monthly_totals = {}  # pid → {stat: val}

        for row in batters:
            pid, pname, tname = row[0], row[1], row[2]
            g_hits, g_hr, g_rbi, g_sb = row[3] or 0, row[4] or 0, row[5] or 0, row[6] or 0
            m_hits, m_hr, m_rbi, m_sb = row[7], row[8], row[9], row[10]
            totals = {
                'monthly_hits': m_hits + g_hits,
                'monthly_hr':   m_hr + g_hr,
                'monthly_rbi':  m_rbi + g_rbi,
                'monthly_sb':   m_sb + g_sb,
            }
            batter_monthly_totals[pid] = (pname, tname, g_hits, g_hr, g_rbi, g_sb, totals)
            batter_ids.append(pid)

            for mtype, thresholds in BATTER_MONTHLY.items():
                for t in thresholds:
                    if totals[mtype] >= t:
                        notify_milestone(pid, pname, tname, mtype, t, season, month, game_id)

            game_vals = {'game_hits': g_hits, 'game_hr': g_hr, 'game_rbi': g_rbi, 'game_sb': g_sb}
            for mtype, thresholds in BATTER_GAME.items():
                for t in thresholds:
                    if game_vals[mtype] >= t:
                        notify_milestone(pid, pname, tname, mtype, t, season, month, game_id)

        # ── 투수 월간 마일스톤 + 단일경기 탈삼진 ──
        pitcher_monthly_so = {}  # pid → (pname, tname, total_so)
        PITCHER_MONTHLY_SO = [30, 40, 50, 60]
        PITCHER_GAME_SO = [10, 12, 14]

        for row in pitchers:
            pid, pname, tname = row[0], row[1], row[2]
            g_so = row[3] or 0
            total_so = g_so + row[4]
            pitcher_monthly_so[pid] = (pname, tname, g_so)
            for t in PITCHER_MONTHLY_SO:
                if total_so >= t:
                    notify_milestone(pid, pname, tname, 'monthly_so', t, season, month, game_id)
            for t in PITCHER_GAME_SO:
                if g_so >= t:
                    notify_milestone(pid, pname, tname, 'game_so', t, season, month, game_id)

        # ── 개인 월간 최다 경신 (역대 월간 최고치 대비) ──
        if batter_ids:
            conn2 = get_connection()
            if conn2:
                try:
                    cur2 = conn2.cursor()
                    cur2.execute("""
                        SELECT player_id,
                               MAX(mh) as best_hits, MAX(mhr) as best_hr,
                               MAX(mrbi) as best_rbi, MAX(msb) as best_sb
                        FROM (
                            SELECT player_id,
                                   SUM(hits) as mh, SUM(home_runs) as mhr,
                                   SUM(rbi) as mrbi, SUM(sb) as msb
                            FROM player_daily_stats
                            WHERE stat_type = 'hitter'
                              AND player_id = ANY(%s)
                              AND game_date < date_trunc('month', CURRENT_DATE)
                              AND game_date >= '2015-01-01'
                            GROUP BY player_id, date_trunc('month', game_date)
                        ) sub
                        GROUP BY player_id
                    """, (batter_ids,))
                    personal_bests = {r[0]: (r[1] or 0, r[2] or 0, r[3] or 0, r[4] or 0)
                                      for r in cur2.fetchall()}
                    cur2.close()
                    conn2.close()

                    for pid, (pname, tname, _gh, _ghr, _grbi, _gsb, totals) in batter_monthly_totals.items():
                        pb = personal_bests.get(pid, (0, 0, 0, 0))
                        checks = [
                            ('personal_monthly_hits', totals['monthly_hits'], pb[0]),
                            ('personal_monthly_hr',   totals['monthly_hr'],   pb[1]),
                            ('personal_monthly_rbi',  totals['monthly_rbi'],  pb[2]),
                            ('personal_monthly_sb',   totals['monthly_sb'],   pb[3]),
                        ]
                        for mtype, curr_val, prev_best in checks:
                            if curr_val > 0 and curr_val > prev_best:
                                notify_milestone(pid, pname, tname, mtype, curr_val, season, month, game_id)
                except Exception as pb_err:
                    print(f"[마일스톤] 개인 최다 쿼리 오류: {pb_err}")
                    try: conn2.close()
                    except: pass

        # ── 연속 안타 스트릭 (10/15/20/25/30경기) ──
        if batter_ids:
            conn3 = get_connection()
            if conn3:
                try:
                    cur3 = conn3.cursor()
                    cur3.execute("""
                        WITH ordered AS (
                            SELECT player_id, hits,
                                   ROW_NUMBER() OVER (PARTITION BY player_id ORDER BY game_date DESC) as rn
                            FROM player_daily_stats
                            WHERE stat_type = 'hitter'
                              AND player_id = ANY(%s)
                        ),
                        recent AS (SELECT * FROM ordered WHERE rn <= 40),
                        with_break AS (
                            SELECT player_id,
                                   MIN(CASE WHEN hits = 0 THEN rn ELSE NULL END) as first_break
                            FROM recent GROUP BY player_id
                        )
                        SELECT o.player_id, COUNT(*) as streak
                        FROM recent o
                        JOIN with_break wb ON wb.player_id = o.player_id
                        WHERE o.hits > 0
                          AND (wb.first_break IS NULL OR o.rn < wb.first_break)
                        GROUP BY o.player_id
                        HAVING COUNT(*) >= 9
                    """, (batter_ids,))
                    streak_rows = cur3.fetchall()
                    cur3.close()
                    conn3.close()

                    STREAK_THRESHOLDS = [10, 15, 20, 25, 30]
                    for pid, streak_prev in streak_rows:
                        info = batter_monthly_totals.get(pid)
                        if not info:
                            continue
                        pname, tname = info[0], info[1]
                        g_hits = info[2]
                        actual_streak = streak_prev + (1 if g_hits > 0 else 0)
                        for t in STREAK_THRESHOLDS:
                            if actual_streak >= t:
                                notify_milestone(pid, pname, tname, 'hitting_streak', t,
                                                 season, month, game_id)
                except Exception as streak_err:
                    print(f"[마일스톤] 연속 안타 쿼리 오류: {streak_err}")
                    try: conn3.close()
                    except: pass

    except Exception as e:
        print(f"[FCM] 마일스톤 알림 오류: {e}")


def _check_post_game_milestones(game_id: int):
    """경기 종료 후: batter_stats/pitcher_stats 시즌 누계 마일스톤 체크"""
    from datetime import date as dt_date
    today = dt_date.today()
    season = today.year
    month = 0  # 시즌 통산은 month=0

    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()

        # 해당 경기 팀 소속 타자 (볼넷/득점 포함) + 오늘 경기 기여분 (임계값 '통과' 판정용)
        cur.execute("""
            SELECT bs.player_id, p.name, t.name,
                   bs.home_runs, bs.rbis, bs.hits, bs.stolen_bases,
                   COALESCE(bs.walks, 0), COALESCE(bs.runs, 0),
                   COALESCE(gb.home_runs, 0), COALESCE(gb.rbis, 0), COALESCE(gb.hits, 0),
                   COALESCE(gb.stolen_bases, 0), COALESCE(gb.walks, 0), COALESCE(gb.runs, 0)
            FROM game_batters gb
            JOIN batter_stats bs ON bs.player_id = gb.player_id AND bs.season = %s
            JOIN players p ON p.id = gb.player_id
            JOIN teams t ON t.id = p.team_id
            WHERE gb.game_id = %s
        """, (season, game_id))
        batters = cur.fetchall()

        # 해당 경기 투수 + 오늘 결과/탈삼진 (임계값 '통과' 판정용)
        cur.execute("""
            SELECT ps.player_id, p.name, t.name,
                   ps.wins, ps.strikeouts, ps.saves, ps.holds,
                   gp.result, COALESCE(gp.strikeouts, 0)
            FROM game_pitchers gp
            JOIN pitcher_stats ps ON ps.player_id = gp.player_id AND ps.season = %s
            JOIN players p ON p.id = gp.player_id
            JOIN teams t ON t.id = p.team_id
            WHERE gp.game_id = %s
        """, (season, game_id))
        pitchers = cur.fetchall()

        # 완봉/완봉승/노히터 체크용 선발투수
        cur.execute("""
            SELECT gp.player_id, p.name, t.name,
                   gp.innings_pitched, gp.earned_runs, gp.hits_allowed, gp.team_side
            FROM game_pitchers gp
            JOIN players p ON p.id = gp.player_id
            JOIN teams t ON t.id = p.team_id
            WHERE gp.game_id = %s AND gp.pitching_order = 1
        """, (game_id,))
        starters_cg = cur.fetchall()
        cur.close()
    except Exception as e:
        print(f"[마일스톤] 시즌 쿼리 오류: {e}")
        return
    finally:
        conn.close()

    try:
        from api.fcm_service import notify_milestone
        from datetime import date as _dt

        # ── 나이 조회 (최연소 체크용) ──
        all_pids = [r[0] for r in batters] + [r[0] for r in pitchers]
        birth_map = {}
        if all_pids:
            conn_b = get_connection()
            if conn_b:
                try:
                    cur_b = conn_b.cursor()
                    cur_b.execute(
                        "SELECT id, birth_date FROM players WHERE id = ANY(%s) AND birth_date IS NOT NULL",
                        (all_pids,))
                    for pid_b, bd in cur_b.fetchall():
                        birth_map[pid_b] = bd
                    cur_b.close()
                finally:
                    conn_b.close()

        today = _dt.today()

        def _age(pid):
            bd = birth_map.get(pid)
            if not bd:
                return None
            return (today - bd).days // 365

        # ── 완봉/완봉승/노히터/QS ──
        for row in starters_cg:
            pid, pname, tname = row[0], row[1], row[2]
            ip_str, er, ha = row[3], row[4] or 0, row[5] or 0
            ip_val = _parse_ip(ip_str)
            if ip_val >= 9.0:
                notify_milestone(pid, pname, tname, 'game_cg', 1, season, month, game_id)
                if er == 0:
                    notify_milestone(pid, pname, tname, 'game_shutout', 1, season, month, game_id)
                if ha == 0:
                    notify_milestone(pid, pname, tname, 'game_no_hitter', 1, season, month, game_id)
            elif ip_val >= 6.0 and er <= 3:
                notify_milestone(pid, pname, tname, 'game_qs', 1, season, month, game_id)

        # ── 타자 시즌 마일스톤 ──
        BATTER_SEASON = {
            'season_hr':   [10, 15, 20, 25, 30, 35, 40],
            'season_rbi':  [50, 60, 70, 80, 90, 100, 110],
            'season_hits': [50, 100, 150, 200],
            'season_sb':   [10, 20, 30, 40],
            'season_bb':   [50, 80, 100],
            'season_runs': [50, 80, 100],
        }
        YOUNG_BATTER_SEASON = {  # 25세 이하 특이 기록
            'season_hr':   20,
            'season_rbi':  70,
            'season_hits': 100,
        }
        today_batter = {}  # 통산 블록 재사용
        for row in batters:
            pid, pname, tname = row[0], row[1], row[2]
            vals = {'season_hr': row[3] or 0, 'season_rbi': row[4] or 0,
                    'season_hits': row[5] or 0, 'season_sb': row[6] or 0,
                    'season_bb': row[7] or 0, 'season_runs': row[8] or 0}
            tg = {'season_hr': row[9], 'season_rbi': row[10], 'season_hits': row[11],
                  'season_sb': row[12], 'season_bb': row[13], 'season_runs': row[14]}
            today_batter[pid] = tg
            for mtype, thresholds in BATTER_SEASON.items():
                prev = vals[mtype] - tg[mtype]
                for t in thresholds:
                    # 이번 경기로 임계값을 '통과'한 경우만 (stale 일괄 발송 방지 — 류현진 5승 오보 fix)
                    if prev < t <= vals[mtype]:
                        notify_milestone(pid, pname, tname, mtype, t, season, month, game_id)
            # 최연소 체크 — 동일 통과 조건 (매 경기 재발송 방지)
            age = _age(pid)
            if age and age <= 25:
                for mtype, min_val in YOUNG_BATTER_SEASON.items():
                    prev = vals[mtype] - tg[mtype]
                    if prev < min_val <= vals[mtype]:
                        ytype = mtype.replace('season_', 'young_season_')
                        notify_milestone(pid, pname, tname, ytype, vals[mtype],
                                         season, month, game_id, extra_label=f"{age}세")

        # ── 투수 시즌 마일스톤 ──
        PITCHER_SEASON = {
            'season_wins':  [5, 10, 15, 20],
            'season_so':    [50, 100, 150, 200],
            'season_saves': [10, 20, 30, 40],
            'season_holds': [10, 20, 30],
        }
        YOUNG_PITCHER_SEASON = {  # 25세 이하 특이 기록
            'season_wins': 10,
            'season_so': 100,
        }
        today_pitcher = {}  # 통산 블록 재사용
        for row in pitchers:
            pid, pname, tname = row[0], row[1], row[2]
            vals = {'season_wins': row[3] or 0, 'season_so': row[4] or 0,
                    'season_saves': row[5] or 0, 'season_holds': row[6] or 0}
            result = (row[7] or '').strip()
            tg = {'season_wins': 1 if result == '승' else 0,
                  'season_so': row[8] or 0,
                  'season_saves': 1 if result == '세이브' else 0,
                  'season_holds': 1 if result == '홀드' else 0}
            today_pitcher[pid] = tg
            for mtype, thresholds in PITCHER_SEASON.items():
                prev = vals[mtype] - tg[mtype]
                for t in thresholds:
                    # 이번 경기로 임계값을 '통과'한 경우만
                    if prev < t <= vals[mtype]:
                        notify_milestone(pid, pname, tname, mtype, t, season, month, game_id)
            age = _age(pid)
            if age and age <= 25:
                for mtype, min_val in YOUNG_PITCHER_SEASON.items():
                    prev = vals[mtype] - tg[mtype]
                    if prev < min_val <= vals[mtype]:
                        ytype = mtype.replace('season_', 'young_season_')
                        notify_milestone(pid, pname, tname, ytype, vals[mtype],
                                         season, month, game_id, extra_label=f"{age}세")

        # ── 통산 타자 마일스톤 ──
        conn2 = get_connection()
        if conn2:
            try:
                cur2 = conn2.cursor()
                cur2.execute("""
                    SELECT bs.player_id, p.name, t.name,
                           SUM(COALESCE(bs.hits, 0)),
                           SUM(COALESCE(bs.home_runs, 0)),
                           SUM(COALESCE(bs.rbis, 0)),
                           SUM(COALESCE(bs.stolen_bases, 0)),
                           SUM(COALESCE(bs.walks, 0))
                    FROM game_batters gb
                    JOIN batter_stats bs ON bs.player_id = gb.player_id
                    JOIN players p ON p.id = gb.player_id
                    JOIN teams t ON t.id = p.team_id
                    WHERE gb.game_id = %s
                    GROUP BY bs.player_id, p.name, t.name
                """, (game_id,))
                career_batters = cur2.fetchall()

                CAREER_BATTER = {
                    'career_hits':  [500, 1000, 1500, 2000, 2500],
                    'career_hr':    [100, 200, 300, 400, 500],
                    'career_rbi':   [500, 1000, 1500],
                    'career_sb':    [100, 200, 300],
                    'career_bb':    [500, 1000],
                }
                _CB_KEY = {'career_hits': 'season_hits', 'career_hr': 'season_hr',
                           'career_rbi': 'season_rbi', 'career_sb': 'season_sb', 'career_bb': 'season_bb'}
                for row in career_batters:
                    pid, pname, tname = row[0], row[1], row[2]
                    cvals = {'career_hits': row[3], 'career_hr': row[4],
                             'career_rbi': row[5], 'career_sb': row[6], 'career_bb': row[7]}
                    tg = today_batter.get(pid, {})
                    for mtype, thresholds in CAREER_BATTER.items():
                        prev = cvals[mtype] - tg.get(_CB_KEY[mtype], 0)
                        for t in thresholds:
                            # 이번 경기로 통과한 임계값만 (stale 일괄 발송 방지)
                            if prev < t <= cvals[mtype]:
                                notify_milestone(pid, pname, tname, mtype, t, season, 0, game_id)
                    # 25세 이하 통산 100홈런/1000안타 — 동일 통과 조건
                    age = _age(pid)
                    if age and age <= 25:
                        if cvals['career_hr'] - tg.get('season_hr', 0) < 100 <= cvals['career_hr']:
                            notify_milestone(pid, pname, tname, 'young_career_hr', 100,
                                             season, 0, game_id, extra_label=f"{age}세")
                        if cvals['career_hits'] - tg.get('season_hits', 0) < 1000 <= cvals['career_hits']:
                            notify_milestone(pid, pname, tname, 'young_career_hits', 1000,
                                             season, 0, game_id, extra_label=f"{age}세")

                # ── 통산 투수 마일스톤 ──
                cur2.execute("""
                    SELECT ps.player_id, p.name, t.name,
                           SUM(COALESCE(ps.wins, 0)),
                           SUM(COALESCE(ps.strikeouts, 0)),
                           SUM(COALESCE(ps.saves, 0)),
                           SUM(COALESCE(ps.holds, 0))
                    FROM game_pitchers gp
                    JOIN pitcher_stats ps ON ps.player_id = gp.player_id
                    JOIN players p ON p.id = gp.player_id
                    JOIN teams t ON t.id = p.team_id
                    WHERE gp.game_id = %s
                    GROUP BY ps.player_id, p.name, t.name
                """, (game_id,))
                career_pitchers = cur2.fetchall()

                CAREER_PITCHER = {
                    'career_wins':  [50, 100, 150, 200],
                    'career_so':    [500, 1000, 1500, 2000, 2500],
                    'career_saves': [100, 200, 300],
                    'career_holds': [100, 200],
                }
                _CP_KEY = {'career_wins': 'season_wins', 'career_so': 'season_so',
                           'career_saves': 'season_saves', 'career_holds': 'season_holds'}
                for row in career_pitchers:
                    pid, pname, tname = row[0], row[1], row[2]
                    cvals = {'career_wins': row[3], 'career_so': row[4],
                             'career_saves': row[5], 'career_holds': row[6]}
                    tg = today_pitcher.get(pid, {})
                    for mtype, thresholds in CAREER_PITCHER.items():
                        prev = cvals[mtype] - tg.get(_CP_KEY[mtype], 0)
                        for t in thresholds:
                            # 이번 경기로 통과한 임계값만
                            if prev < t <= cvals[mtype]:
                                notify_milestone(pid, pname, tname, mtype, t, season, 0, game_id)

                cur2.close()
            except Exception as career_err:
                print(f"[마일스톤] 통산 쿼리 오류: {career_err}")
            finally:
                conn2.close()

    except Exception as e:
        print(f"[FCM] 시즌 마일스톤 알림 오류: {e}")


def _is_walkoff(game_id: int) -> bool:
    """끝내기 판정: 마지막 이닝에 홈팀 득점이 있으면 True"""
    conn = get_connection()
    if not conn:
        return False
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT home_runs FROM game_innings
            WHERE game_id = %s
            ORDER BY inning DESC LIMIT 1
        """, (game_id,))
        row = cur.fetchone()
        cur.close()
        return row is not None and (row[0] or 0) > 0
    except Exception:
        return False
    finally:
        conn.close()


def _check_pitcher_change(game_id: int, game_info: dict):
    """진행 중 새 투수 등판 감지 → 투수 교체 알림. 선발(pitching_order=1)은 라인업 발표 알림에서 처리."""
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT gp.player_id, p.name, gp.innings_pitched, gp.team_side,
                   gp.pitching_order,
                   LAG(p.name) OVER (PARTITION BY gp.game_id, gp.team_side ORDER BY gp.pitching_order) AS prev_name
            FROM game_pitchers gp
            JOIN players p ON p.id = gp.player_id
            WHERE gp.game_id = %s
            ORDER BY gp.team_side, gp.pitching_order
        """, (game_id,))
        rows = cur.fetchall()
        cur.close()
    except Exception:
        return
    finally:
        conn.close()

    if not rows:
        return

    # DB 기반 dedup + 재시작 안전 prime
    seen = _pitcher_seen.setdefault(game_id, set())

    # 메모리 hydrate from DB (재시작 직후 DB-marked 투수 메모리 동기화)
    db_marked_count = 0
    for player_id, *_ in rows:
        if _already_notified(game_id, 'pitcher_change', str(player_id)):
            seen.add(player_id)
            db_marked_count += 1

    # 진짜 첫 호출 (DB+메모리 모두 비어있음): 모든 현재 투수 prime + 알림 없이 종료
    # 재시작 시 25개 투수 일괄 알림 방지
    if db_marked_count == 0 and not seen:
        for player_id, *_ in rows:
            seen.add(player_id)
            _mark_notified(game_id, 'pitcher_change', str(player_id))
        return

    try:
        from api.fcm_service import notify_pitcher_change
        for player_id, name, ip, side, order, prev_name in rows:
            if player_id in seen:
                continue
            seen.add(player_id)
            _mark_notified(game_id, 'pitcher_change', str(player_id))
            if order == 1:
                continue  # 선발은 라인업 발표 알림에서 처리
            team_name = game_info.get('home_team') if side == 'home' else game_info.get('away_team')
            notify_pitcher_change(game_id, game_info.get('home_team', ''), game_info.get('away_team', ''),
                                  name, team_name or '', prev_name or '',
                                  game_info.get('home_team_id', 0), game_info.get('away_team_id', 0))
            print(f"[FCM] 투수 교체 알림: {prev_name} → {name} ({team_name}, game_id={game_id})")
    except Exception as e:
        print(f"[FCM] 투수 교체 알림 오류: {e}")


def _send_game_summary(game_id: int):
    """경기 종료 결과 요약 알림 (호출 측에서 dedup, 여기선 즉시 발송)"""
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT g.home_team_id, g.away_team_id, g.home_score, g.away_score,
                   t1.name, t2.name
            FROM games g
            JOIN teams t1 ON t1.id = g.home_team_id
            JOIN teams t2 ON t2.id = g.away_team_id
            WHERE g.id = %s AND g.status = '종료'
        """, (game_id,))
        game = cur.fetchone()
        if not game:
            return
        home_team_id, away_team_id, home_score, away_score, home_team, away_team = game

        cur.execute("""
            SELECT p.name, gp.result, gp.innings_pitched, gp.earned_runs
            FROM game_pitchers gp
            JOIN players p ON p.id = gp.player_id
            WHERE gp.game_id = %s AND gp.result IN ('승', '패', '홀드', '세이브')
        """, (game_id,))
        pitcher_rows = cur.fetchall()
        win_pitcher = win_ip = ''; win_er = 0
        loss_pitcher = hold_pitcher = save_pitcher = ''
        for pname, result, ip, er in pitcher_rows:
            if result == '승':
                win_pitcher = pname; win_ip = str(ip) if ip else ''; win_er = er or 0
            elif result == '패':
                loss_pitcher = pname
            elif result == '홀드':
                hold_pitcher = pname
            elif result == '세이브':
                save_pitcher = pname

        winner_side = 'home' if home_score > away_score else 'away'
        cur.execute("""
            SELECT p.name, COALESCE(gb.hits,0), COALESCE(gb.home_runs,0), COALESCE(gb.rbis,0)
            FROM game_batters gb
            JOIN players p ON p.id = gb.player_id
            WHERE gb.game_id = %s AND gb.team_side = %s
              AND (gb.rbis > 0 OR gb.home_runs > 0)
            ORDER BY gb.rbis DESC, gb.home_runs DESC, gb.hits DESC
            LIMIT 1
        """, (game_id, winner_side))
        mvp_row = cur.fetchone()
        cur.close()
    except Exception as e:
        print(f"[FCM] 경기요약 쿼리 오류: {e}")
        return
    finally:
        conn.close()

    try:
        from api.fcm_service import notify_game_summary
        notify_game_summary(
            game_id, home_team, away_team, home_score, away_score,
            home_team_id, away_team_id,
            win_pitcher=win_pitcher, win_ip=win_ip, win_er=win_er,
            loss_pitcher=loss_pitcher,
            hold_pitcher=hold_pitcher, save_pitcher=save_pitcher,
            mvp_name=mvp_row[0] if mvp_row else '',
            mvp_hits=mvp_row[1] if mvp_row else 0,
            mvp_hr=mvp_row[2] if mvp_row else 0,
            mvp_rbi=mvp_row[3] if mvp_row else 0,
        )
    except Exception as e:
        print(f"[FCM] 경기요약 알림 오류: {e}")


def _notify_fav_player_lineup(game_id: int, home_team: str, away_team: str):
    """경기 시작 시 즐겨찾기 선수 선발 출전 알림"""
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT gb.player_id, p.name, t.name,
                   gb.batting_order, gb.position, gb.team_side
            FROM game_batters gb
            JOIN players p ON p.id = gb.player_id
            JOIN teams t ON t.id = p.team_id
            WHERE gb.game_id = %s AND gb.batting_order > 0
              AND gb.position IS NOT NULL AND gb.position != ''
        """, (game_id,))
        starters = cur.fetchall()
        cur.close()
    except Exception:
        return
    finally:
        conn.close()

    try:
        from api.fcm_service import notify_fav_player_lineup
        for player_id, pname, tname, batting_order, position, side in starters:
            sub_id = str(player_id)
            if (game_id, player_id) in _fav_lineup_sent:
                continue
            if _already_notified(game_id, 'fav_lineup', sub_id):
                _fav_lineup_sent.add((game_id, player_id))
                continue
            opponent = away_team if side == 'home' else home_team
            notify_fav_player_lineup(player_id, pname, tname, game_id,
                                     opponent, batting_order or 0, position or '')
            _fav_lineup_sent.add((game_id, player_id))
            _mark_notified(game_id, 'fav_lineup', sub_id)
    except Exception as e:
        print(f"[FCM] 선발출전 알림 오류: {e}")


def _fixup_starter_positions():
    """대타 starter + 실제 포지션 sub 케이스 보정.
    Naver lineup이 batting_order 9번을 '대타'로만 표기하고 실제 유격수/포수 등은 sub로 기록 → 필드뷰 포지션 누락.
    같은 batting_order의 실제 포지션 sub를 starter로 promote + 기존 대타 starter 강등."""
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        # 1. 실제 포지션 sub를 starter로 promote (batting_order별 1명만)
        cur.execute("""
            WITH targets AS (
              SELECT DISTINCT ON (gr.game_id, gr.team_side, gr.batting_order) gr.id
              FROM game_rosters gr
              JOIN game_rosters s ON s.game_id=gr.game_id
                AND s.team_side=gr.team_side
                AND s.batting_order=gr.batting_order
                AND s.is_starter=TRUE
                AND s.position IN ('대타', '대주자')
              WHERE gr.is_starter = FALSE
                AND gr.roster_type = 'batter'
                AND gr.position IS NOT NULL
                AND gr.position NOT IN ('대타', '대주자', '')
              ORDER BY gr.game_id, gr.team_side, gr.batting_order, gr.id
            )
            UPDATE game_rosters SET is_starter = TRUE WHERE id IN (SELECT id FROM targets)
        """)
        promoted = cur.rowcount
        # 2. 대타 starter 강등 (같은 batting_order에 다른 starter 있을 때만)
        cur.execute("""
            UPDATE game_rosters SET is_starter = FALSE
            WHERE roster_type = 'batter'
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
        """)
        demoted = cur.rowcount
        conn.commit()
        cur.close()
        if promoted or demoted:
            print(f"[fixup_starter] promoted={promoted} demoted={demoted}")
    except Exception as e:
        print(f"[fixup_starter] 오류: {e}")
    finally:
        conn.close()


def smart_update():
    """
    1분마다 실행
    UTC 01:00~15:00 (KST 10:00~00:00) 사이에만 동작
    """
    now_utc = datetime.now(timezone.utc)
    hour = now_utc.hour

    if not (1 <= hour < 15):
        return

    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    cur.execute("""
        SELECT COUNT(*) FROM games
        WHERE game_date = CURRENT_DATE
        AND status != '취소'
    """)
    today_games = cur.fetchone()[0]
    cur.close()
    conn.close()

    if today_games == 0:
        _update_health('smart_update')
        return

    prev_details = _get_game_details()
    _update_today_games()
    curr_details = _get_game_details()
    _update_health('smart_update')

    prev_statuses = {gid: d['status'] for gid, d in prev_details.items()}
    curr_statuses = {gid: d['status'] for gid, d in curr_details.items()}

    _update_live_games_realtime()
    _update_lineup_by_starttime()
    _update_lineup_fallback()
    _update_roster_changes_pregame()

    if prev_details and curr_details:
        newly_finished = [
            gid for gid, status in curr_statuses.items()
            if status == '종료' and prev_statuses.get(gid) == '진행'
        ]

        # FCM 알림
        try:
            from api.fcm_service import (
                notify_game_start, notify_score_change,
                notify_extra_innings, notify_game_cancelled, notify_streak,
            )
            for gid, curr in curr_details.items():
                prev = prev_details.get(gid, {})
                cs, ps = curr['status'], prev.get('status', '')

                # 우천취소 (state-based + dedup)
                if cs == '취소' and not _already_notified(gid, 'cancelled'):
                    notify_game_cancelled(gid, curr['home_team'], curr['away_team'],
                                          curr['home_team_id'], curr['away_team_id'])
                    _mark_notified(gid, 'cancelled')
                    continue

                # 라인업 발표 → 선발투수 발표 알림 (state-based + dedup)
                if cs == '라인업' and not _already_notified(gid, 'starter_announced'):
                    if gid not in _lineup_announced:
                        _lineup_announced.add(gid)
                        try:
                            _la_c = get_connection()
                            if _la_c:
                                _la_cur = _la_c.cursor()
                                _la_cur.execute("""
                                    SELECT p.name, gp.team_side FROM game_pitchers gp
                                    JOIN players p ON p.id = gp.player_id
                                    WHERE gp.game_id = %s AND gp.pitching_order = 1
                                """, (gid,))
                                _la_rows = _la_cur.fetchall()
                                _la_cur.close(); _la_c.close()
                                _la_hs = _la_ls = ''
                                for _n, _s in _la_rows:
                                    if _s == 'home': _la_hs = _n
                                    else: _la_ls = _n
                                if _la_hs or _la_ls:
                                    from api.fcm_service import notify_starter_announced
                                    notify_starter_announced(gid, curr['home_team'], curr['away_team'],
                                                             curr['home_team_id'], curr['away_team_id'],
                                                             _la_hs, _la_ls)
                                    _mark_notified(gid, 'starter_announced')
                                    # 라인업 발표 → 예측 캐시 무효화 (해당 game만) + 재로깅
                                    try:
                                        from api.cache import cache_delete_prefix
                                        from api.prediction.eval import log_prediction
                                        cache_delete_prefix(f'api.routers.prediction.get_game_win_prediction:({gid},)')
                                        log_prediction(gid)
                                    except Exception as _pe:
                                        print(f"[prediction] 라인업 재로깅 오류 game={gid}: {_pe}")
                        except Exception:
                            pass

                # 경기 시작 (재시작 안전: dedup)
                elif cs == '진행' and ps in ('예정', '라인업', '') and not _already_notified(gid, 'game_start'):
                    # 선발 투수 조회
                    _hs = _ls = ''
                    try:
                        _c2 = get_connection()
                        if _c2:
                            _cur2 = _c2.cursor()
                            _cur2.execute("""
                                SELECT p.name, gp.team_side FROM game_pitchers gp
                                JOIN players p ON p.id = gp.player_id
                                WHERE gp.game_id = %s AND gp.pitching_order = 1
                            """, (gid,))
                            for _name, _side in _cur2.fetchall():
                                if _side == 'home': _hs = _name
                                else: _ls = _name
                            _cur2.close()
                            _c2.close()
                    except Exception:
                        pass
                    notify_game_start(gid, curr['home_team'], curr['away_team'],
                                      curr['home_team_id'], curr['away_team_id'],
                                      start_time=curr.get('start_time', ''),
                                      home_starter=_hs, away_starter=_ls)
                    _mark_notified(gid, 'game_start')
                    # 즐겨찾기 선수 선발 출전 알림 — 비활성화
                    # (notify_starter_announced에 선발투수 + game_start에 라인업 정보 이미 포함)

                # 득점 변화 — DB 기반 dedup: 현재 스코어 sub_id 미알림 + delta>0이면 발송
                elif (cs == '진행'
                      and (curr['home_score'] or 0) + (curr['away_score'] or 0) > 0
                      and (curr['home_score'] != prev.get('home_score', 0)
                           or curr['away_score'] != prev.get('away_score', 0))
                      and not _already_notified(gid, 'score_change',
                                                 f"{curr['home_score'] or 0}_{curr['away_score'] or 0}")):
                    score_subid = f"{curr['home_score'] or 0}_{curr['away_score'] or 0}"
                    ph, pa = prev.get('home_score', 0) or 0, prev.get('away_score', 0) or 0
                    ch, ca = curr['home_score'] or 0, curr['away_score'] or 0
                    # 역전: 득점 전 앞서던 팀이 뒤처짐
                    is_comeback = ((ph > pa and ch < ca) or (pa > ph and ca < ch))
                    # 대역전: 3점 이상 차이 뒤집기
                    is_big_comeback = is_comeback and abs(ph - pa) >= 3
                    # 득점 팀 판별 + 득점 수
                    scoring_team = curr['home_team'] if ch > ph else curr['away_team'] if ca > pa else ''
                    runs_scored = (ch - ph) if ch > ph else (ca - pa) if ca > pa else 1
                    # 득점 상세 (타자/투수/타구/홈인)
                    naver_gid = curr.get('naver_game_id', '')
                    inning_now = curr.get('current_inning', 0)
                    batter = pitcher = play_text = stuff = ''
                    speed = 0
                    pitch_num = 0
                    homein = []
                    if naver_gid and inning_now:
                        try:
                            batter, pitcher, play_text, stuff, speed, homein, pitch_num = _get_scoring_play_detail(
                                naver_gid, inning_now, ch, ca)
                        except Exception:
                            pass
                    # pitcher 누락 시 DB game_pitchers fallback (현재 등판 중 pitcher)
                    if not pitcher:
                        try:
                            # 득점한 공격팀의 반대팀이 수비 (=현재 투수의 팀)
                            pitching_side = 'home' if scoring_team == curr['away_team'] else 'away'
                            _fc = get_connection()
                            if _fc:
                                _fcur = _fc.cursor()
                                _fcur.execute("""
                                    SELECT p.name FROM game_pitchers gp
                                    JOIN players p ON p.id = gp.player_id
                                    WHERE gp.game_id = %s AND gp.team_side = %s
                                    ORDER BY gp.pitching_order DESC NULLS LAST LIMIT 1
                                """, (gid, pitching_side))
                                _r = _fcur.fetchone()
                                if _r:
                                    pitcher = _r[0]
                                _fcur.close(); _fc.close()
                        except Exception:
                            pass
                    notify_score_change(gid, curr['home_team'], curr['away_team'],
                                        ch, ca,
                                        curr['home_team_id'], curr['away_team_id'],
                                        is_comeback=is_comeback,
                                        big_comeback=is_big_comeback,
                                        inning=inning_now,
                                        inning_half=curr.get('inning_half', ''),
                                        scoring_team=scoring_team,
                                        runs=runs_scored,
                                        batter=batter, pitcher=pitcher, play_text=play_text,
                                        stuff=stuff, speed=speed, homein=homein,
                                        pitch_num=pitch_num)
                    _mark_notified(gid, 'score_change', score_subid)
                    _check_new_hrs(gid, curr['home_team_id'], curr['away_team_id'])
                    _check_game_milestones(gid)

                # 경기 종료 — 즉시 game_end 대신 30분 후 _send_game_summary로 발송
                # (game_pitchers 승/패/홀드/세이브 + game_batters MVP 데이터 채워질 시간 확보)
                elif cs == '종료' and ps == '진행':
                    # 종료 시점 날씨 DB 저장
                    try:
                        from api.weather_service import get_weather
                        import json as _json
                        _sid = curr.get('stadium_id')
                        if _sid:
                            _wdata = get_weather(_sid)
                            if _wdata:
                                _wc = get_connection()
                                if _wc:
                                    _wcur = _wc.cursor()
                                    _wcur.execute(
                                        "UPDATE games SET weather = %s WHERE id = %s",
                                        (_json.dumps(_wdata), gid)
                                    )
                                    _wc.commit()
                                    _wcur.close(); _wc.close()
                    except Exception as _we:
                        print(f'[Weather] 종료 날씨 저장 실패 game={gid}: {_we}')

                # 연장전 돌입 (재시작 안전: 회차별 sub_id로 dedup → 10/11/12회 각각 알림)
                curr_inn = curr.get('current_inning', 0) or 0
                if cs == '진행' and curr_inn >= 10 and not _already_notified(gid, 'extra_innings', str(curr_inn)):
                    notify_extra_innings(gid, curr['home_team'], curr['away_team'],
                                         curr_inn,
                                         curr['home_team_id'], curr['away_team_id'])
                    _mark_notified(gid, 'extra_innings', str(curr_inn))

                # 진행 중 투수 교체 감지
                if cs == '진행':
                    try:
                        _check_pitcher_change(gid, curr)
                    except Exception:
                        pass

        except Exception as fcm_err:
            print(f"[FCM] 알림 처리 오류: {fcm_err}")

        # 종료 게임 즉시 처리 (newly_finished 의존 제거 — 재시작 안전, dedup)
        # 매 사이클 종료 게임 중 'post_finished_done' 미마킹 → 한 번씩 처리
        try:
            post_targets = [
                (gid, c) for gid, c in curr_details.items()
                if c.get('status') == '종료' and not _already_notified(gid, 'post_finished_done')
            ]
            if post_targets:
                print(f"[{datetime.now()}] 종료 후처리 대상 {len(post_targets)}개")
                update_team_rankings()
                finished_team_ids = set()
                for gid, curr in post_targets:
                    conn_tmp = get_connection()
                    if not conn_tmp:
                        continue
                    try:
                        cur_tmp = conn_tmp.cursor()
                        cur_tmp.execute(
                            "SELECT naver_game_id, current_inning, home_team_id, away_team_id FROM games WHERE id = %s", (gid,)
                        )
                        row_tmp = cur_tmp.fetchone()
                        cur_tmp.close()
                    finally:
                        conn_tmp.close()
                    if not (row_tmp and row_tmp[1]):
                        continue
                    naver_gid = row_tmp[0]
                    max_inn = int(row_tmp[1])
                    # 투구 데이터 — 직전 이닝도 재저장 (Naver textRelays 타석 일괄 발행 지연 →
                    # 이닝 전환 직후 마지막 타석 누락 방지, 429 손호영 6구 사례. ON CONFLICT UPDATE라 안전)
                    try:
                        save_game_pitches(gid, naver_gid, max_inn)
                        if max_inn > 1:
                            save_game_pitches(gid, naver_gid, max_inn - 1)
                    except Exception as sgp_err:
                        print(f"[{datetime.now()}] save_game_pitches 오류: {sgp_err}")
                    # 동명이인 자동 정정 (game_pitchers + game_batters)
                    # 1) 합쳐진 케이스: raw stats 재INSERT
                    try:
                        _reinsert_dupe_name_rows(gid, naver_gid)
                    except Exception as ri_err:
                        print(f"[reinsert-dupe] 오류 game={gid}: {ri_err}")
                    # 2) mis-match 케이스: player_id 정정
                    try:
                        _fix_dupe_name_player_ids(gid, naver_gid)
                    except Exception as df_err:
                        print(f"[dupe-fix] 오류 game={gid}: {df_err}")
                    # pitch_locations 저장 + 5/30분 retry
                    try:
                        from crawler.crawl_pitch_locations import save_pitch_locations_for_game
                        n = save_pitch_locations_for_game(gid, naver_gid, max_inn)
                        print(f"[{datetime.now()}] pitch_locations 저장: game_id={gid} {n}구")
                    except Exception as pl_err:
                        print(f"[{datetime.now()}] pitch_locations 오류: {pl_err}")
                    def _retry_pitch_loc(g=gid, ng=naver_gid, mi=max_inn):
                        try:
                            from crawler.crawl_pitch_locations import save_pitch_locations_for_game as _s
                            n = _s(g, ng, mi)
                            print(f"[{datetime.now()}] pitch_locations 재크롤: game_id={g} {n}구")
                        except Exception as e:
                            print(f"[{datetime.now()}] pitch_locations 재크롤 오류: {e}")
                    schedule.every(5).minutes.do(_run_once, _retry_pitch_loc)
                    schedule.every(30).minutes.do(_run_once, _retry_pitch_loc)
                    if row_tmp[2]: finished_team_ids.add(row_tmp[2])
                    if row_tmp[3]: finished_team_ids.add(row_tmp[3])
                    # KBO 시즌 스탯 25분 후 (selenium 무거움 — schedule만)
                    schedule.every(25).minutes.do(_run_once, _crawl_kbo_stats_for_game, gid)
                    # 마일스톤 체크 27분 후
                    schedule.every(27).minutes.do(_run_once, _check_post_game_milestones, gid)
                    # 하이라이트 즉시 + 1시간 후 retry (Naver 색인 지연 대응)
                    try:
                        from crawler.crawl_highlights import crawl_highlights_for_game
                        crawl_highlights_for_game(gid)
                    except Exception as hl_err:
                        print(f"[{datetime.now()}] 하이라이트 크롤링 오류: {hl_err}")
                    _mark_notified(gid, 'post_finished_done')
                # 뉴스: 종료된 팀들 일괄
                if finished_team_ids:
                    try:
                        from crawler.crawl_naver_news import crawl_news_for_teams
                        crawl_news_for_teams(list(finished_team_ids))
                    except Exception as news_err:
                        print(f"[{datetime.now()}] 뉴스 크롤링 오류: {news_err}")
                # 종료 직후 records 업데이트 (10분 schedule + 즉시)
                schedule.every(10).minutes.do(_run_once, update_finished_game_records)
                schedule.every(15).minutes.do(_run_once, update_finished_player_stats)
        except Exception as pf_err:
            print(f"[종료 후처리] 오류: {pf_err}")

        # daily_stats 즉시 갱신 (재시작 안전 — game별 dedup)
        try:
            unsaved_finished = [
                gid for gid, c in curr_details.items()
                if c.get('status') == '종료' and not _already_notified(gid, 'daily_stats_saved')
            ]
            if unsaved_finished:
                _save_player_daily_stats_today()
                for gid in unsaved_finished:
                    _mark_notified(gid, 'daily_stats_saved')
        except Exception as ds_err:
            print(f"[즉시 daily_stats] 오류: {ds_err}")

        # ── 연승/연패/순위변동 알림 (재시작 안전: 종료 팀 전체 검사 + dedup) ─
        # newly_finished 의존 제거 → 재시작 후에도 누락 복구
        try:
            from api.fcm_service import notify_streak
            today_str = datetime.now().strftime('%Y-%m-%d')
            # 오늘 종료된 모든 팀 검사
            todays_finished_teams: set = set()
            for gid, curr in curr_details.items():
                if curr.get('status') == '종료':
                    if curr.get('home_team_id'): todays_finished_teams.add(curr['home_team_id'])
                    if curr.get('away_team_id'): todays_finished_teams.add(curr['away_team_id'])
            for team_id in todays_finished_teams:
                streak = _get_consecutive_record(team_id)
                if abs(streak) >= 3:  # 5→3 으로 임계값 낮춤
                    streak_subid = f"{team_id}_{abs(streak)}_{'W' if streak > 0 else 'L'}_{today_str}"
                    if _already_notified(0, 'streak', streak_subid):
                        continue
                    conn_s = get_connection()
                    if conn_s:
                        try:
                            cur_s = conn_s.cursor()
                            cur_s.execute("SELECT name FROM teams WHERE id = %s", (team_id,))
                            row_s = cur_s.fetchone()
                            cur_s.close()
                        finally:
                            conn_s.close()
                        if row_s:
                            notify_streak(team_id, row_s[0], abs(streak), streak > 0)
                            _mark_notified(0, 'streak', streak_subid)
        except Exception as streak_err:
            print(f"[FCM] 연승/연패 알림 오류: {streak_err}")

        # 끝내기 승리 알림 (재시작 안전: 모든 종료 경기 검사 + dedup)
        for gid, curr in curr_details.items():
            if curr.get('status') != '종료':
                continue
            try:
                if (curr.get('home_score', 0) > curr.get('away_score', 0)
                        and _is_walkoff(gid)
                        and not _already_notified(gid, 'walkoff')):
                    from api.fcm_service import notify_walkoff
                    notify_walkoff(gid, curr['home_team'], curr['away_team'],
                                   curr['home_score'], curr['away_score'],
                                   curr['home_team_id'], curr['away_team_id'])
                    _mark_notified(gid, 'walkoff')
            except Exception as wo_err:
                print(f"[FCM] 끝내기 알림 오류: {wo_err}")

        # 마일스톤 27분 후는 post_finished_done 블록에서 이미 schedule됨

        # 경기 종료 결과 요약 알림 — game_pitchers.result 채워질 때까지 대기
        # 종료 직후 naver_crawler가 result 채우는 시점 차이로 win/loss 빈 상태 발송 방지
        for gid, curr in curr_details.items():
            if curr.get('status') != '종료':
                continue
            if _already_notified(gid, 'game_end'):
                continue
            # 승투/세이브/홀드/패전 result 채워졌는지 확인 — 비어있으면 다음 사이클로 미룸
            try:
                ck = get_connection()
                if not ck:
                    continue
                ckc = ck.cursor()
                ckc.execute(
                    "SELECT COUNT(*) FROM game_pitchers WHERE game_id = %s AND result IN ('승','패','세이브','홀드')",
                    (gid,),
                )
                result_count = ckc.fetchone()[0]
                ckc.close()
                ck.close()
                if result_count < 1:
                    print(f"[FCM] game_summary 대기 game={gid} (result 미충원)")
                    continue
            except Exception as ck_err:
                print(f"[FCM] game_summary result 확인 오류 game={gid}: {ck_err}")
                continue
            # 마킹 먼저 (중복 호출 방지)
            _mark_notified(gid, 'game_end')
            try:
                _send_game_summary(gid)
            except Exception as gs_err:
                print(f"[FCM] game_summary 즉시 발송 오류 game={gid}: {gs_err}")

    conn = get_connection()
    if conn:
        cur = conn.cursor()
        cur.execute("""
            SELECT COUNT(*) FROM games g
            WHERE g.status = '종료'
            AND g.game_date = CURRENT_DATE
            AND g.naver_game_id IS NOT NULL
            AND (
                NOT EXISTS (
                    SELECT 1 FROM game_pitchers gp
                    WHERE gp.game_id = g.id
                    AND gp.pitching_order > 0
                )
                OR NOT EXISTS (
                    SELECT 1 FROM game_pitchers gp
                    WHERE gp.game_id = g.id
                    AND gp.result != ''
                )
            )
        """)
        missing = cur.fetchone()[0]
        cur.close()
        conn.close()

        if missing > 0:
            print(f"[{datetime.now()}] 기록 없는 종료 경기 {missing}개 → 5분 후 업데이트 예약")
            schedule.every(5).minutes.do(_run_once, update_finished_game_records)

def update_finished_player_stats():
    """경기 종료 후 선수 스탯 업데이트"""
    from crawler.statiz_crawler import (
        get_hitter_stats,
        get_pitcher_stats,
        save_players_and_stats,
    )
    print(f"[{datetime.now()}] 경기 종료 후 선수 스탯 업데이트 시작")

    hitters = get_hitter_stats(2026)
    deduped = {}
    for h in hitters:
        nid = h.get('naver_player_id')
        if nid not in deduped or h.get('games', 0) > deduped[nid].get('games', 0):
            deduped[nid] = h
    save_players_and_stats(list(deduped.values()), "HITTER")

    pitchers = get_pitcher_stats(2026)
    deduped = {}
    for p in pitchers:
        nid = p.get('naver_player_id')
        if nid not in deduped or p.get('games', 0) > deduped[nid].get('games', 0):
            deduped[nid] = p
    save_players_and_stats(list(deduped.values()), "PITCHER")

    _save_player_daily_stats_today()

    try:
        from crawler.kbo_daily_crawler import crawl_daily_stats_for_today_players
        crawl_daily_stats_for_today_players()
    except Exception as e:
        print(f"[{datetime.now()}] KBO daily 크롤링 오류: {e}")

    try:
        from crawler.kbo_daily_crawler import (
            crawl_kbo_hitter_season_stats,
            crawl_kbo_hitter_season_stats_2,
            crawl_kbo_pitcher_season_stats,
            crawl_kbo_pitcher_season_stats_2,
            crawl_kbo_runner_stats,
            crawl_kbo_defense_stats,
        )
        crawl_kbo_hitter_season_stats(2026)
        crawl_kbo_hitter_season_stats_2(2026)
        crawl_kbo_runner_stats(2026)
        crawl_kbo_defense_stats(2026)
        crawl_kbo_pitcher_season_stats(2026)
        crawl_kbo_pitcher_season_stats_2(2026)
    except Exception as e:
        print(f"[{datetime.now()}] KBO 시즌 스탯 크롤링 오류: {e}")

    # KBO가 규정타석 기준으로만 제공 → 나머지는 daily stats로 보완
    _sync_batter_stats_from_daily()

    print(f"[{datetime.now()}] 경기 종료 후 선수 스탯 업데이트 완료")


def _sync_batter_stats_from_daily():
    """player_daily_stats 누적 합산으로 batter_stats 보완 (statiz 지연 대응)"""
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    cur.execute("""
        UPDATE batter_stats bs
        SET
          rbis         = GREATEST(COALESCE(sub.total_rbi,     0), COALESCE(bs.rbis,         0)),
          hits         = GREATEST(COALESCE(sub.total_hits,    0), COALESCE(bs.hits,          0)),
          home_runs    = GREATEST(COALESCE(sub.total_hr,      0), COALESCE(bs.home_runs,     0)),
          runs         = GREATEST(COALESCE(sub.total_runs,    0), COALESCE(bs.runs,          0)),
          at_bats      = GREATEST(COALESCE(sub.total_ab,      0), COALESCE(bs.at_bats,       0)),
          games        = GREATEST(COALESCE(sub.game_count,    0), COALESCE(bs.games,         0)),
          walks        = GREATEST(COALESCE(sub.total_bb,      0), COALESCE(bs.walks,         0)),
          strikeouts   = GREATEST(COALESCE(sub.total_so,      0), COALESCE(bs.strikeouts,    0)),
          stolen_bases = GREATEST(COALESCE(sub.total_sb,      0), COALESCE(bs.stolen_bases,  0)),
          doubles      = GREATEST(COALESCE(sub.total_2b,      0), COALESCE(bs.doubles,       0)),
          triples      = GREATEST(COALESCE(sub.total_3b,      0), COALESCE(bs.triples,       0)),
          hbp          = GREATEST(COALESCE(sub.total_hbp,     0), COALESCE(bs.hbp,           0)),
          cs           = GREATEST(COALESCE(sub.total_cs,      0), COALESCE(bs.cs,            0)),
          pa           = GREATEST(COALESCE(sub.total_pa,      0), COALESCE(bs.pa,            0)),
          avg = CASE
                  WHEN bs.avg IS NOT NULL AND bs.avg > 0 THEN bs.avg
                  WHEN sub.total_ab > 0
                  THEN ROUND(sub.total_hits::numeric / sub.total_ab, 3)
                  ELSE 0
                END
        FROM (
          SELECT
            player_id,
            COUNT(*)        AS game_count,
            SUM(rbi)        AS total_rbi,
            SUM(hits)       AS total_hits,
            SUM(home_runs)  AS total_hr,
            SUM(runs)       AS total_runs,
            SUM(walks)      AS total_bb,
            SUM(strikeouts) AS total_so,
            SUM(sb)         AS total_sb,
            SUM(ab)         AS total_ab,
            SUM(doubles)    AS total_2b,
            SUM(triples)    AS total_3b,
            SUM(hbp)        AS total_hbp,
            SUM(cs)         AS total_cs,
            SUM(pa)         AS total_pa
          FROM player_daily_stats
          WHERE stat_type = 'hitter'
          AND game_date >= '2026-03-28'
          AND EXTRACT(YEAR FROM game_date) = 2026
          GROUP BY player_id
        ) sub
        WHERE bs.player_id = sub.player_id
        AND bs.season = 2026
    """)
    updated = cur.rowcount

    # PA/OBP/SLG/OPS 파생 스탯 보완
    cur.execute("""
        UPDATE batter_stats SET
            pa = COALESCE(at_bats,0) + COALESCE(walks,0) + COALESCE(hbp,0) + COALESCE(sac,0) + COALESCE(sf,0)
        WHERE season = 2026
          AND COALESCE(at_bats, 0) > COALESCE(pa, 0)
    """)
    cur.execute("""
        UPDATE batter_stats SET
            obp = CASE
                WHEN (COALESCE(at_bats,0) + COALESCE(walks,0) + COALESCE(hbp,0) + COALESCE(sf,0)) > 0
                THEN ROUND(
                    (COALESCE(hits,0) + COALESCE(walks,0) + COALESCE(hbp,0))::numeric /
                    (COALESCE(at_bats,0) + COALESCE(walks,0) + COALESCE(hbp,0) + COALESCE(sf,0)),
                    3)
                ELSE 0 END,
            slg = CASE
                WHEN COALESCE(at_bats,0) > 0
                THEN ROUND(
                    (COALESCE(hits,0) + COALESCE(doubles,0) + 2*COALESCE(triples,0) + 3*COALESCE(home_runs,0))::numeric /
                    at_bats, 3)
                ELSE 0 END
        WHERE season = 2026
          AND (obp IS NULL OR obp = 0)
          AND COALESCE(at_bats, 0) > 0
    """)
    cur.execute("""
        UPDATE batter_stats SET ops = ROUND(COALESCE(obp,0) + COALESCE(slg,0), 3)
        WHERE season = 2026
          AND (ops IS NULL OR ops = 0)
          AND (COALESCE(obp,0) > 0 OR COALESCE(slg,0) > 0)
    """)
    cur.execute("""
        UPDATE pitcher_stats SET
            era = ROUND(earned_runs * 9.0 /
                (FLOOR(innings_pitched) + (innings_pitched - FLOOR(innings_pitched)) * 10.0 / 3.0), 2)
        WHERE season = 2026
          AND (era IS NULL OR era = 0)
          AND COALESCE(innings_pitched, 0) > 0
          AND COALESCE(earned_runs, 0) > 0
    """)
    cur.execute("""
        UPDATE pitcher_stats SET
            whip = ROUND((COALESCE(walks,0) + COALESCE(hits_allowed,0))::numeric /
                (FLOOR(innings_pitched) + (innings_pitched - FLOOR(innings_pitched)) * 10.0 / 3.0), 2)
        WHERE season = 2026
          AND (whip IS NULL OR whip = 0)
          AND COALESCE(innings_pitched, 0) > 0
    """)

    conn.commit()
    cur.close()
    conn.close()
    print(f"[{datetime.now()}] batter_stats daily 동기화 완료 ({updated}명)")


def _save_player_daily_stats_today(target_date=None):
    """종료 경기의 player_daily_stats 업데이트 (game_batters/game_pitchers 기반)"""
    from datetime import date as _date_cls
    if target_date is None:
        target_date = _date_cls.today()
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()

    cur.execute("""
        SELECT g.id, g.game_date, g.home_score, g.away_score,
               ht.name, at2.name
        FROM games g
        JOIN teams ht ON g.home_team_id = ht.id
        JOIN teams at2 ON g.away_team_id = at2.id
        WHERE g.game_date = %s
        AND g.status = '종료'
        AND g.game_date >= '2026-03-28'
    """, (target_date,))
    games = cur.fetchall()

    total = 0
    for (game_id, game_date, home_score, away_score, home_team, away_team) in games:
        if home_score > away_score:
            home_result, away_result = '승', '패'
        elif home_score < away_score:
            home_result, away_result = '패', '승'
        else:
            home_result = away_result = '무'

        # 타자
        cur.execute("""
            SELECT player_id, team_side, at_bats, runs, hits, rbis,
                   home_runs, walks, strikeouts, stolen_bases, avg
            FROM game_batters WHERE game_id = %s
        """, (game_id,))
        for (pid, side, ab, runs, hits, rbi, hr, bb, so, sb, avg) in cur.fetchall():
            pa = (ab or 0) + (bb or 0)
            opponent = away_team if side == 'home' else home_team
            result = home_result if side == 'home' else away_result
            cur.execute("""
                INSERT INTO player_daily_stats (
                    player_id, game_date, opponent, result, stat_type,
                    avg, pa, ab, runs, hits, home_runs, rbi, sb, walks, strikeouts
                ) VALUES (%s, %s, %s, %s, 'hitter', %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (player_id, game_date, opponent, stat_type) DO UPDATE SET
                    result = COALESCE(EXCLUDED.result, player_daily_stats.result),
                    avg = COALESCE(EXCLUDED.avg, player_daily_stats.avg),
                    pa = GREATEST(EXCLUDED.pa, player_daily_stats.pa),
                    ab = GREATEST(EXCLUDED.ab, player_daily_stats.ab),
                    runs = GREATEST(EXCLUDED.runs, player_daily_stats.runs),
                    hits = GREATEST(EXCLUDED.hits, player_daily_stats.hits),
                    home_runs = GREATEST(EXCLUDED.home_runs, player_daily_stats.home_runs),
                    rbi = GREATEST(EXCLUDED.rbi, player_daily_stats.rbi),
                    sb = GREATEST(EXCLUDED.sb, player_daily_stats.sb),
                    walks = GREATEST(EXCLUDED.walks, player_daily_stats.walks),
                    strikeouts = GREATEST(EXCLUDED.strikeouts, player_daily_stats.strikeouts)
            """, (pid, game_date, opponent, result, avg, pa, ab, runs, hits, hr, rbi, sb, bb, so))
            total += 1

        # 투수
        cur.execute("""
            SELECT player_id, team_side, innings_pitched, hits_allowed,
                   earned_runs, runs_allowed, walks, strikeouts, home_runs_allowed
            FROM game_pitchers WHERE game_id = %s
        """, (game_id,))
        for (pid, side, ip, h, er, r, bb, so, hr) in cur.fetchall():
            opponent = away_team if side == 'home' else home_team
            result = home_result if side == 'home' else away_result
            era = round(float(er) / float(ip) * 9, 2) if ip and float(ip) > 0 else None
            cur.execute("""
                INSERT INTO player_daily_stats (
                    player_id, game_date, opponent, result, stat_type,
                    era, ip, h, hr, bb, so, r, er
                ) VALUES (%s, %s, %s, %s, 'pitcher', %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (player_id, game_date, opponent, stat_type) DO UPDATE SET
                    result = EXCLUDED.result,
                    era = EXCLUDED.era,
                    ip = EXCLUDED.ip,
                    h = EXCLUDED.h,
                    hr = EXCLUDED.hr,
                    bb = EXCLUDED.bb,
                    so = EXCLUDED.so,
                    r = EXCLUDED.r,
                    er = EXCLUDED.er
            """, (pid, game_date, opponent, result, era, ip, h, hr, bb, so, r, er))
            total += 1

    conn.commit()
    cur.close()
    conn.close()
    print(f"[{datetime.now()}] player_daily_stats 업데이트 완료 ({len(games)}경기, {total}건)")

def _update_live_games_realtime():
    """진행 중인 경기 이닝/선수/투구 업데이트"""
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    cur.execute("""
        SELECT id, naver_game_id FROM games
        WHERE game_date = CURRENT_DATE
        AND status = '진행'
        AND naver_game_id IS NOT NULL
    """)
    live_games = cur.fetchall()
    cur.close()
    conn.close()

    if live_games:
        print(f"[{datetime.now()}] 진행 중인 경기: {len(live_games)}개 업데이트")
    for (db_game_id, naver_game_id) in live_games:
        update_live_game_innings(db_game_id, naver_game_id)
        update_live_game_players(db_game_id, naver_game_id)
        conn2 = get_connection()
        if conn2:
            cur2 = conn2.cursor()
            cur2.execute(
                "SELECT current_inning FROM games WHERE id = %s", (db_game_id,)
            )
            row = cur2.fetchone()
            cur2.close()
            conn2.close()
            if row and row[0]:
                save_game_pitches(db_game_id, naver_game_id, row[0])

                conn3 = get_connection()
                if conn3:
                    cur3 = conn3.cursor()
                    cur3.execute("""
                        SELECT DISTINCT inning FROM game_pitches
                        WHERE game_id = %s
                        AND inning < %s
                        AND batter_name IS NULL
                    """, (db_game_id, row[0]))
                    missing_innings = [r[0] for r in cur3.fetchall()]
                    cur3.close()
                    conn3.close()
                    for inning in missing_innings:
                        save_game_pitches(db_game_id, naver_game_id, inning)


def _update_lineup_by_starttime():
    """
    1단계: start_time 2시간 전 ~ 로스터 자체 없는 경기 크롤링 (후보야수/불펜)
    2단계: start_time 1시간 전부터 선발 타자 없으면 10분마다 재크롤링
    """
    now_utc = datetime.now(timezone.utc)

    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()

    # start_time 2시간 전부터 선발 타자 없으면 10분마다 재크롤링
    games_no_lineup = []
    if now_utc.minute % 10 == 0:
        cur.execute("""
            SELECT id, naver_game_id FROM games
            WHERE game_date = CURRENT_DATE
            AND status = '예정'
            AND naver_game_id IS NOT NULL
            AND start_time IS NOT NULL
            AND (start_time - INTERVAL '2 hours') <=
                (CURRENT_TIME AT TIME ZONE 'UTC' + INTERVAL '9 hours')
            AND NOT EXISTS (
                SELECT 1 FROM game_rosters gr
                WHERE gr.game_id = games.id
                AND gr.is_starter = TRUE
                AND gr.roster_type = 'batter'
            )
        """)
        games_no_lineup = cur.fetchall()

    cur.close()
    conn.close()

    if games_no_lineup:
        print(f"[{datetime.now()}] 선발 타자 없는 예정 경기 재크롤링: {len(games_no_lineup)}개")
        refreshed = []
        for (db_game_id, naver_game_id) in games_no_lineup:
            save_game_roster(db_game_id, naver_game_id)
            save_entry_roster(db_game_id, naver_game_id)  # 후보/불펜 보강
            refreshed.append(db_game_id)
            time.sleep(0.5)
        # 라인업 크롤 후 예측 재로깅 (선발 타자가 새로 채워졌으면 라인업 OPS 정확)
        try:
            from api.cache import cache_delete_prefix
            from api.prediction.eval import log_prediction
            for gid in refreshed:
                cache_delete_prefix(f'api.routers.prediction.get_game_win_prediction:({gid},)')
                log_prediction(gid)
        except Exception as _pe:
            print(f"[prediction] 라인업 크롤 후 재로깅 오류: {_pe}")


def _update_lineup_fallback():
    """진행 중인데 선발 타자 없는 경기 - 10분마다 재크롤링"""
    now_utc = datetime.now(timezone.utc)
    if now_utc.minute % 10 != 0:
        return

    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    cur.execute("""
        SELECT id, naver_game_id FROM games
        WHERE game_date = CURRENT_DATE
        AND status = '진행'
        AND naver_game_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1 FROM game_rosters gr
            WHERE gr.game_id = games.id
            AND gr.is_starter = TRUE
            AND gr.roster_type = 'batter'
        )
    """)
    games = cur.fetchall()
    cur.close()
    conn.close()

    if games:
        print(f"[{datetime.now()}] 진행 중 선발 타자 없는 경기 재크롤링: {len(games)}개")
        for (db_game_id, naver_game_id) in games:
            save_game_roster(db_game_id, naver_game_id)
            save_entry_roster(db_game_id, naver_game_id)  # 후보/불펜 보강
            time.sleep(0.5)
        # roster 저장 후 starter position 안전망 sweep
        _fixup_starter_positions()


def _update_roster_changes_pregame():
    """
    경기 시작 2시간 전 ~ 30분 전 구간, 5분마다 등록말소 크롤링
    (이 구간에 해당하는 경기가 있을 때만 실행)
    """
    now_utc = datetime.now(timezone.utc)
    if now_utc.minute % 5 != 0:
        return

    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    # 오늘 경기 중 [start_time-2h, start_time-30min] 구간에 있는 예정/라인업 경기 존재 여부
    cur.execute("""
        SELECT COUNT(*) FROM games
        WHERE game_date = CURRENT_DATE
        AND status IN ('예정', '라인업')
        AND start_time IS NOT NULL
        AND (start_time - INTERVAL '2 hours') <=
            (CURRENT_TIME AT TIME ZONE 'UTC' + INTERVAL '9 hours')
        AND (CURRENT_TIME AT TIME ZONE 'UTC' + INTERVAL '9 hours') <=
            (start_time - INTERVAL '30 minutes')
    """)
    count = cur.fetchone()[0]
    cur.close()
    conn.close()

    if count == 0:
        return

    try:
        from crawler.kbo_roster_crawler import run_today
        print(f"[{datetime.now()}] 경기전 등록말소 크롤링 ({count}경기 대기 중)")
        run_today()
    except Exception as e:
        print(f"[{datetime.now()}] 등록말소 크롤링 오류: {e}")


def _get_game_statuses():
    conn = get_connection()
    if not conn:
        return {}
    cur = conn.cursor()
    cur.execute("SELECT id, status FROM games WHERE game_date = CURRENT_DATE")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return {r[0]: r[1] for r in rows}


def _get_game_details():
    """오늘 경기의 상태 + 스코어 + 팀 정보 + 이닝 반환"""
    conn = get_connection()
    if not conn:
        return {}
    cur = conn.cursor()
    cur.execute("""
        SELECT g.id, g.status, g.home_score, g.away_score,
               ht.name, at2.name, g.home_team_id, g.away_team_id,
               COALESCE(g.current_inning, 0), g.inning_half,
               TO_CHAR(g.start_time, 'HH24:MI'), g.naver_game_id, g.stadium_id
        FROM games g
        JOIN teams ht ON g.home_team_id = ht.id
        JOIN teams at2 ON g.away_team_id = at2.id
        WHERE g.game_date = (NOW() AT TIME ZONE 'Asia/Seoul')::date
    """)
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return {
        r[0]: {
            'status':         r[1],
            'home_score':     r[2] or 0,
            'away_score':     r[3] or 0,
            'home_team':      r[4],
            'away_team':      r[5],
            'home_team_id':   r[6],
            'away_team_id':   r[7],
            'current_inning': r[8] or 0,
            'inning_half':    r[9] or '',
            'start_time':     r[10] or '',
            'naver_game_id':  r[11] or '',
            'stadium_id':     r[12],
        }
        for r in rows
    }


def _get_rankings_snapshot() -> dict:
    """팀별 현재 순위 스냅샷 {team_id: {rank, games_behind}}"""
    conn = get_connection()
    if not conn:
        return {}
    try:
        cur = conn.cursor()
        cur.execute("SELECT id, rank, games_behind, name FROM teams WHERE rank IS NOT NULL")
        rows = cur.fetchall()
        cur.close()
        return {r[0]: {'rank': r[1], 'games_behind': r[2], 'name': r[3]} for r in rows}
    except Exception:
        return {}
    finally:
        conn.close()


def _get_consecutive_record(team_id: int) -> int:
    """최근 결과 연속 W/L 카운트 (양수=연승, 음수=연패, 0=무승부/없음)"""
    conn = get_connection()
    if not conn:
        return 0
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT
                CASE
                    WHEN home_team_id = %s THEN
                        CASE WHEN home_score > away_score THEN 'W'
                             WHEN home_score < away_score THEN 'L' ELSE 'D' END
                    ELSE
                        CASE WHEN away_score > home_score THEN 'W'
                             WHEN away_score < home_score THEN 'L' ELSE 'D' END
                END
            FROM games
            WHERE (home_team_id = %s OR away_team_id = %s)
              AND status = '종료' AND home_score IS NOT NULL
            ORDER BY game_date DESC, id DESC
            LIMIT 10
        """, (team_id, team_id, team_id))
        results = [r[0] for r in cur.fetchall()]
        cur.close()
        if not results or results[0] == 'D':
            return 0
        first, count = results[0], 0
        for r in results:
            if r == first:
                count += 1
            else:
                break
        return count if first == 'W' else -count
    except Exception:
        return 0
    finally:
        conn.close()


def _get_scoring_play_detail(naver_game_id, inning, new_home_score, new_away_score):
    """Naver 중계 API에서 득점 타자/투수/타구/투구내용 추출. 실패 시 ('','','','',0,[],0) 반환
    우선순위: type=13(타석결과) > 특수키워드(폭투/보크/패스트볼) > type=1(마지막 투구)
    """
    import requests, re as _re
    HEADERS = {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://sports.naver.com/'}
    _SPECIAL_KW = ('폭투', '보크', '패스트볼', '보크')
    conn = None
    cur = None
    try:
        url = f"https://api-gw.sports.naver.com/schedule/games/{naver_game_id}/relay?inning={inning}"
        res = requests.get(url, headers=HEADERS, timeout=5)
        relay = res.json().get('result', {}).get('textRelayData', {})
        text_relays = relay.get('textRelays', [])

        conn = get_connection()
        cur = conn.cursor() if conn else None
        pitcher_cache = {}

        curr_batter = curr_pitcher = ''
        curr_stuff = ''
        curr_speed = 0
        curr_pitch_num = 0

        # type=1 (투구 이벤트) 마지막 값
        last1_batter = last1_pitcher = last1_text = last1_stuff = ''
        last1_speed = last1_pitch_num = 0

        # type=13 (타석 결과: 희생플라이/안타/볼넷/삼진/번트 등) 마지막 값
        last13_text = last13_batter = last13_pitcher = ''

        # 특수 키워드 이벤트 (폭투/보크/패스트볼)
        last_sp_text = last_sp_batter = last_sp_pitcher = ''

        def _reset_at_bat():
            nonlocal last1_batter, last1_pitcher, last1_text, last1_stuff
            nonlocal last1_speed, last1_pitch_num
            nonlocal last13_text, last13_batter, last13_pitcher
            nonlocal last_sp_text, last_sp_batter, last_sp_pitcher
            last1_batter = last1_pitcher = last1_text = last1_stuff = ''
            last1_speed = last1_pitch_num = 0
            last13_text = last13_batter = last13_pitcher = ''
            last_sp_text = last_sp_batter = last_sp_pitcher = ''

        result_batter = result_pitcher = result_text = result_stuff = ''
        result_speed = 0
        result_pitch_num = 0
        result_homein = []
        found_scoring = False
        done = False

        # Naver textRelays는 최신순(역순) 반환 → reversed로 chronological 순회
        # 안 하면 첫 이벤트(득점 후 상태)에서 즉시 score 감지 → last_*_text 빈값
        for item in reversed(text_relays):
            if done:
                break
            for opt in item.get('textOptions', []):
                state = opt.get('currentGameState', {}) or {}
                otype = opt.get('type')
                text_now = opt.get('text', '')

                # 투수 이름 (state에서 실시간 추적)
                pid = str(state.get('pitcher') or '')
                if pid and cur:
                    if pid not in pitcher_cache:
                        cur.execute("SELECT name FROM players WHERE naver_player_id=%s LIMIT 1", (pid,))
                        row = cur.fetchone()
                        pitcher_cache[pid] = row[0] if row else ''
                    curr_pitcher = pitcher_cache.get(pid, '')

                # 타자 교체 감지 (batterRecord or type=8 선수교체 공지)
                br = opt.get('batterRecord') or {}
                if br.get('name'):
                    if br['name'] != curr_batter:
                        curr_pitch_num = 0
                        _reset_at_bat()
                    curr_batter = br['name']
                elif otype == 8:
                    m = _re.match(r'^(?:\d+번타자|대타)\s+(\S+)', text_now)
                    if m:
                        if m.group(1) != curr_batter:
                            curr_pitch_num = 0
                            _reset_at_bat()
                        curr_batter = m.group(1)
                    if found_scoring:
                        done = True
                        break

                # 구종/구속 갱신 (어떤 이벤트든)
                if opt.get('stuff'):
                    curr_stuff = opt['stuff']
                    curr_speed = int(opt.get('speed', 0) or 0)

                # type=1: 투구 이벤트
                if otype == 1:
                    curr_pitch_num += 1
                    last1_batter = curr_batter
                    last1_pitcher = curr_pitcher
                    last1_text = text_now
                    last1_stuff = opt.get('stuff', '') or curr_stuff
                    last1_speed = int(opt.get('speed', 0) or 0) or curr_speed
                    last1_pitch_num = curr_pitch_num

                # type=13(홈팀)/23(원정팀): 타석 최종 결과 (희생플라이/안타/번트/볼넷/삼진 등)
                elif otype in (13, 23):
                    last13_text = text_now
                    last13_batter = curr_batter
                    last13_pitcher = curr_pitcher

                # 특수 키워드: 폭투/보크/패스트볼 (type 무관)
                if text_now and any(kw in text_now for kw in _SPECIAL_KW):
                    last_sp_text = text_now
                    last_sp_batter = curr_batter
                    last_sp_pitcher = curr_pitcher

                # 득점 상태 감지
                hs = state.get('homeScore')
                aws = state.get('awayScore')
                if hs is not None and aws is not None:
                    if int(hs) >= new_home_score and int(aws) >= new_away_score:
                        if not found_scoring:
                            # 우선순위: type13 > 특수키워드 > type1
                            if last13_text:
                                result_text = last13_text
                                result_batter = last13_batter or curr_batter
                                result_pitcher = last13_pitcher or curr_pitcher
                                result_stuff = last1_stuff
                                result_speed = last1_speed
                                result_pitch_num = last1_pitch_num
                            elif last_sp_text:
                                result_text = last_sp_text
                                result_batter = last_sp_batter or curr_batter
                                result_pitcher = last_sp_pitcher or curr_pitcher
                                result_stuff = last1_stuff
                                result_speed = last1_speed
                                result_pitch_num = last1_pitch_num
                            elif last1_text:
                                result_text = last1_text
                                result_batter = last1_batter or curr_batter
                                result_pitcher = last1_pitcher or curr_pitcher
                                result_stuff = last1_stuff
                                result_speed = last1_speed
                                result_pitch_num = last1_pitch_num
                            else:
                                # 타석 이벤트 없는 득점 (다른 이닝 주자 등)
                                result_batter = curr_batter
                                result_pitcher = curr_pitcher
                            found_scoring = True

                # 홈인 수집 (type 14/24/31)
                # 정규식: 한글 이름 2~4자 + 선택적 조사(이/가) + 홈인
                # 조사/부사 어미('로'/'서'/'에'/'으') 끝나면 reject → "실책으로 홈인" 같은 케이스 차단
                if found_scoring and otype in (14, 24, 31):
                    _PARTICLE_SUFFIX = ('로', '서', '에', '으', '며', '면', '도', '만', '나')
                    for _m in _re.finditer(r'([가-힣]{2,4})(?:이|가)?\s*홈인', text_now):
                        _name = _m.group(1)
                        if _name.endswith(_PARTICLE_SUFFIX):
                            continue
                        if _name not in result_homein:
                            result_homein.append(_name)

        return result_batter, result_pitcher, result_text, result_stuff, result_speed, result_homein, result_pitch_num
    except Exception:
        return '', '', '', '', 0, [], 0
    finally:
        if cur:
            try: cur.close()
            except: pass
        if conn:
            try: conn.close()
            except: pass


def _notify_roster_for_fans():
    """오늘 등록말소: 즐겨찾기 선수 팬 + 마이팀 팬 모두에게 알림"""
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT prc.player_id, prc.player_name, prc.change_type, p.team_id
            FROM player_roster_changes prc
            LEFT JOIN players p ON p.id = prc.player_id
            WHERE prc.change_date = CURRENT_DATE
              AND prc.player_id IS NOT NULL
              AND prc.change_type IN ('1군 등록', '1군 말소')
        """)
        rows = cur.fetchall()
        cur.close()
    except Exception:
        return
    finally:
        conn.close()
    if not rows:
        return
    try:
        from api.fcm_service import notify_roster_change, notify_team_roster_change
        for player_id, player_name, change_type, team_id in rows:
            notify_roster_change(player_id, player_name, change_type)
            if team_id:
                notify_team_roster_change(team_id, player_id, player_name, change_type)
    except Exception as e:
        print(f"[FCM] 로스터 알림 오류: {e}")


def _run_once(func, *args):
    func(*args)
    return schedule.CancelJob


def _update_today_games():
    today = datetime.today().strftime("%Y-%m-%d")
    games = get_games_by_date(today)
    if games:
        save_teams(games)
        save_games(games)


def update_finished_game_records():
    """종료 경기 상세 기록 업데이트"""
    print(f"[{datetime.now()}] 경기 상세 기록 업데이트 시작")

    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    cur.execute("""
        SELECT g.id, g.naver_game_id,
               REPLACE(g.game_date::text, '-', '') AS game_date_str
        FROM games g
        WHERE g.status = '종료'
        AND g.naver_game_id IS NOT NULL
        AND (
            NOT EXISTS (
                SELECT 1 FROM game_pitchers gp WHERE gp.game_id = g.id
            )
            OR NOT EXISTS (
                SELECT 1 FROM game_pitchers gp
                WHERE gp.game_id = g.id AND gp.pitching_order > 0
            )
            OR NOT EXISTS (
                SELECT 1 FROM game_pitchers gp
                WHERE gp.game_id = g.id AND gp.result != ''
            )
            OR NOT EXISTS (
                SELECT 1 FROM game_innings gi WHERE gi.game_id = g.id
            )
        )
        AND g.game_date >= CURRENT_DATE - INTERVAL '3 days'
    """)
    games = cur.fetchall()
    cur.close()
    conn.close()

    print(f"업데이트 필요한 종료 경기: {len(games)}개")
    for (db_game_id, naver_game_id, game_date_str) in games:
        if not _is_regular_game(naver_game_id):
            continue
        record = get_game_record(naver_game_id)
        if record:
            save_game_record(db_game_id, record)
        time.sleep(0.3)

    conn = get_connection()
    if conn:
        cur = conn.cursor()
        cur.execute("""
            SELECT id, naver_game_id FROM games
            WHERE status = '종료'
            AND game_date = CURRENT_DATE
            AND naver_game_id IS NOT NULL
            AND NOT EXISTS (
                SELECT 1 FROM game_rosters gr
                WHERE gr.game_id = games.id AND gr.is_starter = TRUE
                AND gr.roster_type = 'batter'
            )
        """)
        games_no_roster = cur.fetchall()
        cur.close()
        conn.close()

        if games_no_roster:
            print(f"선발 타자 없는 종료 경기: {len(games_no_roster)}개")
            for (db_game_id, naver_game_id) in games_no_roster:
                save_game_roster(db_game_id, naver_game_id)
                save_entry_roster(db_game_id, naver_game_id)  # 후보/불펜 보강
                time.sleep(0.5)

    update_team_rankings()
    print(f"[{datetime.now()}] 상세 기록 업데이트 완료")


def _snapshot_rank_history(curr_ranks: dict):
    """오늘 순위 스냅샷 INSERT (mv 계산용). UNIQUE(team_id, snapshot_date) ON CONFLICT DO NOTHING."""
    from database.connection import get_connection as _gc
    from datetime import date as _date
    conn = _gc()
    if not conn:
        return
    try:
        cur = conn.cursor()
        today = _date.today()
        for team_id, curr in curr_ranks.items():
            rank = curr.get('rank')
            if not rank:
                continue
            cur.execute("""
                INSERT INTO team_rank_history (team_id, rank, snapshot_date)
                VALUES (%s, %s, %s)
                ON CONFLICT (team_id, snapshot_date) DO NOTHING
            """, (team_id, rank, today))
        conn.commit()
        cur.close()
    except Exception as e:
        print(f"[rank_history] snapshot 오류: {e}")
    finally:
        conn.close()


def update_team_rankings():
    print(f"[{datetime.now()}] 팀 순위 업데이트")
    prev_ranks = _get_rankings_snapshot()
    teams = get_team_rankings(2026)
    save_team_rankings(teams)
    curr_ranks = _get_rankings_snapshot()
    today_str = datetime.now().strftime('%Y-%m-%d')

    # mv 계산용 daily snapshot
    _snapshot_rank_history(curr_ranks)

    # 순위 변동 알림 (재시작 안전: sub_id에 old→new 순위 + 날짜 포함)
    try:
        from api.fcm_service import notify_rank_change
        for team_id, curr in curr_ranks.items():
            prev = prev_ranks.get(team_id, {})
            old_r, new_r = prev.get('rank'), curr['rank']
            if old_r and new_r and old_r != new_r:
                sub_id = f"{team_id}_{old_r}_{new_r}_{today_str}"
                if _already_notified(0, 'rank_change', sub_id):
                    continue
                notify_rank_change(team_id, curr['name'], old_r, new_r,
                                   curr.get('games_behind') or 0)
                _mark_notified(0, 'rank_change', sub_id)
    except Exception as e:
        print(f"[FCM] 순위 알림 오류: {e}")

    # 1위 마이팀 추격전 알림 (재시작 안전: sub_id에 gap + 날짜)
    try:
        from api.fcm_service import notify_pennant_race
        first_curr = [(tid, d) for tid, d in curr_ranks.items() if d.get('rank') == 1]
        first_prev = [(tid, d) for tid, d in prev_ranks.items() if d.get('rank') == 1]
        if first_curr and first_prev:
            first_tid, first_data = first_curr[0]
            sec_curr = [d for d in curr_ranks.values() if d.get('rank') == 2]
            sec_prev = [d for d in prev_ranks.values() if d.get('rank') == 2]
            if sec_curr and sec_prev:
                curr_gap = float(sec_curr[0].get('games_behind') or 0)
                prev_gap = float(sec_prev[0].get('games_behind') or 0)
                if curr_gap < prev_gap and curr_gap >= 0:
                    sub_id = f"{first_tid}_{curr_gap:.1f}_{today_str}"
                    if not _already_notified(0, 'pennant_race', sub_id):
                        notify_pennant_race(first_tid, first_data['name'], curr_gap, prev_gap)
                        _mark_notified(0, 'pennant_race', sub_id)
    except Exception as e:
        print(f"[FCM] 페넌트레이스 알림 오류: {e}")

    # 게임차 0 달성 알림 (재시작 안전: sub_id에 team_id + 날짜)
    try:
        from api.fcm_service import notify_gb_zero
        first_name = next((d['name'] for d in curr_ranks.values() if d.get('rank') == 1), '')
        for team_id, curr in curr_ranks.items():
            if curr.get('rank', 99) <= 1:
                continue
            new_gb = curr.get('games_behind')
            if new_gb is None or float(new_gb) != 0:
                continue
            sub_id = f"{team_id}_{today_str}"
            if _already_notified(0, 'gb_zero', sub_id):
                continue
            notify_gb_zero(team_id, curr['name'], first_name)
            _mark_notified(0, 'gb_zero', sub_id)
    except Exception as e:
        print(f"[FCM] 게임차0 알림 오류: {e}")


def _update_roster_changes():
    """오늘 등록말소 + 선수이동 크롤링"""
    try:
        from crawler.kbo_roster_crawler import run_today, run_trade
        print(f"[{datetime.now()}] 등록말소 크롤링 시작")
        run_today()
        run_trade(days=7)
        _notify_roster_for_fans()
        # 등록말소 발생 → 오늘 예정 게임 예측 캐시 무효화 + 재로깅
        try:
            from api.cache import cache_delete_prefix
            from api.prediction.eval import log_today_predictions
            cache_delete_prefix('api.routers.prediction.get_game_win_prediction')
            log_today_predictions()
            print(f"[{datetime.now()}] 등록말소 후 예측 재로깅 완료")
        except Exception as _pe:
            print(f"[prediction] 등록말소 후 재로깅 오류: {_pe}")
    except Exception as e:
        print(f"[{datetime.now()}] 등록말소 크롤링 오류: {e}")


def update_kbo_player_stats(player_ids=None):
    """KBO 사이트에서 선수 2026 시즌 스탯 업데이트. player_ids 지정 시 해당 선수만."""
    try:
        from selenium.webdriver.common.by import By
        from crawler.crawl_kbo_player_info import (
            get_driver,
            parse_basic_info,
            parse_basic_stats_hitter,
            parse_basic_stats_pitcher,
            parse_awards,
            parse_register_days,
            save_basic_stats_hitter,
            save_basic_stats_pitcher,
            save_awards,
            save_register_days,
        )
    except ImportError as e:
        print(f"[{datetime.now()}] KBO 선수 스탯 업데이트 건너뜀 (모듈 없음): {e}")
        return

    label = f"{len(player_ids)}명" if player_ids else "전체"
    print(f"[{datetime.now()}] KBO 선수 스탯 업데이트 시작 ({label})")

    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    if player_ids:
        cur.execute("""
            SELECT id, name, naver_player_id, player_type
            FROM players
            WHERE naver_player_id IS NOT NULL AND id = ANY(%s)
            ORDER BY id
        """, (player_ids,))
    else:
        cur.execute("""
            SELECT id, name, naver_player_id, player_type
            FROM players
            WHERE naver_player_id IS NOT NULL
            ORDER BY id
        """)
    players = cur.fetchall()
    cur.close()
    conn.close()

    driver = get_driver()
    updated = 0

    for player_id, name, naver_id, player_type in players:
        try:
            ptype = 'Hitter' if player_type == '타자' else 'Pitcher'
            base_url = f"https://www.koreabaseball.com/Record/Player/{ptype}Detail"
            driver.get(f"{base_url}/Basic.aspx?playerId={naver_id}")
            time.sleep(1.2)
            basic_lines = driver.find_element(By.TAG_NAME, 'body').text.split('\n')

            basic_info = parse_basic_info(basic_lines)
            basic_stats = parse_basic_stats_hitter(basic_lines) if player_type == '타자' else parse_basic_stats_pitcher(basic_lines)
            awards = parse_awards(basic_lines)
            register_records = parse_register_days(basic_lines)

            conn = get_connection()
            if not conn:
                continue
            cur = conn.cursor()

            cur.execute("""
                UPDATE players SET
                    throws = COALESCE(%s, throws),
                    bats = COALESCE(%s, bats),
                    position = COALESCE(NULLIF(%s, ''), position)
                WHERE id = %s
            """, (basic_info['throws'], basic_info['bats'], basic_info['position'], player_id))

            if player_type == '타자':
                save_basic_stats_hitter(cur, player_id, basic_stats)
            else:
                save_basic_stats_pitcher(cur, player_id, basic_stats)

            save_awards(cur, player_id, awards)
            save_register_days(cur, player_id, register_records)

            conn.commit()
            cur.close()
            conn.close()
            updated += 1

        except Exception as e:
            print(f"KBO 크롤링 오류 ({name}): {e}")
            try:
                conn.rollback()
                conn.close()
            except:
                pass
            continue

    driver.quit()
    print(f"[{datetime.now()}] KBO 선수 스탯 업데이트 완료 ({updated}명)")


def _crawl_kbo_stats_for_game(game_id):
    """경기 종료 후 해당 경기 출전 선수만 KBO 크롤링"""
    try:
        conn = get_connection()
        if not conn:
            return
        cur = conn.cursor()
        cur.execute("""
            SELECT DISTINCT player_id FROM game_pitchers WHERE game_id = %s
            UNION
            SELECT DISTINCT player_id FROM game_batters WHERE game_id = %s
        """, (game_id, game_id))
        player_ids = [r[0] for r in cur.fetchall()]
        cur.close()
        conn.close()
        if not player_ids:
            print(f"[{datetime.now()}] game_id={game_id} 출전 선수 없음, KBO 크롤 건너뜀")
            return
        print(f"[{datetime.now()}] game_id={game_id} 출전 선수 {len(player_ids)}명 KBO 크롤 시작")
        update_kbo_player_stats(player_ids=player_ids)
        # game_pitchers 최종값 반영 — T+25 이후 daily_stats 재동기화
        try:
            from datetime import date as _d
            _save_player_daily_stats_today()
        except Exception as _ds_e:
            print(f"[{datetime.now()}] daily_stats 재동기화 오류: {_ds_e}")
    except Exception as e:
        print(f"[{datetime.now()}] 경기별 KBO 크롤 오류 (game_id={game_id}): {e}")


def update_player_stats():
    from crawler.statiz_crawler import (
        crawl_player_info_selenium,
        crawl_missing_player_ids,
        crawl_kbo_register,
    )
    print(f"[{datetime.now()}] 선수 통계 업데이트 시작")

    hitters = get_hitter_stats(2026)
    deduped = {}
    for h in hitters:
        nid = h.get('naver_player_id')
        if nid not in deduped or h.get('games', 0) > deduped[nid].get('games', 0):
            deduped[nid] = h
    save_players_and_stats(list(deduped.values()), "HITTER")

    pitchers = get_pitcher_stats(2026)
    deduped = {}
    for p in pitchers:
        nid = p.get('naver_player_id')
        if nid not in deduped or p.get('games', 0) > deduped[nid].get('games', 0):
            deduped[nid] = p
    save_players_and_stats(list(deduped.values()), "PITCHER")

    crawl_kbo_register()
    crawl_missing_player_ids()
    crawl_player_info_selenium()
    print(f"[{datetime.now()}] 선수 통계 업데이트 완료")


def update_season_schedule():
    print(f"[{datetime.now()}] 시즌 일정 업데이트 시작")
    all_games = get_season_schedule(2026)
    save_games(all_games)
    print(f"시즌 일정 {len(all_games)}경기 업데이트 완료")


def _is_regular_game(naver_game_id):
    import re
    pattern = r'^\d{8}[A-Z]{4}02026$'
    return bool(re.match(pattern, naver_game_id))


def _crawl_highlights_hourly():
    try:
        from crawler.crawl_highlights import crawl_highlights
        crawl_highlights()
    except Exception as e:
        print(f"[{datetime.now()}] 하이라이트 크롤링 오류: {e}")


def _crawl_news_hourly():
    try:
        from crawler.crawl_naver_news import crawl_all_team_news
        crawl_all_team_news()
    except Exception as e:
        print(f"[{datetime.now()}] 뉴스 시간별 크롤링 오류: {e}")


def _send_pregame_notifications():
    """경기 시작 전 알림 — 유저별 notify_before_minutes(30/60/120) 기준"""
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        for minutes in (30, 60, 120):
            cur.execute("""
                SELECT g.id, g.home_team_id, g.away_team_id,
                       ht.name AS home_team, at2.name AS away_team
                FROM games g
                JOIN teams ht  ON ht.id  = g.home_team_id
                JOIN teams at2 ON at2.id = g.away_team_id
                WHERE g.game_date = CURRENT_DATE
                  AND g.status IN ('예정', '라인업')
                  AND g.start_time IS NOT NULL
                  AND g.start_time >= ((CURRENT_TIME AT TIME ZONE 'Asia/Seoul')::time)
                                      + (%s * INTERVAL '1 minute')
                                      - INTERVAL '2 minutes 30 seconds'
                  AND g.start_time <  ((CURRENT_TIME AT TIME ZONE 'Asia/Seoul')::time)
                                      + (%s * INTERVAL '1 minute')
                                      + INTERVAL '2 minutes 30 seconds'
            """, (minutes, minutes))
            games = cur.fetchall()

            for game_id, home_tid, away_tid, home_team, away_team in games:
                cur.execute("""
                    SELECT DISTINCT pt.user_id, pt.token
                    FROM push_tokens pt
                    LEFT JOIN user_settings us ON us.user_id = pt.user_id
                    WHERE COALESCE(us.notify_game_start, TRUE) = TRUE
                      AND COALESCE(us.notify_before_minutes, 60) = %s
                      AND (
                        COALESCE(us.notify_my_team_only, FALSE) = FALSE
                        OR EXISTS (
                            SELECT 1 FROM user_favorite_teams uft
                            WHERE uft.user_id = pt.user_id
                              AND uft.team_id = ANY(%s)
                        )
                      )
                      AND NOT EXISTS (
                        SELECT 1 FROM pregame_notifications_sent pns
                        WHERE pns.user_id = pt.user_id AND pns.game_id = %s
                      )
                """, (minutes, [home_tid, away_tid], game_id))
                targets = cur.fetchall()
                if not targets:
                    continue

                label = '2시간' if minutes == 120 else '1시간' if minutes == 60 else '30분'
                title = f"⚾ {away_team} vs {home_team} {label} 전"
                body = f"{label} 뒤에 경기가 시작됩니다"

                user_ids = [t[0] for t in targets]
                cur.executemany(
                    "INSERT INTO user_notifications (user_id, title, body, type, game_id)"
                    " VALUES (%s,%s,%s,%s,%s)",
                    [(uid, title, body, 'game_start', game_id) for uid in user_ids]
                )
                cur.executemany(
                    "INSERT INTO pregame_notifications_sent (user_id, game_id)"
                    " VALUES (%s,%s) ON CONFLICT DO NOTHING",
                    [(uid, game_id) for uid in user_ids]
                )
                conn.commit()

                try:
                    from api.fcm_service import _get_app
                    if _get_app() is not None:
                        from firebase_admin import messaging
                        tokens = [t[1] for t in targets]
                        msg = messaging.MulticastMessage(
                            notification=messaging.Notification(title=title, body=body),
                            data={'type': 'game_start', 'game_id': str(game_id)},
                            tokens=tokens,
                        )
                        messaging.send_each_for_multicast(msg)
                except Exception as e:
                    print(f"[FCM] 경기전 알림 발송 오류: {e}")

                print(f"[pregame] {label} 전 알림: {away_team} vs {home_team} → {len(user_ids)}명")
        cur.close()
    except Exception as e:
        print(f"[pregame_notif] 오류: {e}")
    finally:
        conn.close()



def _recover_missed_daily_stats():
    """서버 재시작 후 최근 2일 내 누락된 daily stats 복구"""
    from datetime import date as _date_cls, timedelta
    today = _date_cls.today()
    for days_back in range(0, 2):
        check_date = today - timedelta(days=days_back)
        conn = get_connection()
        if not conn:
            continue
        cur = conn.cursor()
        cur.execute('SELECT COUNT(*) FROM games WHERE game_date = %s AND status = %s', (check_date, '종료'))
        game_count = cur.fetchone()[0]
        if not game_count:
            cur.close()
            conn.close()
            continue
        cur.execute('SELECT COUNT(*) FROM player_daily_stats WHERE game_date = %s', (check_date,))
        daily_count = cur.fetchone()[0]
        cur.close()
        conn.close()
        if daily_count == 0:
            print(f'[recovery] {check_date} daily_stats 누락 → 복구 실행')
            _save_player_daily_stats_today(target_date=check_date)
        else:
            print(f'[recovery] {check_date} daily_stats OK ({daily_count}건)')


def run_scheduler():
    print("PlayBall 스케줄러 시작!")
    try:
        _recover_missed_daily_stats()
    except Exception as e:
        print(f'[recovery] 오류: {e}')

    # 30초마다 (UTC 01:00~15:00에만 동작)
    schedule.every(30).seconds.do(smart_update)

    # 매일 UTC 01:00 (KST 10:00): 네이버 선수 통계
    schedule.every().day.at("01:00").do(update_player_stats)

    # 매일 UTC 15:00 (KST 00:00): 자정 기록/팀순위 + KBO 선수 스탯
    schedule.every().day.at("15:00").do(update_finished_game_records)
    schedule.every().day.at("15:00").do(update_team_rankings)
    schedule.every().monday.at("15:00").do(update_kbo_player_stats)  # KST 월요일 00:00

    # 매일 UTC 00:30 (KST 09:30): 등록말소 크롤링
    schedule.every().day.at("00:30").do(_update_roster_changes)

    # 매일 UTC 15:30 (KST 00:30): 예측 정확도 평가 + 일별 집계 + 오늘 로깅 + 재학습
    def _prediction_daily():
        try:
            from api.prediction.eval import daily_pipeline
            daily_pipeline()
        except Exception as e:
            print(f"[prediction] daily_pipeline 오류: {e}")
    schedule.every().day.at("15:30").do(_prediction_daily)

    # 매일 UTC 15:40 (KST 00:40): 즐겨찾기 선수 이벤트 처리
    def _player_events_daily():
        try:
            from crawler.crawl_player_events import (
                ensure_tables, daily_player_summary, hitting_streak_check,
                crawl_transactions, crawl_injury_list, notify_pending,
            )
            ensure_tables()
            daily_player_summary()
            hitting_streak_check()
            crawl_transactions()
            crawl_injury_list()
            notify_pending()
            from crawler.crawl_player_events import check_allstar_vote_events
            check_allstar_vote_events()
        except Exception as e:
            print(f"[player-events] daily 오류: {e}")
    schedule.every().day.at("15:40").do(_player_events_daily)

    # 시상/올스타 — 시즌 이벤트 (월별 트리거: 7월 올스타, 11월 시상식)
    def _player_events_seasonal():
        try:
            from datetime import datetime as _dt
            from crawler.crawl_player_events import (
                ensure_tables, crawl_awards, crawl_allstars, notify_pending,
            )
            ensure_tables()
            month_kst = (_dt.utcnow().month + (1 if _dt.utcnow().hour >= 15 else 0)) % 12 or 12
            # 7월 (올스타 발표)
            if month_kst == 7:
                crawl_allstars()
            # 11월 (시상식)
            if month_kst == 11:
                crawl_awards()
            notify_pending()
        except Exception as e:
            print(f"[player-events] seasonal 오류: {e}")
    # 매일 UTC 15:50 (KST 00:50): 시상/올스타 (해당 월만 작동)
    schedule.every().day.at("15:50").do(_player_events_seasonal)

    # 매시간: 오늘 예측 로깅 (스케줄 변경 대응 — 선발 변경 시 갱신)
    def _prediction_hourly_log():
        try:
            from api.prediction.eval import log_today_predictions
            log_today_predictions()
        except Exception as e:
            print(f"[prediction] hourly log 오류: {e}")
    schedule.every(1).hours.do(_prediction_hourly_log)

    # 매주 월요일 UTC 03:00: 시즌 일정
    schedule.every().monday.at("03:00").do(update_season_schedule)

    # 매시간: 좀비 크롬 정리
    schedule.every(1).hours.do(kill_zombie_chrome)

    # 매시간: 팀 뉴스 크롤링
    schedule.every(1).hours.do(_crawl_news_hourly)

    # 6시간마다: 하이라이트 크롤링 (YouTube API quota 절감)
    schedule.every(6).hours.do(_crawl_highlights_hourly)

    # 15분마다: 크롤러 헬스체크
    schedule.every(15).minutes.do(_health_check)

    # 5분마다: 경기 시작 전 알림 (30분/1시간/2시간 전)
    schedule.every(5).minutes.do(_send_pregame_notifications)

    print("스케줄 등록 완료!")
    print("- 30초마다 (UTC 01:00~15:00 = KST 10:00~00:00): 경기 상태/이닝/선수/투구 업데이트")
    print("- start_time 2시간 전: 로스터 크롤링 (후보야수/불펜)")
    print("- start_time 1시간 전 ~ 경기 시작: 선발 타자 없으면 10분마다 재크롤링")
    print("- 진행 중 선발 타자 없으면 10분마다 재크롤링")
    print("- 경기 종료 감지: 팀순위 즉시 + 10분 후 기록 업데이트")
    print("- UTC 01:00 (KST 10:00): 네이버 선수 통계 업데이트")
    print("- UTC 15:00 (KST 00:00): 자정 기록/팀순위 정기 업데이트")
    print("- 매주 월요일 UTC 15:00 (KST 00:00): KBO 전체 선수 스탯 업데이트")
    print("- 매주 월요일 UTC 03:00: 시즌 일정 업데이트")
    print("- 매시간: 좀비 크롬 정리")

    while True:
        schedule.run_pending()
        time.sleep(10)


if __name__ == "__main__":
    print("=== 즉시 실행 테스트 ===")
    try:
        _update_today_games()
        update_team_rankings()
        update_finished_game_records()
    except Exception as e:
        print(f"초기 실행 오류: {e}")
    run_scheduler()