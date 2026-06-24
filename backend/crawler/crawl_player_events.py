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
        CREATE TABLE IF NOT EXISTS allstar_vote_events (
            id SERIAL PRIMARY KEY,
            season INT NOT NULL,
            opens_at DATE NOT NULL,
            closes_at DATE NOT NULL,
            vote_url TEXT,
            notified_open BOOLEAN DEFAULT FALSE,
            notified_d3 BOOLEAN DEFAULT FALSE,
            notified_d1 BOOLEAN DEFAULT FALSE,
            created_at TIMESTAMPTZ DEFAULT NOW(),
            UNIQUE(season)
        );
    """)
    conn.commit()
    cur.close(); conn.close()


_TRANSACTION_KEYWORDS = {
    'trade': ['트레이드', '트레이드 단행', '맞트레이드'],
    'release': ['방출', '방출 통보', '웨이버 공시'],
    'retire': ['은퇴', '은퇴 선언', '은퇴 발표', '현역 은퇴'],
    'fa_signed': ['FA 계약', 'FA 잔류', 'FA 영입'],
    'fa_filed': ['FA 신청', 'FA 자격', 'FA 선언'],
}


def _match_player_in_title(title: str, players_cache: dict) -> tuple[int, str] | None:
    """제목에서 선수명 매칭 → (player_id, name) 반환. 동명이인은 처음 매칭만."""
    for name, pid in players_cache.items():
        if name in title:
            return pid, name
    return None


def _classify_transaction(text: str) -> str | None:
    """제목/본문에서 트랜잭션 타입 추론. 우선순위 적용."""
    for ttype, keywords in _TRANSACTION_KEYWORDS.items():
        for kw in keywords:
            if kw in text:
                return ttype
    return None


def crawl_transactions():
    """Google News RSS로 KBO 선수 이동 기사 검색 → player_transactions INSERT.
    재시도 시점에 notified=FALSE 새 row를 notify_pending이 발송."""
    from datetime import date
    from crawler.crawl_naver_news import fetch_rss
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    cur.execute("SELECT id, name FROM players WHERE name IS NOT NULL AND LENGTH(name) >= 2")
    rows = cur.fetchall()
    # 짧은 이름 우선순위 낮춰 동명이인 매칭 정확도 향상 (긴 이름이 더 unique)
    players_cache = {r[1]: r[0] for r in sorted(rows, key=lambda x: -len(x[1]))}
    cur.close(); conn.close()

    # 트랜잭션 키워드 결합으로 1회 RSS 조회 (Google이 OR 검색 지원)
    queries = [
        'KBO 트레이드', 'KBO 방출', 'KBO 은퇴',
        'KBO FA 계약', 'KBO FA 신청',
    ]
    inserted = 0
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    today = date.today()

    from datetime import timedelta
    cutoff = today - timedelta(days=7)
    for q in queries:
        articles = fetch_rss(q)
        for art in articles:
            title = art.get('title', '')
            if not title:
                continue
            ttype = _classify_transaction(title)
            if not ttype:
                continue
            # 기사 발행일 7일 이상 지났으면 skip — 오래된 뉴스 재알림 방지 (강백호 FA 사례)
            pub = art.get('published_at')
            if pub:
                pub_date = pub.date() if hasattr(pub, 'date') else None
                if pub_date and pub_date < cutoff:
                    continue
            matched = _match_player_in_title(title, players_cache)
            if not matched:
                continue
            pid, pname = matched
            # event_date = 기사 발행일 우선, 없으면 today
            evt_date = pub.date() if pub and hasattr(pub, 'date') else today
            try:
                cur.execute("""
                    INSERT INTO player_transactions
                        (player_id, player_name, transaction_type, detail, event_date)
                    VALUES (%s, %s, %s, %s, %s)
                    ON CONFLICT (player_id, transaction_type, event_date) DO NOTHING
                    RETURNING id
                """, (pid, pname, ttype, title[:500], evt_date))
                if cur.fetchone():
                    inserted += 1
            except Exception as e:
                print(f"[transaction] INSERT 오류: {e}")
    conn.commit()
    cur.close(); conn.close()
    if inserted:
        print(f"[transactions] 신규 {inserted}건 감지")


def crawl_injury_list():
    """player_roster_changes 중 1군 말소 + 부상 사유 → player_injury_list 동기화.
    별도 부상 명단 페이지 대신 등록말소 사유 활용 (안정적 + 이미 크롤 중)."""
    from datetime import date, timedelta
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    cutoff = date.today() - timedelta(days=7)
    cur.execute("""
        SELECT prc.player_id, prc.player_name, p.team_id, prc.change_type,
               prc.reason, prc.change_date
        FROM player_roster_changes prc
        LEFT JOIN players p ON p.id = prc.player_id
        WHERE prc.change_date >= %s AND prc.player_id IS NOT NULL
          AND prc.change_type IN ('1군 등록', '1군 말소')
    """, (cutoff,))
    rows = cur.fetchall()
    inserted = 0
    for pid, pname, team_id, ctype, reason, gdate in rows:
        action = None
        if ctype == '1군 말소' and reason and any(
            kw in reason for kw in ['부상', '컨디션', '회복']
        ):
            action = 'listed'
        elif ctype == '1군 등록' and reason and '복귀' in reason:
            action = 'returned'
        if not action:
            continue
        try:
            cur.execute("""
                INSERT INTO player_injury_list
                    (player_id, player_name, team_id, action, reason, event_date)
                VALUES (%s, %s, %s, %s, %s, %s)
                ON CONFLICT (player_id, action, event_date) DO NOTHING
                RETURNING id
            """, (pid, pname, team_id, action, reason[:200] if reason else '', gdate))
            if cur.fetchone():
                inserted += 1
        except Exception as e:
            print(f"[injury] INSERT 오류: {e}")
    conn.commit()
    cur.close(); conn.close()
    if inserted:
        print(f"[injury] 신규 {inserted}건 감지")


_AWARD_KEYWORDS = {
    'mvp': ['정규시즌 MVP', '시즌 MVP'],
    'rookie': ['신인왕', '올해의 신인'],
    'goldenglove': ['골든글러브', '골든 글러브'],
}


def crawl_awards(season: int = None):
    """KBO 시상식 발표 기사 Google News 크롤 → player_awards INSERT.
    매년 11월 시상식 후 발견. 시즌 외엔 0건 정상."""
    from datetime import date
    if season is None:
        season = date.today().year
    from crawler.crawl_naver_news import fetch_rss
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    cur.execute("SELECT id, name, team_id FROM players WHERE name IS NOT NULL AND LENGTH(name) >= 2")
    rows = cur.fetchall()
    players_cache = {r[1]: (r[0], r[2]) for r in sorted(rows, key=lambda x: -len(x[1]))}
    cur.close(); conn.close()

    queries = [f'{season} KBO MVP', f'{season} KBO 신인왕', f'{season} KBO 골든글러브']
    inserted = 0
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    for q in queries:
        articles = fetch_rss(q)
        for art in articles:
            title = art.get('title', '')
            atype = None
            for k, kws in _AWARD_KEYWORDS.items():
                if any(kw in title for kw in kws):
                    atype = k
                    break
            if not atype:
                continue
            for name, (pid, tid) in players_cache.items():
                if name in title:
                    try:
                        cur.execute("""
                            INSERT INTO player_awards
                                (player_id, player_name, team_id, award_type, position, season)
                            VALUES (%s, %s, %s, %s, %s, %s)
                            ON CONFLICT (player_id, award_type, season) DO NOTHING
                            RETURNING id
                        """, (pid, name, tid, atype, '', season))
                        if cur.fetchone():
                            inserted += 1
                    except Exception as e:
                        print(f"[award] INSERT 오류: {e}")
                    break
    conn.commit()
    cur.close(); conn.close()
    if inserted:
        print(f"[awards] 신규 {inserted}건 감지")


def crawl_allstars(season: int = None):
    """KBO 올스타 선발 기사 Google News 크롤 → player_allstars INSERT.
    매년 7월 중순 발표."""
    from datetime import date
    if season is None:
        season = date.today().year
    from crawler.crawl_naver_news import fetch_rss
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    cur.execute("SELECT id, name, team_id FROM players WHERE name IS NOT NULL AND LENGTH(name) >= 2")
    rows = cur.fetchall()
    players_cache = {r[1]: (r[0], r[2]) for r in sorted(rows, key=lambda x: -len(x[1]))}
    cur.close(); conn.close()

    queries = [f'{season} KBO 올스타 선발', f'{season} 올스타 베스트12', f'{season} KBO 올스타전']
    inserted = 0
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    for q in queries:
        articles = fetch_rss(q)
        for art in articles:
            title = art.get('title', '')
            if '올스타' not in title:
                continue
            # league 추론
            league = ''
            if '드림' in title: league = 'dream'
            elif '나눔' in title: league = 'nanum'
            for name, (pid, tid) in players_cache.items():
                if name in title:
                    try:
                        cur.execute("""
                            INSERT INTO player_allstars
                                (player_id, player_name, team_id, season, league, vote_rank)
                            VALUES (%s, %s, %s, %s, %s, %s)
                            ON CONFLICT (player_id, season) DO NOTHING
                            RETURNING id
                        """, (pid, name, tid, season, league, 0))
                        if cur.fetchone():
                            inserted += 1
                    except Exception as e:
                        print(f"[allstar] INSERT 오류: {e}")
                    break
    conn.commit()
    cur.close(); conn.close()
    if inserted:
        print(f"[allstars] 신규 {inserted}건 감지")


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


def check_allstar_vote_events():
    """allstar_vote_events 테이블 검사 → 시작/D-3/D-1 알림 발송."""
    from api.fcm_service import notify_allstar_vote_period
    from datetime import date, timedelta
    today = date.today()
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    cur.execute("""
        SELECT id, season, opens_at, closes_at, vote_url,
               notified_open, notified_d3, notified_d1
        FROM allstar_vote_events
        WHERE closes_at >= %s
    """, (today,))
    for eid, season, opens_at, closes_at, vote_url, n_open, n_d3, n_d1 in cur.fetchall():
        deadline = closes_at.strftime('%m월 %d일')
        try:
            if not n_open and today >= opens_at:
                notify_allstar_vote_period('opened', season, deadline, vote_url or '')
                cur.execute("UPDATE allstar_vote_events SET notified_open=TRUE WHERE id=%s", (eid,))
            if not n_d3 and today == closes_at - timedelta(days=3):
                notify_allstar_vote_period('closing_d3', season, deadline, vote_url or '')
                cur.execute("UPDATE allstar_vote_events SET notified_d3=TRUE WHERE id=%s", (eid,))
            if not n_d1 and today == closes_at - timedelta(days=1):
                notify_allstar_vote_period('closing_d1', season, deadline, vote_url or '')
                cur.execute("UPDATE allstar_vote_events SET notified_d1=TRUE WHERE id=%s", (eid,))
        except Exception as e:
            print(f"[allstar_vote] 알림 실패 id={eid}: {e}")
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
    try:
        cur = conn.cursor()
        # ⚠️ player_daily_stats 실 컬럼 = ab (at_bats 아님). 오타 시 매 실행 에러 → 커넥션 누수 사고(06-25)
        cur.execute("""
            SELECT DISTINCT pds.player_id, p.name, t.name, p.player_type,
                   pds.stat_type, pds.hits, pds.ab, pds.home_runs, pds.rbi,
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
        cur.close()
    finally:
        conn.close()  # 예외 시에도 반드시 반납 (try/finally 없으면 누수)
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
    try:
        cur = conn.cursor()
        # ⚠️ 실 컬럼 = ab (at_bats 아님)
        cur.execute("""
            SELECT pds.player_id, p.name, t.name, pds.game_date, pds.hits, pds.ab
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
        cur.close()
    finally:
        conn.close()

    # 선수별 연속 안타 streak 계산
    from collections import defaultdict
    by_player = defaultdict(list)
    for pid, pname, tname, gdate, hits, ab in rows:
        by_player[pid].append((gdate, hits or 0, ab or 0, pname, tname))

    notify_conn = get_connection()
    if not notify_conn:
        return
    try:
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
        ncur.close()
    finally:
        notify_conn.close()


if __name__ == '__main__':
    ensure_tables()
    print("crawl_player_events: 테이블 준비 완료")
