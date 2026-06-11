"""과거 시즌(2024·2025) batter/pitcher_stats 적재 — 네이버 통계 + KBO 공식 + SQL 파생

사용: cd ~/playball/backend && python3 crawler/backfill_season_stats.py 2024 2025

- 1차 = 네이버 통계 API(statiz_crawler, requests): 전 선수 + woba/wrc_plus/war 포함.
  update_players=False → 현존 players만 매칭(naver_id 우선 = 이적생 자동),
  은퇴/방출 선수 신규생성 없음, 현역 프로필(team_id 등) 안 건드림.
- 2차 = KBO 공식(selenium): 과거 시즌은 규정 충족자만 노출 — sac/sf/gdp/detail/주루/수비
  등 보강 컬럼용 (GREATEST 머지).
- 3차 = SQL 파생지표 (run_season_crawl.compute_derived_stats, 모듈 SEASON 치환).
"""
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from crawler.statiz_crawler import get_hitter_stats, get_pitcher_stats, save_players_and_stats
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
    print(f"[{season}] 네이버 통계 타자", flush=True)
    hitters = get_hitter_stats(season)
    print(f"  {len(hitters)}명 수신", flush=True)
    save_players_and_stats(hitters, 'HITTER', update_players=False)
    print(f"[{season}] 네이버 통계 투수", flush=True)
    pitchers = get_pitcher_stats(season)
    print(f"  {len(pitchers)}명 수신", flush=True)
    save_players_and_stats(pitchers, 'PITCHER', update_players=False)
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
