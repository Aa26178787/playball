-- 역대 포스트시즌: historical_season_stats에 series_type 추가 (정규/와일드카드/준PO/PO/한국시리즈)
-- 소스: 같은 Basic1/Basic2 페이지의 ddlSeries 드롭다운 (0정규/4와일드카드/3준PO/5PO/7한국시리즈)
ALTER TABLE historical_season_stats
    ADD COLUMN IF NOT EXISTS series_type TEXT NOT NULL DEFAULT '정규';

-- 기존 UNIQUE(kbo_player_id, season, team_name)에 series_type 포함하도록 교체
ALTER TABLE historical_season_stats
    DROP CONSTRAINT IF EXISTS historical_season_stats_kbo_player_id_season_team_name_key;
ALTER TABLE historical_season_stats
    DROP CONSTRAINT IF EXISTS historical_season_stats_uniq;
ALTER TABLE historical_season_stats
    ADD CONSTRAINT historical_season_stats_uniq
    UNIQUE (kbo_player_id, season, team_name, series_type);

CREATE INDEX IF NOT EXISTS idx_hist_stats_series ON historical_season_stats(series_type);
