"""
전체 KBO 시즌 스탯 크롤러 + 파생지표 계산 실행 스크립트
"""
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from database.connection import get_connection
from crawler.kbo_daily_crawler import (
    crawl_kbo_hitter_season_stats,
    crawl_kbo_hitter_season_stats_2,
    crawl_kbo_pitcher_season_stats,
    crawl_kbo_pitcher_season_stats_2,
    crawl_kbo_runner_stats,
    crawl_kbo_defense_stats,
    crawl_kbo_hitter_detail1,
    crawl_kbo_pitcher_detail1,
)

SEASON = 2026

# IP 실제이닝 변환: .1=1/3, .2=2/3 형식 → 실수 (SQL 표현식)
_IP_REAL = """
    FLOOR(innings_pitched) +
    ROUND((innings_pitched - FLOOR(innings_pitched)) * 10) * (1.0 / 3.0)
"""


def compute_derived_stats():
    """기존 데이터로 파생 지표 계산 (전체 갱신)"""
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()

    # ── 투수 ──────────────────────────────────────────────
    cur.execute(f"""
        UPDATE pitcher_stats SET
            k_per_9  = ROUND((strikeouts * 9.0       / NULLIF({_IP_REAL}, 0))::numeric, 2),
            bb_per_9 = ROUND((walks * 9.0             / NULLIF({_IP_REAL}, 0))::numeric, 2),
            h_per_9  = ROUND((hits_allowed * 9.0      / NULLIF({_IP_REAL}, 0))::numeric, 2),
            hr_per_9 = ROUND((home_runs_allowed * 9.0 / NULLIF({_IP_REAL}, 0))::numeric, 2),
            fip      = ROUND(
                ((13.0 * COALESCE(home_runs_allowed,0)
                  + 3.0 * (COALESCE(walks,0) + COALESCE(hbp,0))
                  - 2.0 * COALESCE(strikeouts,0))
                 / NULLIF({_IP_REAL}, 0) + 3.20)::numeric, 2),
            k_bb     = ROUND((strikeouts::numeric / NULLIF(walks, 0)), 2),
            go_ao    = ROUND((go::numeric          / NULLIF(ao,    0)), 2)
        WHERE season = %s AND innings_pitched > 0
    """, (SEASON,))
    print(f"[derived] 투수 지표 업데이트: {cur.rowcount}행")

    cur.execute("""
        UPDATE pitcher_stats SET
            babip = ROUND(
                (hits_allowed - home_runs_allowed)::numeric /
                NULLIF(tbf - strikeouts - home_runs_allowed - walks - COALESCE(hbp,0), 0),
                3)
        WHERE season = %s AND tbf > 0
          AND hits_allowed IS NOT NULL AND home_runs_allowed IS NOT NULL
          AND strikeouts IS NOT NULL AND walks IS NOT NULL
          AND babip IS NULL
    """, (SEASON,))
    print(f"[derived] pitcher babip: {cur.rowcount}행")

    # ── 타자 (조건별 분리) ────────────────────────────────
    # 기본 누적 지표: hits/doubles/triples/home_runs만 있으면 계산 가능
    cur.execute("""
        UPDATE batter_stats SET
            tb  = hits + doubles + 2 * triples + 3 * home_runs,
            xbh = doubles + triples + home_runs
        WHERE season = %s AND hits IS NOT NULL AND doubles IS NOT NULL
    """, (SEASON,))
    print(f"[derived] tb/xbh: {cur.rowcount}행")

    # XR: 기본 타격 지표만 필요
    cur.execute("""
        UPDATE batter_stats SET
            xr = ROUND((
                0.50 * (hits - doubles - triples - home_runs)
                + 0.72 * doubles + 1.04 * triples + 1.44 * home_runs
                + 0.34 * (COALESCE(hbp,0) + walks - COALESCE(ibb,0))
                + 0.25 * COALESCE(ibb,0)
                + 0.18 * COALESCE(stolen_bases,0)
                - 0.32 * COALESCE(cs,0)
                - 0.09 * (at_bats - hits - strikeouts)
                - 0.098 * strikeouts
                - 0.37 * COALESCE(gdp,0)
                + 0.37 * COALESCE(sf,0)
                + 0.04 * COALESCE(sac,0)
            )::numeric, 2)
        WHERE season = %s AND hits IS NOT NULL AND at_bats IS NOT NULL
          AND walks IS NOT NULL AND strikeouts IS NOT NULL
    """, (SEASON,))
    print(f"[derived] xr: {cur.rowcount}행")

    # 비율 지표: slg/obp/avg 필요
    cur.execute("""
        UPDATE batter_stats SET
            iso   = ROUND((slg - avg)::numeric, 3),
            ops   = ROUND((obp + slg)::numeric, 3),
            gpa   = ROUND(((1.8 * obp + slg) / 4.0)::numeric, 3),
            babip = ROUND(
                (hits - home_runs)::numeric /
                NULLIF(at_bats - strikeouts - home_runs + COALESCE(sf,0), 0),
                3)
        WHERE season = %s AND slg IS NOT NULL AND avg IS NOT NULL AND obp IS NOT NULL
          AND hits IS NOT NULL AND at_bats IS NOT NULL
    """, (SEASON,))
    print(f"[derived] iso/ops/gpa/babip: {cur.rowcount}행")

    # BB/K, GO/AO
    cur.execute("""
        UPDATE batter_stats SET
            bb_k  = ROUND((walks::numeric  / NULLIF(strikeouts, 0)), 3),
            go_ao = ROUND((go::numeric     / NULLIF(ao, 0)), 2)
        WHERE season = %s AND walks IS NOT NULL AND strikeouts IS NOT NULL
    """, (SEASON,))
    print(f"[derived] bb_k/go_ao: {cur.rowcount}행")

    conn.commit()
    cur.close()
    conn.close()
    print("[derived] 파생지표 계산 완료")


