import schedule
import time
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

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
    """선발투수 5이닝 미만 강판 감지 → 알림"""
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT gp.player_id, p.name, gp.innings_pitched, gp.team_side
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

    def _parse_ip(ip_val) -> float:
        try:
            parts = str(ip_val).strip().split('.')
            inn = int(parts[0]) if parts[0] else 0
            outs = int(parts[1]) if len(parts) > 1 and parts[1] else 0
            return inn + outs / 3
        except Exception:
            return 0.0

    try:
        from api.fcm_service import notify_starter_ko
        for player_id, name, ip, side in starters:
            parsed = _parse_ip(ip)
            if 0 < parsed < 5.0:
                team_name = game_info.get('home_team') if side == 'home' else game_info.get('away_team')
                notify_starter_ko(game_id, name, team_name or '',
                                  str(ip) if ip else '0',
                                  game_info.get('home_team_id', 0),
                                  game_info.get('away_team_id', 0))
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
                    notify_game_start(gid, curr['home_team'], curr['away_team'],
                                      curr['home_team_id'], curr['away_team_id'])

                # 득점 변화
                elif (cs == '진행' and ps == '진행' and
                      (curr['home_score'] != prev.get('home_score', 0) or
                       curr['away_score'] != prev.get('away_score', 0))):
                    ph, pa = prev.get('home_score', 0), prev.get('away_score', 0)
                    ch, ca = curr['home_score'], curr['away_score']
                    # 역전: 득점 전 앞서던 팀이 뒤처짐
                    is_comeback = ((ph > pa and ch < ca) or (pa > ph and ca < ch))
                    notify_score_change(gid, curr['home_team'], curr['away_team'],
                                        ch, ca,
                                        curr['home_team_id'], curr['away_team_id'],
                                        is_comeback=is_comeback)
                    _check_new_hrs(gid, curr['home_team_id'], curr['away_team_id'])

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
          AND EXTRACT(YEAR FROM game_date) = 2026
          GROUP BY player_id
        ) sub
        WHERE bs.player_id = sub.player_id
        AND bs.season = 2026
    """)
    updated = cur.rowcount
    conn.commit()
    cur.close()
    conn.close()
    print(f"[{datetime.now()}] batter_stats daily 동기화 완료 ({updated}명)")


def _save_player_daily_stats_today():
    """오늘 종료 경기의 player_daily_stats 업데이트 (game_batters/game_pitchers 기반)"""
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
        WHERE g.game_date = CURRENT_DATE
        AND g.status = '종료'
    """)
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
            opponent = away_team if side == 'home' else home_team
            result = home_result if side == 'home' else away_result
            cur.execute("""
                INSERT INTO player_daily_stats (
                    player_id, game_date, opponent, result, stat_type,
                    avg, ab, runs, hits, home_runs, rbi, sb, walks, strikeouts
                ) VALUES (%s, %s, %s, %s, 'hitter', %s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (player_id, game_date, opponent, stat_type) DO UPDATE SET
                    result = EXCLUDED.result,
                    avg = EXCLUDED.avg,
                    ab = EXCLUDED.ab,
                    runs = EXCLUDED.runs,
                    hits = EXCLUDED.hits,
                    home_runs = EXCLUDED.home_runs,
                    rbi = EXCLUDED.rbi,
                    sb = EXCLUDED.sb,
                    walks = EXCLUDED.walks,
                    strikeouts = EXCLUDED.strikeouts
            """, (pid, game_date, opponent, result, avg, ab, runs, hits, hr, rbi, sb, bb, so))
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
               COALESCE(g.current_inning, 0)
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
            'status':       r[1],
            'home_score':   r[2] or 0,
            'away_score':   r[3] or 0,
            'home_team':    r[4],
            'away_team':    r[5],
            'home_team_id': r[6],
            'away_team_id': r[7],
            'current_inning': r[8] or 0,
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


def _notify_roster_for_fans():
    """오늘 등록말소 중 즐겨찾기 선수 → 팬에게 알림"""
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT player_id, player_name, change_type
            FROM player_roster_changes
            WHERE change_date = CURRENT_DATE
              AND player_id IS NOT NULL
              AND change_type IN ('1군 등록', '1군 말소')
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
        from api.fcm_service import notify_roster_change
        for player_id, player_name, change_type in rows:
            notify_roster_change(player_id, player_name, change_type)
    except Exception as e:
        print(f"[FCM] 로스터 알림 오류: {e}")


def _run_once(func):
    func()
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
            # 2위 games_behind 비교 (prev vs curr)
            sec_curr = [d for d in curr_ranks.values() if d.get('rank') == 2]
            sec_prev = [d for d in prev_ranks.values() if d.get('rank') == 2]
            if sec_curr and sec_prev:
                curr_gap = float(sec_curr[0].get('games_behind') or 0)
                prev_gap = float(sec_prev[0].get('games_behind') or 0)
                if curr_gap < prev_gap and curr_gap >= 0:
                    notify_pennant_race(first_tid, first_data['name'], curr_gap, prev_gap)
    except Exception as e:
        print(f"[FCM] 페넌트레이스 알림 오류: {e}")


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


def update_kbo_player_stats():
    """KBO 사이트에서 선수 2026 시즌 스탯 업데이트"""
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

    print(f"[{datetime.now()}] KBO 선수 스탯 업데이트 시작")

    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
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


def run_scheduler():
    print("PlayBall 스케줄러 시작!")

    # 1분마다 (UTC 01:00~15:00에만 동작)
    schedule.every(1).minutes.do(smart_update)

    # 매일 UTC 01:00 (KST 10:00): 네이버 선수 통계
    schedule.every().day.at("01:00").do(update_player_stats)

    # 매일 UTC 15:00 (KST 00:00): 자정 기록/팀순위 + KBO 선수 스탯
    schedule.every().day.at("15:00").do(update_finished_game_records)
    schedule.every().day.at("15:00").do(update_team_rankings)
    schedule.every().day.at("15:30").do(update_kbo_player_stats)

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

    print("스케줄 등록 완료!")
    print("- 1분마다 (UTC 01:00~15:00 = KST 10:00~00:00): 경기 상태/이닝/선수/투구 업데이트")
    print("- start_time 2시간 전: 로스터 크롤링 (후보야수/불펜)")
    print("- start_time 1시간 전 ~ 경기 시작: 선발 타자 없으면 10분마다 재크롤링")
    print("- 진행 중 선발 타자 없으면 10분마다 재크롤링")
    print("- 경기 종료 감지: 팀순위 즉시 + 10분 후 기록 업데이트")
    print("- UTC 01:00 (KST 10:00): 네이버 선수 통계 업데이트")
    print("- UTC 15:00 (KST 00:00): 자정 기록/팀순위 정기 업데이트")
    print("- UTC 15:30 (KST 00:30): KBO 선수 스탯 업데이트")
    print("- 매주 월요일 UTC 03:00: 시즌 일정 업데이트")
    print("- 매시간: 좀비 크롬 정리")

    while True:
        schedule.run_pending()
        time.sleep(30)


if __name__ == "__main__":
    print("=== 즉시 실행 테스트 ===")
    try:
        _update_today_games()
        update_team_rankings()
        update_finished_game_records()
    except Exception as e:
        print(f"초기 실행 오류: {e}")
    run_scheduler()