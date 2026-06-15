-- 트랙A꼬리: 드래프트(지명순위) — detail div.player_info '지명순위: 93 삼성 1차' 추출
-- 연봉은 합법성 회색이라 보류. draft.koreabaseball.com 별도크롤 불요(detail에 이미 있음).
ALTER TABLE historical_players ADD COLUMN IF NOT EXISTS draft_info TEXT;