def sync_innings_from_game_pitchers():
    """game_pitchers 집계로 pitcher_stats IP/games 복구 (덮어쓰기 방지)"""
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()
    cur.execute("""
        UPDATE pitcher_stats ps
        SET
            games              = GREATEST(COALESCE(ps.games,0), agg.g),
            wins               = GREATEST(COALESCE(ps.wins,0),  agg.w),
            losses             = GREATEST(COALESCE(ps.losses,0), agg.l),
            saves              = GREATEST(COALESCE(ps.saves,0),  agg.sv),
            holds              = GREATEST(COALESCE(ps.holds,0),  agg.hld),
            innings_pitched    = GREATEST(COALESCE(ps.innings_pitched,0), agg.ip_fmt),
            strikeouts         = GREATEST(COALESCE(ps.strikeouts,0), agg.so),
            earned_runs        = GREATEST(COALESCE(ps.earned_runs,0), agg.er),
            walks              = GREATEST(COALESCE(ps.walks,0),  agg.bb),
            hits_allowed       = GREATEST(COALESCE(ps.hits_allowed,0), agg.ha),
            runs_allowed       = GREATEST(COALESCE(ps.runs_allowed,0), agg.ra),
            home_runs_allowed  = GREATEST(COALESCE(ps.home_runs_allowed,0), agg.hra)
        FROM (
            SELECT player_id,
                COUNT(*) AS g,
                SUM(CASE WHEN result='승' THEN 1 ELSE 0 END) AS w,
                SUM(CASE WHEN result='패' THEN 1 ELSE 0 END) AS l,
                SUM(CASE WHEN result='세이브' THEN 1 ELSE 0 END) AS sv,
                SUM(CASE WHEN result='홀드' THEN 1 ELSE 0 END) AS hld,
                SUM(strikeouts) AS so,
                SUM(earned_runs) AS er,
                SUM(walks) AS bb,
                SUM(hits_allowed) AS ha,
                SUM(runs_allowed) AS ra,
                SUM(home_runs_allowed) AS hra,
                (
                    FLOOR(SUM(FLOOR(innings_pitched) + ROUND((innings_pitched - FLOOR(innings_pitched))*10)*(1.0/3.0))) +
                    LEAST(ROUND(
                        (SUM(FLOOR(innings_pitched) + ROUND((innings_pitched - FLOOR(innings_pitched))*10)*(1.0/3.0))
                         - FLOOR(SUM(FLOOR(innings_pitched) + ROUND((innings_pitched - FLOOR(innings_pitched))*10)*(1.0/3.0))))
                        * 3), 2) * 0.1
                ) AS ip_fmt
            FROM game_pitchers
            WHERE innings_pitched > 0
            GROUP BY player_id
        ) agg
        WHERE ps.player_id = agg.player_id AND ps.season = %s
    """, (SEASON,))
    print(f"[sync] game_pitchers 집계 복구: {cur.rowcount}행")
    conn.commit()
    cur.close()
    conn.close()


def run_all():
    print("=== KBO 시즌 크롤러 전체 실행 ===")

    print("\n[1/8] 타자 Basic1")
    crawl_kbo_hitter_season_stats(SEASON)

    print("\n[2/8] 타자 Basic2")
    crawl_kbo_hitter_season_stats_2(SEASON)

    print("\n[3/8] 타자 Detail1 (GO/AO/GW_RBI/P_PA)")
    crawl_kbo_hitter_detail1(SEASON)

    print("\n[4/8] 투수 Basic1")
    crawl_kbo_pitcher_season_stats(SEASON)

    print("\n[5/8] 투수 Basic2")
    crawl_kbo_pitcher_season_stats_2(SEASON)

    print("\n[6/8] 투수 Detail1 (GS/GF/SVO/Wgs/Wgr/TS/GDP/GO/AO)")
    crawl_kbo_pitcher_detail1(SEASON)

    print("\n[7/8] 주루 (SBA/SB/CS/SB%/OOB/PKO)")
    crawl_kbo_runner_stats(SEASON)

    print("\n[8/8] 수비 (E/GS/IP/PKO/PO/A/DP/FPCT/PB/CS/CS%)")
    crawl_kbo_defense_stats(SEASON)

    print("\n[sync] game_pitchers로 IP 복구")
    sync_innings_from_game_pitchers()

    print("\n[파생지표] 계산")
    compute_derived_stats()

    print("\n=== 전체 완료 ===")


if __name__ == '__main__':
    run_all()
