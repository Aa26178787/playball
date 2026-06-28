-- 역대 C2 트랙2: 2군(퓨처스) 경기단위 box-only
-- 소스: KBO Futures/Schedule/GameList.aspx(일정) + Futures/Schedule/BoxScore.aspx(박스)
-- ⚠️ 2군 pitch-by-pitch 소스 전무 → box-score 천장(라인스코어+선수 box 집계, JSONB).
-- ⚠️ box 선수행에 playerId 앵커 없음 → 이름만 저장(kbo_player_id 미연결, name-join 비권장).
CREATE TABLE IF NOT EXISTS futures_games (
    game_id      TEXT PRIMARY KEY,         -- KBO gameId (YYYYMMDD{away}{home}{dh})
    season       INT NOT NULL,
    game_date    DATE,
    away_code    TEXT,                      -- 팀코드 (HH/LG/WO=고양/SM=상무/UL=울산 ..)
    home_code    TEXT,
    away_score   INT,
    home_score   INT,
    stadium      TEXT,
    status       TEXT,                      -- 종료 / 취소(우천 등) / 예정
    series_id    INT DEFAULT 0,             -- BoxScore URL seriesId (게임별 가변)
    created_at   TIMESTAMP DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_futures_games_season ON futures_games(season);
CREATE INDEX IF NOT EXISTS idx_futures_games_date ON futures_games(game_date);

CREATE TABLE IF NOT EXISTS futures_game_box (
    game_id      TEXT PRIMARY KEY REFERENCES futures_games(game_id) ON DELETE CASCADE,
    scoreboard   JSONB,    -- {away:{team,innings:[..],r,h,e,b}, home:{..}}
    away_batters JSONB,    -- [{order,pos,name,ab,h,rbi,r,avg}]
    home_batters JSONB,
    pitchers     JSONB,    -- [{side,name,result,w,l,sv,ip,batters,pitches,hits,hr,bb_hbp,so,r,er,era}]
    summary      JSONB,    -- {결승타:..,홈런:..,2루타:..,실책:..,..}
    crawled_at   TIMESTAMP DEFAULT now()
);
GRANT ALL ON futures_games TO playball_user;
GRANT ALL ON futures_game_box TO playball_user;
