-- 역대 세이버/레이트 확장: Naver stat API 고유 지표 컬럼 (KBO 미제공)
-- 매핑(2026-06-17 값검증): 타자 babip=hitterBabip·iso=hitterIsop·wpa=hitterWpa /
--   투수 k_per_9=pitcherInningKk·bb_per_9=pitcherInningBb·k_bb=pitcherKkBbRate·
--   k_pct=pitcherPaKkRate·bb_pct=pitcherPaBbRate·wpct=pitcherWra(승률)·wpa=pitcherWpa·np=pitcherPitchCount
-- ⚠️ pitcherWra=승률(17/23) — 피안타율 아님. avg_against는 Naver 미제공.
ALTER TABLE historical_season_stats
    ADD COLUMN IF NOT EXISTS babip    NUMERIC,
    ADD COLUMN IF NOT EXISTS iso      NUMERIC,
    ADD COLUMN IF NOT EXISTS wpa      NUMERIC,
    ADD COLUMN IF NOT EXISTS k_per_9  NUMERIC,
    ADD COLUMN IF NOT EXISTS bb_per_9 NUMERIC,
    ADD COLUMN IF NOT EXISTS k_bb     NUMERIC,
    ADD COLUMN IF NOT EXISTS k_pct    NUMERIC,
    ADD COLUMN IF NOT EXISTS bb_pct   NUMERIC,
    ADD COLUMN IF NOT EXISTS wpct     NUMERIC,
    ADD COLUMN IF NOT EXISTS np       INT;
