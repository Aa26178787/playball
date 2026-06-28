-- 역대 C2 트랙1: 2군(퓨처스) 시즌스탯 역대화
-- 소스: KBO futures/player/{hitter,pitcher}.aspx (selenium, ddlSeason 2010~ + ddlTeam 비규정 우회)
-- 키: kbo_player_id (선수 앵커 playerId, 1군 historical_players와 동일 정규키)
-- ⚠️ 1군 historical_season_stats와 별도 테이블 (career/leaders 오염 방지 — 2군은 통산집계서 제외)
-- 컬럼: 퓨처스 페이지 단일테이블(tbl) 제공분만. OPS=SLG+OBP, WHIP=(H+BB)/IP 계산.
CREATE TABLE IF NOT EXISTS historical_futures_season_stats (
    id            SERIAL PRIMARY KEY,
    kbo_player_id INT NOT NULL REFERENCES historical_players(kbo_player_id) ON DELETE CASCADE,
    season        INT NOT NULL,
    team_name     TEXT,
    player_type   TEXT NOT NULL,        -- 타자 / 투수
    games         INT,
    -- 타자
    pa            INT,
    at_bats       INT,
    runs          INT,
    hits          INT,
    doubles       INT,
    triples       INT,
    home_runs     INT,
    rbis          INT,
    stolen_bases  INT,
    walks         INT,
    hbp           INT,
    strikeouts    INT,
    avg           NUMERIC,
    obp           NUMERIC,
    slg           NUMERIC,
    ops           NUMERIC,
    -- 투수
    wins              INT,
    losses            INT,
    saves             INT,
    holds             INT,
    wpct              NUMERIC,
    innings_pitched   NUMERIC,
    hits_allowed      INT,
    home_runs_allowed INT,
    walks_allowed     INT,
    hbp_allowed       INT,
    strikeouts_pitched INT,
    runs_allowed      INT,
    earned_runs       INT,
    era               NUMERIC,
    whip              NUMERIC,
    UNIQUE (kbo_player_id, season, team_name, player_type)
);
CREATE INDEX IF NOT EXISTS idx_hist_fut_stats_player ON historical_futures_season_stats(kbo_player_id);
CREATE INDEX IF NOT EXISTS idx_hist_fut_stats_season ON historical_futures_season_stats(season);
GRANT ALL ON historical_futures_season_stats TO playball_user;
GRANT USAGE, SELECT ON SEQUENCE historical_futures_season_stats_id_seq TO playball_user;
