-- 우천중단(rain delay) 플래그 (2026-06-23)
-- 경기 진행 중 일시 중단 상태. status는 '진행' 유지 + suspended 오버레이.
-- 재개/종료/취소 시 scheduler가 FALSE로 복귀. 기존 4값 status enum/쿼리 무손상.
ALTER TABLE games ADD COLUMN IF NOT EXISTS suspended BOOLEAN DEFAULT FALSE;
