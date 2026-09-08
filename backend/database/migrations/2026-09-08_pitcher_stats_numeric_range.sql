-- 투수 극단값(소수 이닝, 100+ ERA 등)이 일일 스케줄러를 중단시키지 않게 한다.
-- 기존 정밀도보다 넓히기만 하므로 데이터 손실 없이 반복 적용할 수 있다.
ALTER TABLE pitcher_stats
    ALTER COLUMN era       TYPE NUMERIC(6,2),
    ALTER COLUMN whip      TYPE NUMERIC(6,2),
    ALTER COLUMN war       TYPE NUMERIC(7,2),
    ALTER COLUMN fip       TYPE NUMERIC(7,2),
    ALTER COLUMN k_per_9   TYPE NUMERIC(7,2),
    ALTER COLUMN bb_per_9  TYPE NUMERIC(7,2),
    ALTER COLUMN h_per_9   TYPE NUMERIC(7,2),
    ALTER COLUMN hr_per_9  TYPE NUMERIC(7,2),
    ALTER COLUMN k_bb      TYPE NUMERIC(7,2),
    ALTER COLUMN babip     TYPE NUMERIC(4,3),
    ALTER COLUMN wpct      TYPE NUMERIC(4,3);
