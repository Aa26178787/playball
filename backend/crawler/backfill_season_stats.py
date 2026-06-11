"""과거 시즌(2024·2025) batter/pitcher_stats 적재 — KBO 공식 크롤 + SQL 파생지표

사용: cd ~/playball/backend && python3 crawler/backfill_season_stats.py 2024 2025

- 매칭: 현존 players만 (_find_player_id — 이적생은 name 단독 fallback, 동명이인 스킵).
  은퇴/방출 선수는 적재 안 함 (players 오염 방지) → 과거 시즌 행은 현역 선수 한정.
- statiz 미수집: woba/wrc_plus/war 등 고급지표는 과거 시즌 NULL (UI '-').
- 파생지표는 run_season_crawl.compute_derived_stats 재사용 (모듈 SEASON 치환).
"""
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from crawler.kbo_daily_crawler import (
    crawl_kbo_hitter_season_stats,
    crawl_kbo_hitter_season_stats_2,
    crawl_kbo_hitter_detail1,
    crawl_kbo_pitcher_season_stats,
    crawl_kbo_pitcher_season_stats_2,
    crawl_kbo_pitcher_detail1,
    crawl_kbo_runner_stats,
    crawl_kbo_defense_stats,
)
import crawler.run_season_crawl as rsc


def backfill(season: int):
    print(f"\n===== {season} 시즌 적재 =====", flush=True)
    steps = [
        ("타자 Basic1", crawl_kbo_hitter_season_stats),
        ("타자 Basic2", crawl_kbo_hitter_season_stats_2),
        ("타자 Detail1", crawl_kbo_hitter_detail1),
        ("투수 Basic1", crawl_kbo_pitcher_season_stats),
        ("투수 Basic2", crawl_kbo_pitcher_season_stats_2),
        ("투수 Detail1", crawl_kbo_pitcher_detail1),
        ("주루", crawl_kbo_runner_stats),
        ("수비", crawl_kbo_defense_stats),
    ]
    for label, fn in steps:
        print(f"[{season}] {label}", flush=True)
        fn(season)
    print(f"[{season}] 파생지표", flush=True)
    rsc.SEASON = season  # compute_derived_stats가 모듈 전역 SEASON 사용
    rsc.compute_derived_stats()
    print(f"===== {season} 완료 =====", flush=True)


if __name__ == '__main__':
    seasons = [int(a) for a in sys.argv[1:]] or [2024, 2025]
    for s in seasons:
        backfill(s)
