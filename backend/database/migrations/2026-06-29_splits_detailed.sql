-- 역대 C2 트랙3: 스플릿 세밀축 — 기존 historical_splits 확장
-- (1) 정확 SLG용 TB 컬럼 (Basic1 split에 TB 있음 → slg=TB/AB, 구성요소 계산 대체)
-- (2) 투수 스플릿 지원 (player_type='투수' 행용 투수 컬럼)
-- 세밀 v1 축: 투수=홈원정/상대팀/월별/타자유형(좌우)/구장, 타자=투수유형(좌우 플래툰).
ALTER TABLE historical_splits
    ADD COLUMN IF NOT EXISTS tb                 INT,
    ADD COLUMN IF NOT EXISTS innings_pitched    NUMERIC,
    ADD COLUMN IF NOT EXISTS era                NUMERIC,
    ADD COLUMN IF NOT EXISTS whip               NUMERIC,
    ADD COLUMN IF NOT EXISTS wins               INT,
    ADD COLUMN IF NOT EXISTS losses             INT,
    ADD COLUMN IF NOT EXISTS saves              INT,
    ADD COLUMN IF NOT EXISTS holds              INT,
    ADD COLUMN IF NOT EXISTS hits_allowed       INT,
    ADD COLUMN IF NOT EXISTS walks_allowed      INT,
    ADD COLUMN IF NOT EXISTS strikeouts_pitched INT,
    ADD COLUMN IF NOT EXISTS earned_runs        INT,
    ADD COLUMN IF NOT EXISTS runs_allowed       INT,
    ADD COLUMN IF NOT EXISTS home_runs_allowed  INT;
