"""선수 이벤트 크롤러 — Phase 2/3 알림용.
트랜잭션(트레이드/방출/은퇴/FA), 부상자 명단, 시상식, 올스타.

TODO: 각 함수의 실제 크롤 로직 구현 (Naver/KBO 페이지 분석 필요).
현재 stub — DB 신규 row 감지하면 fcm_service의 notify_* 호출하는 hook만 구비."""
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from database.connection import get_connection


def ensure_tables():
    """이벤트 추적 테이블 생성."""
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS player_transactions (
            id SERIAL PRIMARY KEY,
            player_id INT,
            player_name VARCHAR(50),
            transaction_type VARCHAR(20),
            detail TEXT,
            event_date DATE,
            notified BOOLEAN DEFAULT FALSE,
            crawled_at TIMESTAMPTZ DEFAULT NOW(),
            UNIQUE(player_id, transaction_type, event_date)
        );
        CREATE TABLE IF NOT EXISTS player_injury_list (
            id SERIAL PRIMARY KEY,
            player_id INT,
            player_name VARCHAR(50),
            team_id INT,
            action VARCHAR(20),
            reason TEXT,
            event_date DATE,
            notified BOOLEAN DEFAULT FALSE,
            crawled_at TIMESTAMPTZ DEFAULT NOW(),
            UNIQUE(player_id, action, event_date)
        );
        CREATE TABLE IF NOT EXISTS player_awards (
            id SERIAL PRIMARY KEY,
            player_id INT,
            player_name VARCHAR(50),
            team_id INT,
            award_type VARCHAR(20),
            position VARCHAR(20),
            season INT,
            notified BOOLEAN DEFAULT FALSE,
            crawled_at TIMESTAMPTZ DEFAULT NOW(),
            UNIQUE(player_id, award_type, season)
        );
        CREATE TABLE IF NOT EXISTS player_allstars (
            id SERIAL PRIMARY KEY,
            player_id INT,
            player_name VARCHAR(50),
            team_id INT,
            season INT,
            league VARCHAR(10),
            vote_rank INT,
            notified BOOLEAN DEFAULT FALSE,
            crawled_at TIMESTAMPTZ DEFAULT NOW(),
            UNIQUE(player_id, season)
        );
    """)
    conn.commit()
    cur.close(); conn.close()


def crawl_transactions():
    """Naver 선수 이동/은퇴 페이지 크롤 → player_transactions INSERT.
    TODO: Naver 크롤 로직. 현재 stub — 향후 구현."""
    # 예시 데이터 source: https://sports.news.naver.com/kbaseball/news/index?category=move
    # 기사 제목/본문에서 키워드 감지: "트레이드", "방출", "은퇴 발표", "FA 계약", "FA 선언"
    pass


def crawl_injury_list():
    """KBO 부상자 명단 크롤 → player_injury_list INSERT.
    TODO: KBO 부상자 명단 페이지 분석."""
    # 예시: https://www.koreabaseball.com/Player/IL.aspx (가상)
    pass


def crawl_awards(season: int):
    """KBO 시상식 결과 크롤 → player_awards INSERT.
    매년 11월 시상식 후 1회 실행."""
    # 예시 source: KBO 공식 시상식 페이지
    pass


def crawl_allstars(season: int):
    """올스타 선발 크롤 → player_allstars INSERT.
    매년 7월 중순 발표 후 1회 실행."""
    # 예시 source: KBO 올스타전 페이지
    pass


def notify_pending():
    """notified=FALSE 이벤트들을 알림 발송. crawl_* 호출 후 트리거."""
    from api.fcm_service import (
        notify_player_transaction, notify_injury_list,
        notify_award, notify_allstar,
    )
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()

    # 트랜잭션
    cur.execute("""
        SELECT id, player_id, player_name, transaction_type, detail
        FROM player_transactions WHERE notified=FALSE
    """)
    for tid, pid, pname, ttype, detail in cur.fetchall():
        try:
            notify_player_transaction(pid, pname, ttype, detail or '')
            cur.execute("UPDATE player_transactions SET notified=TRUE WHERE id=%s", (tid,))
        except Exception as e:
            print(f"[event] transaction 알림 실패 id={tid}: {e}")

    # 부상자
    cur.execute("""
        SELECT pil.id, pil.player_id, pil.player_name, t.name, pil.action, pil.reason
        FROM player_injury_list pil
        LEFT JOIN teams t ON t.id = pil.team_id
        WHERE pil.notified=FALSE
    """)
    for iid, pid, pname, tname, action, reason in cur.fetchall():
        try:
            notify_injury_list(pid, pname, tname or '', action, reason or '')
            cur.execute("UPDATE player_injury_list SET notified=TRUE WHERE id=%s", (iid,))
        except Exception as e:
            print(f"[event] injury 알림 실패 id={iid}: {e}")

    # 시상
    cur.execute("""
        SELECT pa.id, pa.player_id, pa.player_name, t.name, pa.award_type, pa.season, pa.position
        FROM player_awards pa
        LEFT JOIN teams t ON t.id = pa.team_id
        WHERE pa.notified=FALSE
    """)
    for aid, pid, pname, tname, atype, season, position in cur.fetchall():
        try:
            notify_award(pid, pname, tname or '', atype, season, position or '')
            cur.execute("UPDATE player_awards SET notified=TRUE WHERE id=%s", (aid,))
        except Exception as e:
            print(f"[event] award 알림 실패 id={aid}: {e}")

    # 올스타
    cur.execute("""
        SELECT pa.id, pa.player_id, pa.player_name, t.name, pa.season, pa.league, pa.vote_rank
        FROM player_allstars pa
        LEFT JOIN teams t ON t.id = pa.team_id
        WHERE pa.notified=FALSE
    """)
    for aid, pid, pname, tname, season, league, vrank in cur.fetchall():
        try:
            notify_allstar(pid, pname, tname or '', season, league or '', vrank or 0)
            cur.execute("UPDATE player_allstars SET notified=TRUE WHERE id=%s", (aid,))
        except Exception as e:
            print(f"[event] allstar 알림 실패 id={aid}: {e}")

    conn.commit()
    cur.close(); conn.close()


def daily_player_summary():
    """매일 자정 — 즐겨찾기된 선수 중 그날 출전한 선수 활약 요약 알림."""
    from api.fcm_service import notify_daily_player_summary
    from datetime import date
    today = date.today()
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    cur.execute("""
        SELECT DISTINCT pds.player_id, p.name, t.name, p.player_type,
               pds.stat_type, pds.hits, pds.at_bats, pds.home_runs, pds.rbi,
               pds.walks, pds.sb, pds.ip, pds.er, pds.so, pds.result
        FROM player_daily_stats pds
        JOIN players p ON p.id = pds.player_id
        LEFT JOIN teams t ON t.id = p.team_id
        WHERE pds.game_date = %s
          AND EXISTS (
            SELECT 1 FROM user_favorite_players ufp
            WHERE ufp.player_id = pds.player_id
          )
    """, (today,))
    rows = cur.fetchall()
    cur.close(); conn.close()
    for r in rows:
        pid, pname, tname, ptype, stype, h, ab, hr, rbi, bb, sb, ip, er, so, result = r
        stats = {
            'hits': h, 'at_bats': ab, 'home_runs': hr, 'rbi': rbi,
            'walks': bb, 'sb': sb, 'ip': ip, 'er': er, 'so': so, 'result': result,
        }
        try:
            notify_daily_player_summary(pid, pname, tname or '', ptype or '타자', stats, today)
        except Exception as e:
            print(f"[daily-summary] 알림 실패 player={pid}: {e}")


def hitting_streak_check():
    """player_daily_stats에서 즐겨찾기 선수 연속 안타 streak 계산 → 8경기 이상 신기록 알림."""
    from api.fcm_service import notify_hitting_streak
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    cur.execute("""
        SELECT pds.player_id, p.name, t.name, pds.game_date, pds.hits, pds.at_bats
        FROM player_daily_stats pds
        JOIN players p ON p.id = pds.player_id
        LEFT JOIN teams t ON t.id = p.team_id
        WHERE pds.stat_type='hitter'
          AND EXISTS (
            SELECT 1 FROM user_favorite_players ufp WHERE ufp.player_id = pds.player_id
          )
        ORDER BY pds.player_id, pds.game_date DESC
    """)
    rows = cur.fetchall()
    cur.close(); conn.close()

    # 선수별 연속 안타 streak 계산
    from collections import defaultdict
    by_player = defaultdict(list)
    for pid, pname, tname, gdate, hits, ab in rows:
        by_player[pid].append((gdate, hits or 0, ab or 0, pname, tname))

    notify_conn = get_connection()
    if not notify_conn:
        return
    ncur = notify_conn.cursor()
    for pid, history in by_player.items():
        # history는 최신순. streak 계산: 연속으로 hits > 0 (ab > 0 조건 포함)
        streak = 0
        latest_pname = ''
        latest_tname = ''
        for gdate, hits, ab, pname, tname in history:
            if ab > 0 and hits > 0:
                streak += 1
                if not latest_pname:
                    latest_pname = pname
                    latest_tname = tname
            else:
                break
        if streak >= 8:
            sub_id = f"{pid}_streak_{streak}"
            ncur.execute("""
                SELECT 1 FROM notification_log
                WHERE game_id=0 AND type='hitting_streak' AND sub_id=%s
            """, (sub_id,))
            if ncur.fetchone():
                continue
            try:
                notify_hitting_streak(pid, latest_pname, latest_tname or '', streak)
                ncur.execute("""
                    INSERT INTO notification_log (game_id, type, sub_id)
                    VALUES (0, 'hitting_streak', %s) ON CONFLICT DO NOTHING
                """, (sub_id,))
            except Exception as e:
                print(f"[streak] 알림 실패 player={pid}: {e}")
    notify_conn.commit()
    ncur.close(); notify_conn.close()


if __name__ == '__main__':
    ensure_tables()
    print("crawl_player_events: 테이블 준비 완료")
