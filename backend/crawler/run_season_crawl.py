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


def compute_derived_stats():
    """기존 데이터로 파생 지표 계산 (NULL 값 채우기)"""
    conn = get_connection()
    if not conn:
        return
    cur = conn.cursor()

    # IP 실제이닝 변환: 45.2 → 45 + 2/3 이닝
    # innings_pitched 컬럼: .1 = 1/3, .2 = 2/3 형식
    ip_expr = """
        FLOOR(innings_pitched) +
        ROUND((innings_pitched - FLOOR(innings_pitched)) * 10) * (1.0 / 3.0)
    """

    # 투수: k_per_9
    cur.execute(f"""
        UPDATE pitcher_stats SET
            k_per_9 = ROUND((strikeouts * 9.0 / NULLIF({ip_expr}, 0))::numeric, 2)
        WHERE season = %s AND innings_pitched > 0
          AND strikeouts IS NOT NULL
          AND (k_per_9 IS NULL OR k_per_9 = 0)
    """, (SEASON,))
    print(f"[derived] k_per_9 업데이트: {cur.rowcount}행")

    # 투수: bb_per_9
    cur.execute(f"""
        UPDATE pitcher_stats SET
            bb_per_9 = ROUND((walks * 9.0 / NULLIF({ip_expr}, 0))::numeric, 2)
        WHERE season = %s AND innings_pitched > 0
          AND walks IS NOT NULL
          AND (bb_per_9 IS NULL OR bb_per_9 = 0)
    """, (SEASON,))
    print(f"[derived] bb_per_9 업데이트: {cur.rowcount}행")

    # 투수: FIP = (13*HR + 3*(BB+HBP) - 2*K) / IP + FIP_constant
    # KBO 2026 FIP 상수 ≈ 3.2 (league ERA - unadjusted FIP 근사값)
    cur.execute(f"""
        UPDATE pitcher_stats SET
            fip = ROUND(
                ((13.0 * home_runs_allowed
                  + 3.0 * (walks + COALESCE(hbp, 0))
                  - 2.0 * strikeouts)
                 / NULLIF({ip_expr}, 0) + 3.20)::numeric,
                2)
        WHERE season = %s AND innings_pitched > 0
          AND home_runs_allowed IS NOT NULL
          AND walks IS NOT NULL AND strikeouts IS NOT NULL
          AND fip IS NULL
    """, (SEASON,))
    print(f"[derived] fip 업데이트: {cur.rowcount}행")

    # 투수: BABIP = (HA - HRA) / (TBF - SO - HRA - BB - HBP)
    cur.execute("""
        UPDATE pitcher_stats SET
            babip = ROUND(
                (hits_allowed - home_runs_allowed)::numeric /
                NULLIF(tbf - strikeouts - home_runs_allowed
                       - walks - COALESCE(hbp, 0), 0),
                3)
        WHERE season = %s AND tbf > 0
          AND hits_allowed IS NOT NULL AND home_runs_allowed IS NOT NULL
          AND strikeouts IS NOT NULL AND walks IS NOT NULL
          AND babip IS NULL
    """, (SEASON,))
    print(f"[derived] pitcher babip 업데이트: {cur.rowcount}행")

    # 타자: TB = H + 2B + 2*3B + 3*HR
    cur.execute("""
        UPDATE batter_stats SET
            tb = hits + doubles + 2 * triples + 3 * home_runs
        WHERE season = %s AND hits IS NOT NULL AND doubles IS NOT NULL
          AND (tb IS NULL OR tb = 0)
    """, (SEASON,))
    print(f"[derived] tb 업데이트: {cur.rowcount}행")

    # 타자: ISO = SLG - AVG
    cur.execute("""
        UPDATE batter_stats SET
            iso = ROUND((slg - avg)::numeric, 3)
        WHERE season = %s AND slg IS NOT NULL AND avg IS NOT NULL
          AND iso IS NULL
    """, (SEASON,))
    print(f"[derived] iso 업데이트: {cur.rowcount}행")

    # 타자: BABIP = (H - HR) / (AB - SO - HR + SF)
    cur.execute("""
        UPDATE batter_stats SET
            babip = ROUND(
                (hits - home_runs)::numeric /
                NULLIF(at_bats - strikeouts - home_runs + COALESCE(sf, 0), 0),
                3)
        WHERE season = %s AND at_bats > 0
          AND hits IS NOT NULL AND home_runs IS NOT NULL
          AND strikeouts IS NOT NULL
          AND babip IS NULL
    """, (SEASON,))
    print(f"[derived] batter babip 업데이트: {cur.rowcount}행")

    # 타자: OPS = OBP + SLG (NULL 채우기)
    cur.execute("""
        UPDATE batter_stats SET
            ops = ROUND((obp + slg)::numeric, 3)
        WHERE season = %s AND obp IS NOT NULL AND slg IS NOT NULL
          AND ops IS NULL
    """, (SEASON,))
    print(f"[derived] ops 업데이트: {cur.rowcount}행")

    conn.commit()
    cur.close()
    conn.close()
    print("[derived] 파생지표 계산 완료")


def run_all():
    print("=== KBO 시즌 크롤러 전체 실행 ===")

    print("\n[1/8] 타자 Basic1 (G/AB/R/H/2B/3B/HR/RBI/SB/CS/BB/HBP/SO/GDP/AVG)")
    crawl_kbo_hitter_season_stats(SEASON)

    print("\n[2/8] 타자 Basic2 (BB/IBB/HBP/SO/GDP/OBP/SLG/OPS/MH/RISP/PH-BA)")
    crawl_kbo_hitter_season_stats_2(SEASON)

    print("\n[3/8] 타자 Detail1 (P/PA)")
    crawl_kbo_hitter_detail1(SEASON)

    print("\n[4/8] 투수 Basic1 (G/W/L/SV/HLD/IP/HA/HRA/BB/HBP/SO/R/ER/ERA/WHIP/WPCT)")
    crawl_kbo_pitcher_season_stats(SEASON)

    print("\n[5/8] 투수 Basic2 (CG/SHO/QS/BSV/TBF/NP/AVG/2B/3B/SAC/SF/IBB/WP/BK)")
    crawl_kbo_pitcher_season_stats_2(SEASON)

    print("\n[6/8] 투수 Detail1 (GS/GF/SVO)")
    crawl_kbo_pitcher_detail1(SEASON)

    print("\n[7/8] 주루 (SBA/SB/CS/SB%)")
    crawl_kbo_runner_stats(SEASON)

    print("\n[8/8] 수비 (E/FPCT/PO/A/DP/PB)")
    crawl_kbo_defense_stats(SEASON)

    print("\n[파생지표] 계산 시작")
    compute_derived_stats()

    print("\n=== 전체 완료 ===")


if __name__ == '__main__':
    run_all()
