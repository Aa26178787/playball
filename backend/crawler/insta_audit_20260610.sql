-- 인스타 핸들 전수 재검증 (2026-06-10 dual-viewer: imginn+picnob, NFKC+bio이름+팔로워 스윕)
-- 제거: 동명이인/오등록 (근거 = 팔로워 규모/표시이름/생년 대조)
UPDATE players SET insta_handle = NULL WHERE id = 4169; -- 박지훈(KT 투수): 0529.jihoon.ig = 아이돌 박지훈(7.6M, bio [RE:FLECT])
UPDATE players SET insta_handle = NULL WHERE id = 152;  -- 박찬호(OB 95년 내야수): chanhopark61 = MLB 레전드 박찬호(73년생, 등번호61)
UPDATE players SET insta_handle = NULL WHERE id = 238;  -- 이준혁(NC): leejunhyuk05 = 배우 이준혁(996.7K, 야구흔적 0)
UPDATE players SET insta_handle = NULL WHERE id = 4157; -- 신동건(LT 07년 투수): s1nd0ngun 표시이름 tnpzi_ 무관 = 핸들 변경/양도 의심
-- 신규 등록: imginn/picnob 본인검증 통과 (표시이름=본명 or bio에 구단/본인 명시)
UPDATE players SET insta_handle = 'owen_white12'    WHERE id = 205;  -- 화이트(HH): disp Owen White
UPDATE players SET insta_handle = 'jarryd_dale'     WHERE id = 179;  -- 데일(HT): disp Jarryd Dale + @always_kia_tigers
UPDATE players SET insta_handle = 'k__a_ng_'        WHERE id = 3783; -- 강민성(KT): disp 강민성 + @ktwiz.pr
UPDATE players SET insta_handle = 'sikkkkkkkkk_'    WHERE id = 353;  -- 장현식(LG): disp 장현식 + @lgtwinsbaseballclub
UPDATE players SET insta_handle = '_jinukkim_'      WHERE id = 282;  -- 김진욱(LT): disp 김진욱 + @busanlottegiants
UPDATE players SET insta_handle = 'mattdavidson_24' WHERE id = 134;  -- 데이비슨(NC): disp Matt Davidson + @ncdinos2011
UPDATE players SET insta_handle = 'yeongsuoh'       WHERE id = 187;  -- 오영수(NC): disp 오영수 Yeongsu Oh
UPDATE players SET insta_handle = 'kmszz__'         WHERE id = 154;  -- 김민석(OB): disp 김민석 + @doosanbears.1982
UPDATE players SET insta_handle = 'shotatakeda18'   WHERE id = 290;  -- 타케다(SK): disp 武田翔太 + bio SSG Landers
UPDATE players SET insta_handle = 'lewin_dh19'      WHERE id = 13;   -- 디아즈(SS): disp Lewin Diaz + bio 삼성라이온즈
UPDATE players SET insta_handle = 'alcantararaul26' WHERE id = 229;  -- 알칸타라(WO): disp Raul Alcantara
UPDATE players SET insta_handle = 'yuto.hros.1480'  WHERE id = 262;  -- 유토(WO): disp 金久保優斗 + bio Kiwoom Heroes#4
UPDATE players SET insta_handle = 'hyeon0_0soo'     WHERE id = 140;  -- 김현수(KT 88년 외야수=LG서 이적): disp 김현수(917K)
