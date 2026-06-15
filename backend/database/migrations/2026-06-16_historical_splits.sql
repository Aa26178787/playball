-- trackB 스플릿 기본축: 타자 상황별 스플릿 (홈원정/상대팀/월별)
-- 소스: KBO HitterBasic/Basic1.aspx ddlSituation(축)+ddlSituationDetail(값) 이중드롭
-- 스코프(2026-06-16 결정): 최근 3시즌(2023~2025), 타자, Basic1 코어(avg + 계산 slg). 투수/OPS/역대전체=후속.
CREATE TABLE IF NOT EXISTS historical_splits (
    id            SERIAL PRIMARY KEY,
    kbo_player_id INT NOT NULL REFERENCES historical_players(kbo_player_id) ON DELETE CASCADE,
    season        INT NOT NULL,
    player_type   TEXT DEFAULT '타자',
    split_axis    TEXT NOT NULL,   -- 홈원정 / 상대팀 / 월별
    split_value   TEXT NOT NULL,   -- 홈,방문 / 상대팀명 / 4월,5월..
    games         INT,
    pa            INT,
    at_bats       INT,
    hits          INT,
    doubles       INT,
    triples       INT,
    home_runs     INT,
    rbis          INT,
    avg           NUMERIC,
    slg           NUMERIC,          -- (1B+2*2B+3*3B+4*HR)/AB 계산
    UNIQUE (kbo_player_id, season, player_type, split_axis, split_value)
);
CREATE INDEX IF NOT EXISTS idx_hist_splits_player ON historical_splits(kbo_player_id);
CREATE INDEX IF NOT EXISTS idx_hist_splits_axis ON historical_splits(split_axis);
GRANT ALL ON historical_splits TO playball_user;
GRANT USAGE, SELECT ON SEQUENCE historical_splits_id_seq TO playball_user;
