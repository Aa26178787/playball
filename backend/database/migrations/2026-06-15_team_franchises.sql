-- 역대 데이터 수집 토대: 구단계보(팀역사) 테이블
-- 목적: 역대(1982~) 선수의 그-시대 구단명/코드 → 현 10구단 매핑 받침.
--       역대 기록은 "삼미 슈퍼스타즈" "OB 베어스" 등 옛 구단명으로 들어옴.
-- 매핑 규칙: current_team_id = 법적 계보 잇는 현 구단 (NULL = 해체/단절 구단).
-- ⚠️ 계보 판정 = KBO 공식 관례 준수:
--    · 개명/인수로 이어진 구단 = 연속(continuous). (OB→두산, 해태→KIA, 빙그레→한화, SK→SSG 등)
--    · 현대 유니콘스(삼미→청보→태평양→현대) = 2007 해체 후 단절. 히어로즈는 선수단 일부만
--      인수한 별개 법인 → current_team_id=NULL (KBO도 현대 기록을 키움 계보로 안 침).
--    · 쌍방울 레이더스 = 1999 해체. 선수 일부→SK(신생) → 단절(NULL).
--    역대 선수 team_id 매핑 시 NULL 구단은 옛 구단명 그대로 표기(현 구단에 귀속 X).

CREATE TABLE IF NOT EXISTS team_franchises (
    id              SERIAL PRIMARY KEY,
    current_team_id INT REFERENCES teams(id) ON DELETE SET NULL,  -- NULL = 해체/단절
    team_name       TEXT NOT NULL,        -- 그 시대 공식 구단명 (역대 기록 표기)
    team_code       TEXT,                 -- KBO/naver 코드 (현재명 시대만 채움, 옛 시대는 크롤서 보강)
    start_year      INT  NOT NULL,
    end_year        INT,                  -- NULL = 현재 진행
    is_continuous   BOOLEAN NOT NULL DEFAULT TRUE,  -- current_team_id로 법적 연속이면 TRUE
    note            TEXT,
    UNIQUE (team_name, start_year)
);
CREATE INDEX IF NOT EXISTS idx_team_franchises_current ON team_franchises(current_team_id);

-- 시드: 현 short_name 코드로 current_team_id 조회 (id 비의존)
-- short_name: OB=두산 LG HT=KIA HH=한화 LT=롯데 SS=삼성 SK=SSG WO=키움 NC KT

INSERT INTO team_franchises (current_team_id, team_name, team_code, start_year, end_year, is_continuous, note) VALUES
-- 두산 베어스 (OB)
((SELECT id FROM teams WHERE short_name='OB'), 'OB 베어스',     'OB', 1982, 1998, TRUE,  '1999 두산으로 개명'),
((SELECT id FROM teams WHERE short_name='OB'), '두산 베어스',   'OB', 1999, NULL, TRUE,  NULL),
-- LG 트윈스 (LG)
((SELECT id FROM teams WHERE short_name='LG'), 'MBC 청룡',      NULL, 1982, 1989, TRUE,  '1990 LG 인수·개명'),
((SELECT id FROM teams WHERE short_name='LG'), 'LG 트윈스',     'LG', 1990, NULL, TRUE,  NULL),
-- 삼성 라이온즈 (SS) — 개명 없음
((SELECT id FROM teams WHERE short_name='SS'), '삼성 라이온즈', 'SS', 1982, NULL, TRUE,  '창단 이래 동일'),
-- 롯데 자이언츠 (LT) — 개명 없음
((SELECT id FROM teams WHERE short_name='LT'), '롯데 자이언츠', 'LT', 1982, NULL, TRUE,  '창단 이래 동일'),
-- 한화 이글스 (HH)
((SELECT id FROM teams WHERE short_name='HH'), '빙그레 이글스', NULL, 1986, 1993, TRUE,  '1994 한화로 개명'),
((SELECT id FROM teams WHERE short_name='HH'), '한화 이글스',   'HH', 1994, NULL, TRUE,  NULL),
-- KIA 타이거즈 (HT)
((SELECT id FROM teams WHERE short_name='HT'), '해태 타이거즈', NULL, 1982, 2000, TRUE,  '2001 KIA 인수·개명'),
((SELECT id FROM teams WHERE short_name='HT'), 'KIA 타이거즈',  'HT', 2001, NULL, TRUE,  NULL),
-- 키움 히어로즈 (WO) — 같은 법인 명칭/스폰서 변경
((SELECT id FROM teams WHERE short_name='WO'), '우리·서울 히어로즈', NULL, 2008, 2009, TRUE, '히어로즈 창단(스폰서명 변천)'),
((SELECT id FROM teams WHERE short_name='WO'), '넥센 히어로즈', 'WO', 2010, 2018, TRUE,  NULL),
((SELECT id FROM teams WHERE short_name='WO'), '키움 히어로즈', 'WO', 2019, NULL, TRUE,  NULL),
-- SSG 랜더스 (SK)
((SELECT id FROM teams WHERE short_name='SK'), 'SK 와이번스',   NULL, 2000, 2020, TRUE,  '2021 SSG(신세계) 인수·개명'),
((SELECT id FROM teams WHERE short_name='SK'), 'SSG 랜더스',    'SK', 2021, NULL, TRUE,  NULL),
-- NC 다이노스 (NC) — 신생
((SELECT id FROM teams WHERE short_name='NC'), 'NC 다이노스',   'NC', 2013, NULL, TRUE,  '2013 창단(전신 없음)'),
-- KT 위즈 (KT) — 신생
((SELECT id FROM teams WHERE short_name='KT'), 'KT 위즈',       'KT', 2015, NULL, TRUE,  '2015 창단(전신 없음)'),
-- ── 해체/단절 구단 (current_team_id = NULL) ──
-- 현대 유니콘스 계보 (삼미→청보→태평양→현대, 2007 해체)
(NULL, '삼미 슈퍼스타즈', NULL, 1982, 1985, FALSE, '현대 유니콘스 전신. 1985 청보 인수'),
(NULL, '청보 핀토스',     NULL, 1985, 1987, FALSE, '삼미 인수. 1988 태평양으로'),
(NULL, '태평양 돌핀스',   NULL, 1988, 1995, FALSE, '청보 인수. 1996 현대로'),
(NULL, '현대 유니콘스',   NULL, 1996, 2007, FALSE, '2007 해체. 선수단 일부→히어로즈(별개 법인, KBO 계보 단절)'),
-- 쌍방울 레이더스 (1999 해체)
(NULL, '쌍방울 레이더스', NULL, 1991, 1999, FALSE, '1999 해체. 선수 일부→SK(2000 신생)')
ON CONFLICT (team_name, start_year) DO NOTHING;

GRANT ALL ON team_franchises TO playball_user;
GRANT USAGE, SELECT ON SEQUENCE team_franchises_id_seq TO playball_user;
