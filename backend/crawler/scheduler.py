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

_game_hr_cache: dict = {}  # {game_id: {player_id: hr_count}} — HR 중복 알림 방지
_starter_ko_sent: set = set()  # (game_id, player_id) — 조기강판 중복 알림 방지


def _parse_ip(ip_val) -> float:
    """이닝수 파싱: "6.2" → 6.67 (6이닝 2아웃)"""
    try:
        parts = str(ip_val).strip().split('.')
        inn = int(parts[0]) if parts[0] else 0
        outs = int(parts[1]) if len(parts) > 1 and parts[1] else 0
        return inn + outs / 3
    except Exception:
        return 0.0

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

    prev_hrs = _game_hr_cache.get(game_id, {})
    curr_hrs: dict = {}
    new_hr_players = []
    for player_id, hr_count, player_name, team_name in rows:
        curr_hrs[player_id] = hr_count
        if hr_count > prev_hrs.get(player_id, 0):
            new_hr_players.append((player_id, player_name, team_name))
    _game_hr_cache[game_id] = curr_hrs

    if not new_hr_players:
        return
    try:
        from api.fcm_service import notify_fav_hr
        for player_id, player_name, team_name in new_hr_players:
            notify_fav_hr(player_id, player_name, team_name, game_id)
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
                   gb.hits as g_hits, gb.home_runs as g_hr, gb.rbi as g_rbi,
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
            GROUP BY gb.player_id, p.name, t.name, gb.hits, gb.home_runs, gb.rbi, gb.stolen_bases
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

        # 해당 경기 팀 소속 타자 (볼넷/득점 포함)
        cur.execute("""
            SELECT bs.player_id, p.name, t.name,
                   bs.home_runs, bs.rbis, bs.hits, bs.stolen_bases,
                   COALESCE(bs.walks, 0), COALESCE(bs.runs, 0)
            FROM game_batters gb
            JOIN batter_stats bs ON bs.player_id = gb.player_id AND bs.season = %s
            JOIN players p ON p.id = gb.player_id
            JOIN teams t ON t.id = p.team_id
            WHERE gb.game_id = %s
        """, (season, game_id))
        batters = cur.fetchall()

        # 해당 경기 투수
        cur.execute("""
            SELECT ps.player_id, p.name, t.name,
                   ps.wins, ps.strikeouts, ps.saves, ps.holds
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

        # ── 완봉/완봉승/노히터 ──
        for row in starters_cg:
            pid, pname, tname = row[0], row[1], row[2]
            ip_str, er, ha = row[3], row[4] or 0, row[5] or 0
            if _parse_ip(ip_str) >= 9.0:
                notify_milestone(pid, pname, tname, 'game_cg', 1, season, month, game_id)
                if er == 0:
                    notify_milestone(pid, pname, tname, 'game_shutout', 1, season, month, game_id)
                if ha == 0:
                    notify_milestone(pid, pname, tname, 'game_no_hitter', 1, season, month, game_id)

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
        for row in batters:
            pid, pname, tname = row[0], row[1], row[2]
            vals = {'season_hr': row[3] or 0, 'season_rbi': row[4] or 0,
                    'season_hits': row[5] or 0, 'season_sb': row[6] or 0,
                    'season_bb': row[7] or 0, 'season_runs': row[8] or 0}
            for mtype, thresholds in BATTER_SEASON.items():
                for t in thresholds:
                    if vals[mtype] >= t:
                        notify_milestone(pid, pname, tname, mtype, t, season, month, game_id)
            # 최연소 체크
            age = _age(pid)
            if age and age <= 25:
                for mtype, min_val in YOUNG_BATTER_SEASON.items():
                    if vals[mtype] >= min_val:
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
        for row in pitchers:
            pid, pname, tname = row[0], row[1], row[2]
            vals = {'season_wins': row[3] or 0, 'season_so': row[4] or 0,
                    'season_saves': row[5] or 0, 'season_holds': row[6] or 0}
            for mtype, thresholds in PITCHER_SEASON.items():
                for t in thresholds:
                    if vals[mtype] >= t:
                        notify_milestone(pid, pname, tname, mtype, t, season, month, game_id)
            age = _age(pid)
            if age and age <= 25:
                for mtype, min_val in YOUNG_PITCHER_SEASON.items():
                    if vals[mtype] >= min_val:
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
                for row in career_batters:
                    pid, pname, tname = row[0], row[1], row[2]
                    cvals = {'career_hits': row[3], 'career_hr': row[4],
                             'career_rbi': row[5], 'career_sb': row[6], 'career_bb': row[7]}
                    for mtype, thresholds in CAREER_BATTER.items():
                        for t in thresholds:
                            if cvals[mtype] >= t:
                                notify_milestone(pid, pname, tname, mtype, t, season, 0, game_id)
                    # 25세 이하 통산 100홈런/1000안타
                    age = _age(pid)
                    if age and age <= 25:
                        if cvals['career_hr'] >= 100:
                            notify_milestone(pid, pname, tname, 'young_career_hr', 100,
                                             season, 0, game_id, extra_label=f"{age}세")
                        if cvals['career_hits'] >= 1000:
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
                for row in career_pitchers:
                    pid, pname, tname = row[0], row[1], row[2]
                    cvals = {'career_wins': row[3], 'career_so': row[4],
                             'career_saves': row[5], 'career_holds': row[6]}
                    for mtype, thresholds in CAREER_PITCHER.items():
                        for t in thresholds:
                            if cvals[mtype] >= t:
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


def _check_starter_ko(game_id: int, game_info: dict):
    """선발투수 5이닝 미만 강판 감지 → 즉시 알림 (진행 중 실시간 체크, 중복 방지)"""
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        # has_relief: 같은 팀 구원투수가 이미 등판했는지 확인 (선발 강판 확정 조건)
        cur.execute("""
            SELECT gp.player_id, p.name, gp.innings_pitched, gp.team_side,
                   EXISTS(
                       SELECT 1 FROM game_pitchers gp2
                       WHERE gp2.game_id = gp.game_id
                         AND gp2.team_side = gp.team_side
                         AND gp2.pitching_order > 1
                   ) as has_relief
            FROM game_pitchers gp
            JOIN players p ON p.id = gp.player_id
            WHERE gp.game_id = %s AND gp.pitching_order = 1
        """, (game_id,))
        starters = cur.fetchall()
        cur.close()
    except Exception:
        return
    finally:
        conn.close()

    if not starters:
        return

    try:
        from api.fcm_service import notify_starter_ko
        for player_id, name, ip, side, has_relief in starters:
            if (game_id, player_id) in _starter_ko_sent:
                continue  # 이미 알림 발송
            if not has_relief:
                continue  # 구원 등판 전 → 아직 선발이 마운드
            parsed = _parse_ip(ip)
            if 0 < parsed < 5.0:
                team_name = game_info.get('home_team') if side == 'home' else game_info.get('away_team')
                notify_starter_ko(game_id, name, team_name or '',
                                  str(ip) if ip else '0',
                                  game_info.get('home_team_id', 0),
                                  game_info.get('away_team_id', 0))
                _starter_ko_sent.add((game_id, player_id))
                print(f"[FCM] 선발 조기강판 알림: {name} {ip}이닝 (game_id={game_id})")
    except Exception as e:
        print(f"[FCM] 조기강판 알림 오류: {e}")


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
                notify_game_start, notify_score_change, notify_game_end,
                notify_extra_innings, notify_game_cancelled, notify_streak,
            )
            for gid, curr in curr_details.items():
                prev = prev_details.get(gid, {})
                cs, ps = curr['status'], prev.get('status', '')

                # 우천취소
                if cs == '취소' and ps not in ('취소', ''):
                    notify_game_cancelled(gid, curr['home_team'], curr['away_team'],
                                          curr['home_team_id'], curr['away_team_id'])
                    continue

                # 경기 시작
                if cs == '진행' and ps in ('예정', '라인업', ''):
                    # 선발 투수 조회
                    _hs = _ls = ''
                    try:
                        _c2 = get_connection()
                        if _c2:
                            _cur2 = _c2.cursor()
                            _cur2.execute("""
                                SELECT p.name, gp.side FROM game_pitchers gp
                                JOIN players p ON p.id = gp.player_id
                                WHERE gp.game_id = %s AND gp.pitch_order = 1
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

                # 득점 변화
                elif (cs == '진행' and ps == '진행' and
                      (curr['home_score'] != prev.get('home_score', 0) or
                       curr['away_score'] != prev.get('away_score', 0))):
                    ph, pa = prev.get('home_score', 0), prev.get('away_score', 0)
                    ch, ca = curr['home_score'], curr['away_score']
                    # 역전: 득점 전 앞서던 팀이 뒤처짐
                    is_comeback = ((ph > pa and ch < ca) or (pa > ph and ca < ch))
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
                    notify_score_change(gid, curr['home_team'], curr['away_team'],
                                        ch, ca,
                                        curr['home_team_id'], curr['away_team_id'],
                                        is_comeback=is_comeback,
                                        inning=inning_now,
                                        inning_half=curr.get('inning_half', ''),
                                        scoring_team=scoring_team,
                                        runs=runs_scored,
                                        batter=batter, pitcher=pitcher, play_text=play_text,
                                        stuff=stuff, speed=speed, homein=homein,
                                        pitch_num=pitch_num)
                    _check_new_hrs(gid, curr['home_team_id'], curr['away_team_id'])
                    _check_game_milestones(gid)

                # 경기 종료
                elif cs == '종료' and ps == '진행':
                    notify_game_end(gid, curr['home_team'], curr['away_team'],
                                    curr['home_score'], curr['away_score'],
                                    curr['home_team_id'], curr['away_team_id'])

                # 연장전 돌입 (별도 체크)
                prev_inn = prev.get('current_inning', 0) or 0
                curr_inn = curr.get('current_inning', 0) or 0
                if cs == '진행' and curr_inn >= 10 and prev_inn < 10:
                    notify_extra_innings(gid, curr['home_team'], curr['away_team'],
                                         curr_inn,
                                         curr['home_team_id'], curr['away_team_id'])

                # 진행 중 선발 조기강판 실시간 체크 (구원 등판 즉시 감지)
                if cs == '진행':
                    try:
                        _check_starter_ko(gid, curr)
                    except Exception:
                        pass

        except Exception as fcm_err:
            print(f"[FCM] 알림 처리 오류: {fcm_err}")

        if newly_finished:
            print(f"[{datetime.now()}] 경기 {len(newly_finished)}개 종료 감지 → 팀순위 업데이트")
            finished_team_ids = set()
            for gid in newly_finished:
                conn_tmp = get_connection()
                if conn_tmp:
                    cur_tmp = conn_tmp.cursor()
                    cur_tmp.execute(
                        "SELECT naver_game_id, current_inning, home_team_id, away_team_id FROM games WHERE id = %s", (gid,)
                    )
                    row_tmp = cur_tmp.fetchone()
                    cur_tmp.close()
                    conn_tmp.close()
                    if row_tmp and row_tmp[1]:
                        save_game_pitches(gid, row_tmp[0], row_tmp[1])
                        # 투구 위치 데이터 저장
                        try:
                            from crawler.crawl_pitch_locations import save_pitch_locations_for_game
                            max_inn = int(row_tmp[1])
                            n = save_pitch_locations_for_game(gid, row_tmp[0], max_inn)
                            print(f"[{datetime.now()}] pitch_locations 저장: game_id={gid} {n}구")
                        except Exception as pl_err:
                            print(f"[{datetime.now()}] pitch_locations 오류: {pl_err}")
                        if row_tmp[2]: finished_team_ids.add(row_tmp[2])
                        if row_tmp[3]: finished_team_ids.add(row_tmp[3])
            update_team_rankings()
            schedule.every(10).minutes.do(_run_once, update_finished_game_records)
            schedule.every(15).minutes.do(_run_once, update_finished_player_stats)
            # 경기 종료 25분 후 출전 선수 KBO 크롤
            for gid in newly_finished:
                schedule.every(25).minutes.do(_run_once, _crawl_kbo_stats_for_game, gid)
            # 경기 종료 팀 뉴스 크롤링
            if finished_team_ids:
                try:
                    from crawler.crawl_naver_news import crawl_news_for_teams
                    crawl_news_for_teams(list(finished_team_ids))
                except Exception as news_err:
                    print(f"[{datetime.now()}] 뉴스 크롤링 오류: {news_err}")
            # 경기 종료 하이라이트 크롤링
            for gid in newly_finished:
                try:
                    from crawler.crawl_highlights import crawl_highlights_for_game
                    crawl_highlights_for_game(gid)
                except Exception as hl_err:
                    print(f"[{datetime.now()}] 하이라이트 크롤링 오류: {hl_err}")

            # 연승/연패 알림 (5연승/5연패 이상, 이후 1씩 증가마다)
            try:
                from api.fcm_service import notify_streak
                for team_id in finished_team_ids:
                    streak = _get_consecutive_record(team_id)
                    if abs(streak) >= 5:
                        conn_s = get_connection()
                        if conn_s:
                            cur_s = conn_s.cursor()
                            cur_s.execute("SELECT name FROM teams WHERE id = %s", (team_id,))
                            row_s = cur_s.fetchone()
                            cur_s.close(); conn_s.close()
                            if row_s:
                                notify_streak(team_id, row_s[0], abs(streak), streak > 0)
            except Exception as streak_err:
                print(f"[FCM] 연승/연패 알림 오류: {streak_err}")

        # 끝내기 승리 알림
        for gid in newly_finished:
            try:
                curr = curr_details.get(gid, {})
                if curr.get('home_score', 0) > curr.get('away_score', 0) and _is_walkoff(gid):
                    from api.fcm_service import notify_walkoff
                    notify_walkoff(gid, curr['home_team'], curr['away_team'],
                                   curr['home_score'], curr['away_score'],
                                   curr['home_team_id'], curr['away_team_id'])
            except Exception as wo_err:
                print(f"[FCM] 끝내기 알림 오류: {wo_err}")

        # 선발 조기강판 알림
        for gid in newly_finished:
            try:
                _check_starter_ko(gid, curr_details.get(gid, {}))
            except Exception as ko_err:
                print(f"[FCM] 조기강판 알림 오류: {ko_err}")

        # 경기 종료 후 시즌 마일스톤 (stats 업데이트 후 25분 지연 실행)
        for gid in newly_finished:
            schedule.every(27).minutes.do(_run_once, _check_post_game_milestones, gid)

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
        for (db_game_id, naver_game_id) in games_no_lineup:
            save_game_roster(db_game_id, naver_game_id)
            time.sleep(0.5)


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
            time.sleep(0.5)


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
               TO_CHAR(g.start_time, 'HH24:MI'), g.naver_game_id
        FROM games g
        JOIN teams ht ON g.home_team_id = ht.id
        JOIN teams at2 ON g.away_team_id = at2.id
        WHERE g.game_date = CURRENT_DATE
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
    """Naver 중계 API에서 득점 타자/투수/타구/투구내용 추출. 실패 시 ('','','','',0,[],0) 반환"""
    import requests, re as _re
    HEADERS = {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://sports.naver.com/'}
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
        curr_pitch_num = 0  # 현재 타자의 투구 카운트

        # 마지막 type=1 이벤트 저장 (score 업데이트는 후속 이벤트에서 일어남)
        last_batter = last_pitcher = last_text = last_stuff = ''
        last_speed = 0
        last_pitch_num = 0

        result_batter = result_pitcher = result_text = result_stuff = ''
        result_speed = 0
        result_pitch_num = 0
        result_homein = []
        found_scoring = False
        done = False

        for item in text_relays:
            if done:
                break
            for opt in item.get('textOptions', []):
                state = opt.get('currentGameState', {}) or {}

                pid = str(state.get('pitcher') or '')
                if pid and cur:
                    if pid not in pitcher_cache:
                        cur.execute("SELECT name FROM players WHERE naver_player_id=%s LIMIT 1", (pid,))
                        row = cur.fetchone()
                        pitcher_cache[pid] = row[0] if row else ''
                    curr_pitcher = pitcher_cache.get(pid, '')

                br = opt.get('batterRecord') or {}
                if br.get('name'):
                    if br['name'] != curr_batter:
                        curr_pitch_num = 0  # 새 타자 → 투구 카운트 리셋
                    curr_batter = br['name']
                elif opt.get('type') == 8:
                    m = _re.match(r'^(?:\d+번타자|대타)\s+(\S+)', opt.get('text', ''))
                    if m:
                        if m.group(1) != curr_batter:
                            curr_pitch_num = 0
                        curr_batter = m.group(1)
                    if found_scoring:
                        done = True
                        break  # 다음 타자 시작 → homeIn 수집 종료

                if opt.get('stuff'):
                    curr_stuff = opt.get('stuff', '')
                    curr_speed = int(opt.get('speed', 0) or 0)

                # 투구 이벤트(type=1) 저장 → 득점 감지 시 사용
                # (Naver는 스코어를 type=1 직후 이벤트에서 업데이트하므로 last_* 보관)
                if opt.get('type') == 1:
                    curr_pitch_num += 1
                    last_batter = curr_batter
                    last_pitcher = curr_pitcher
                    last_text = opt.get('text', '')
                    last_stuff = opt.get('stuff', '') or curr_stuff
                    last_speed = int(opt.get('speed', 0) or 0) or curr_speed
                    last_pitch_num = curr_pitch_num

                hs = state.get('homeScore')
                aws = state.get('awayScore')
                if hs is not None and aws is not None:
                    if int(hs) >= new_home_score and int(aws) >= new_away_score:
                        if not found_scoring and last_text:
                            result_batter = last_batter
                            result_pitcher = last_pitcher
                            result_text = last_text
                            result_stuff = last_stuff
                            result_speed = last_speed
                            result_pitch_num = last_pitch_num
                            found_scoring = True

                # 홈인 수집 (type 14/24): 득점 감지 시점 포함 이후
                if found_scoring and opt.get('type') in (14, 24):
                    txt = opt.get('text', '')
                    m2 = _re.search(r'([가-힣A-Za-z]+)\s*홈인', txt)
                    if m2 and m2.group(1) not in result_homein:
                        result_homein.append(m2.group(1))

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
                time.sleep(0.5)

    update_team_rankings()
    print(f"[{datetime.now()}] 상세 기록 업데이트 완료")


def update_team_rankings():
    print(f"[{datetime.now()}] 팀 순위 업데이트")
    prev_ranks = _get_rankings_snapshot()
    teams = get_team_rankings(2026)
    save_team_rankings(teams)
    curr_ranks = _get_rankings_snapshot()
    # 순위 변동 알림
    try:
        from api.fcm_service import notify_rank_change
        for team_id, curr in curr_ranks.items():
            prev = prev_ranks.get(team_id, {})
            old_r, new_r = prev.get('rank'), curr['rank']
            if old_r and new_r and old_r != new_r:
                notify_rank_change(team_id, curr['name'], old_r, new_r,
                                   curr.get('games_behind') or 0)
    except Exception as e:
        print(f"[FCM] 순위 알림 오류: {e}")

    # 1위 마이팀 추격전 알림 (2위와 게임차 좁혀질 때)
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
                    notify_pennant_race(first_tid, first_data['name'], curr_gap, prev_gap)
    except Exception as e:
        print(f"[FCM] 페넌트레이스 알림 오류: {e}")

    # 게임차 0 달성 알림 (새로 동률 1위가 된 팀)
    try:
        from api.fcm_service import notify_gb_zero
        first_name = next((d['name'] for d in curr_ranks.values() if d.get('rank') == 1), '')
        for team_id, curr in curr_ranks.items():
            if curr.get('rank', 99) <= 1:
                continue
            prev = prev_ranks.get(team_id, {})
            old_gb = prev.get('games_behind')
            new_gb = curr.get('games_behind')
            if old_gb and float(old_gb) > 0 and new_gb is not None and float(new_gb) == 0:
                notify_gb_zero(team_id, curr['name'], first_name)
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
                  AND g.start_time >= (CURRENT_TIME AT TIME ZONE 'Asia/Seoul')
                                      + (%s * INTERVAL '1 minute')
                                      - INTERVAL '2 minutes 30 seconds'
                  AND g.start_time <  (CURRENT_TIME AT TIME ZONE 'Asia/Seoul')
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

    # 매주 월요일 UTC 03:00: 시즌 일정
    schedule.every().monday.at("03:00").do(update_season_schedule)

    # 매시간: 좀비 크롬 정리
    schedule.every(1).hours.do(kill_zombie_chrome)

    # 매시간: 팀 뉴스 크롤링
    schedule.every(1).hours.do(_crawl_news_hourly)

    # 매시간: 하이라이트 크롤링
    schedule.every(1).hours.do(_crawl_highlights_hourly)

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