-- 역대 데이터 수집 트랙A코어: 은퇴/역대 선수 스키마
-- 설계결정(2026-06-15 게이트): 별도 역대테이블(현 players 무손상) + kbo_player_id 정규키.
-- 소스: KBO 공식(koreabaseball.com) selenium. naver stat api는 2007~만(실측) → 역대는 KBO 단일 spine.
-- 앱 조회 = active(players) ∪ historical_players 병합. saber(war/woba/wrc+/fip)=KBO 미제공, recompute로 후채움.

CREATE TABLE IF NOT EXISTS historical_players (
    id              SERIAL PRIMARY KEY,
    kbo_player_id   INT UNIQUE NOT NULL,          -- 정규키 (KBO detail/record playerId)
    naver_player_id INT,                          -- 라이브 보조 브릿지 (매칭되면 채움)
    player_id       INT REFERENCES players(id) ON DELETE SET NULL,  -- 현역 players 행 있으면 링크
    name            TEXT NOT NULL,
    player_type     TEXT,                         -- 타자/투수
    birth_date      DATE,
    height          INT,
    weight          INT,
    throws          TEXT,                         -- 좌/우/양 (투)
    bats            TEXT,                         -- 좌/우/양 (타)
    position        TEXT,
    career          TEXT,                         -- 경력/출신교 (남도초-경운중-...-LG)
    debut_year      INT,
    final_year      INT,
    primary_team_id INT REFERENCES teams(id) ON DELETE SET NULL,  -- 대표팀(현존), 해체구단이면 NULL
    profile_image   TEXT,
    created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_hist_players_name   ON historical_players(name);
CREATE INDEX IF NOT EXISTS idx_hist_players_naver  ON historical_players(naver_player_id);

CREATE TABLE IF NOT EXISTS historical_season_stats (
    id                 SERIAL PRIMARY KEY,
    kbo_player_id      INT NOT NULL REFERENCES historical_players(kbo_player_id) ON DELETE CASCADE,
    season             INT NOT NULL,
    team_franchise_id  INT REFERENCES team_franchises(id) ON DELETE SET NULL,  -- 그 시즌 소속(해체구단 포함)
    team_name          TEXT,                  -- 그 시즌 구단명(표시용)
    player_type        TEXT,                  -- 타자/투수
    games              INT,
    -- 타자
    pa                 INT,
    at_bats            INT,
    runs               INT,
    hits               INT,
    doubles            INT,
    triples            INT,
    home_runs          INT,
    rbis               INT,
    walks              INT,
    hbp                INT,
    intentional_walks  INT,
    strikeouts         INT,
    stolen_bases       INT,
    caught_stealing    INT,
    gdp                INT,
    sac_hits           INT,
    sac_flies          INT,
    avg                NUMERIC,
    obp                NUMERIC,
    slg                NUMERIC,
    ops                NUMERIC,
    -- 투수
    wins               INT,
    losses             INT,
    saves              INT,
    holds              INT,
    innings_pitched    NUMERIC,               -- 6.1=6⅓ 표기(기존 관례)
    hits_allowed       INT,
    runs_allowed       INT,
    earned_runs        INT,
    walks_allowed      INT,
    hbp_allowed        INT,
    strikeouts_pitched INT,
    home_runs_allowed  INT,
    era                NUMERIC,
    whip               NUMERIC,
    qs                 INT,
    complete_games     INT,
    shutouts           INT,
    -- 세이버 (KBO 미제공 → recompute 후채움)
    war                NUMERIC,
    woba               NUMERIC,
    wrc_plus           INT,
    fip                NUMERIC,
    UNIQUE (kbo_player_id, season, team_name)
);
CREATE INDEX IF NOT EXISTS idx_hist_stats_player ON historical_season_stats(kbo_player_id);
CREATE INDEX IF NOT EXISTS idx_hist_stats_season ON historical_season_stats(season);

GRANT ALL ON historical_players, historical_season_stats TO playball_user;
GRANT USAGE, SELECT ON SEQUENCE historical_players_id_seq, historical_season_stats_id_seq TO playball_user;
