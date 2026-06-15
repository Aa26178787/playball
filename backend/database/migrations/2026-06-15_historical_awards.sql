-- 역대 수상경력: 선수 detail Award.aspx (서버 IP 도달 OK — aggregation History 페이지와 달리 접근됨)
-- 소스: KBO Record/Player/{Hitter,Pitcher}Detail/Award.aspx?playerId= (table 연도|수상)
CREATE TABLE IF NOT EXISTS historical_awards (
    id            SERIAL PRIMARY KEY,
    kbo_player_id INT NOT NULL REFERENCES historical_players(kbo_player_id) ON DELETE CASCADE,
    season        INT,
    award         TEXT NOT NULL,
    UNIQUE (kbo_player_id, season, award)
);
CREATE INDEX IF NOT EXISTS idx_hist_awards_player ON historical_awards(kbo_player_id);
GRANT ALL ON historical_awards TO playball_user;
GRANT USAGE, SELECT ON SEQUENCE historical_awards_id_seq TO playball_user;
