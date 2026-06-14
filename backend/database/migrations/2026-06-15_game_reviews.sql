-- 메가E: 경기 한줄평 + 오늘의 MVP 영속 (종료 후처리서 upsert)
-- 재사용: 경기상세 배지, 추후 공유 카드/다이제스트
CREATE TABLE IF NOT EXISTS game_reviews (
    game_id        INT PRIMARY KEY REFERENCES games(id) ON DELETE CASCADE,
    review_text    TEXT,
    mvp_player_id  INT REFERENCES players(id) ON DELETE SET NULL,
    mvp_name       TEXT,
    mvp_line       TEXT,
    created_at     TIMESTAMPTZ DEFAULT now()
);
GRANT ALL ON game_reviews TO playball_user;
