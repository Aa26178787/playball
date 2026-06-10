# 선수 인스타 핸들 검증 (players.insta_handle)

## 현황 (2026-06-10b — 전수 재검증 완료)
- **등록 370명 / 미등록 ~124명** (활성 기준. 358 전수 dual-viewer 재검증 → 동명이인 4 제거 + naver 신규 13 + 보류해소 3)
- 재검증 내역: VERIFIED 304(이름) + 10(bio이름/구단) / GONE_OR_PRIVATE 17(비공개·삭제 — namu 등급 유지) / 잔여 수동확인 ~22(외국인 로마자 등 본인 판정 다수 포함)
- 원본(namu만 크롤)서 가족계정 ~9건·동명이인 다수 박멸 + **2차 전수서 고팔로워 동명이인 3(아이돌 박지훈 7.6M·MLB 박찬호·배우 이준혁 996K) + 핸들양도 의심 1(신동건) 추가 박멸**

## 핵심 원리
- **IG는 완전 로그인월** — 비로그인 직접 검증 불가 (og메타 제거됨, 계정 존재확인도 실제/가짜 동일 780KB 셸)
- **imginn.com = 우회 (⭐ gold)** — 3rd-party 뷰어가 비로그인서 **프로필 표시이름+바이오+팔로워** 노출. `og:title="이름(@핸들)"` → 선수명 대조로 **본인확인**. 가족계정(꽃집·아기·강아지·자녀)·동명이인(배우·가수·아이돌) 색출의 결정타.
  - imginn 상태: 200=데이터 / **410=비공개 or 삭제** / 429=일시차단(재시도하면 풀림)
  - **NFC 정규화 필수** (imginn 한글 NFD vs DB NFC → 안 하면 강백호=강백호도 불일치)

## 2026-06-10b 전수 재검증 체계 (신규)
- **picnob.com = 2번째 독립 뷰어** (`/profile/{handle}/`, 구 pixwox) — imginn 410/429 폴백. ⚠️ PS5.1 Invoke-WebRequest는 TLS 지문 403 → **curl.exe 필수**
- `verify_dual_all.ps1` — 등록 전수 재검증 (imginn→picnob 폴백). `-InFile/-OutFile/-Limit` 파라미터. 판정: VERIFIED_NAME(표시이름) / **VERIFIED_NAME_BIO(bio에 선수명 — '롯데자이언츠 전준우입니다' 류)** / VERIFIED_TEAM(구단 키워드) / GONE_OR_PRIVATE / NAME_MISMATCH
- `collect_naver_candidates.ps1` — 미등록자 naver 웹검색서 후보 핸들 수집 (검증은 안 함)
- `verify_candidates.ps1` — 후보를 imginn/picnob 본인검증, 첫 VERIFIED 채택
- **NFKC 정규화** — 장식문자 표시이름(𝑯𝒂𝒏𝒘𝒉𝒂·𝗥𝗬𝗨) → 일반문자. NFC만으론 못 풀음
- **팔로워 스윕** — VERIFIED_NAME이어도 bio 팔로워 100K+ & 야구키워드 0 = 동명이인 의심 (박지훈·이준혁 검출 패턴)
- **생년 대조** — 핸들 숫자 vs players.birth_date (조상우 940904=94-09-04 확정 사례)
- ⚠️ **.ps1 한글 리터럴 = UTF-8 BOM 필수** — BOM 없으면 PS5.1이 CP949로 읽어 한글 정규식 깨짐(전부 0건/오판정 사고)
- ⚠️ naver 후보 함정 (VERIFIED_TEAM 단독 채택 금지 사례): 구단 공식계정(always_kia_tigers·busanlottegiants·heroesbaseballclub)·정치인 김민석·식당(타무라 제주·더로아 '삼성'점)·타 선수 계정(나승엽이 김세민 후보로)·바이오에 구단명 있는 팬계정 → **신규 채택 = NAME 계열 or TEAM+본명일치만**

## 검증 도구 (backend/crawler/ — ⚠️ 전부 로컬 PC 전용. 서버 IP는 namu/imginn 403/차단)
- `verify_imginn.ps1` — ⭐ imginn 표시이름 vs 선수명(NFC) 본인검증. 3s+1회재시도. 입력 insta_review.tsv → insta_imginn.csv
- `verify_all_insta_local.ps1` — DB핸들 vs live namu 대조 (팀명 disambig + 야구 가드)
- `verify_wikidata_insta.ps1` — Wikidata P2003(Instagram) 교차. **TLS1.2 + User-Agent 필수**, en desc로 'baseball' 엔티티 매칭 (없으면 throttle/no_entity 폭증). 커버리지 낮음(스타급만)
- `verify_family_insta.ps1` — namu 가족섹션 오추출 색출 (잡은 핸들 앞 200자에 아내/어머니/자녀 등 마커 → FAMILY_SUSPECT)
- `verify_naver_insta.ps1` — naver 검색 보조 (팀계정·뉴스·동명이인 노이즈 多 → 참고용, 단독 신뢰 ❌)
- `verify_fill_missing.ps1` — 누락채우기: **live namu.wiki 직접크롤**로 후보 추출 + imginn 본인검증 (가족 오필 차단)
- `generate_insta_review.ps1` → insta_review.html (전체 리뷰: 사진+핸들+google/namu 링크+체크박스→SQL)
- `generate_missing_html.ps1` → insta_missing.html (누락 입력: 핸들 입력→`id|이름|핸들` 출력)
- 모든 *.tsv/*.csv/*.html/*.log = 로컬 untracked (서버 pull 충돌 방지)

## 검증 등급 (정직)
| 등급 | 대상 | 신뢰 |
|---|---|---|
| 거의 확실 | imginn VERIFIED_NAME(표시이름=선수명)/VERIFIED_TEAM(바이오에 구단) ~290 | 실제 프로필 확인 |
| 높음 | namu ok_self + 비공개(imginn 410) ~30 | namu 등재, IG 직접 못 봄 |
| 약함 | 핸들=이름철자 추정·빈계정 소수 | 확증 못 함 |
| 검증불가 | 핸들변경·비공개 동명이인 | → 앱 신고버튼 |

## ⚠️⚠️ 절대 금지 — Google AI 개요(SGE) 핸들 환각
- AI 개요가 `이니셜_숫자`(m_jun_02·s_wook_38·dong_jin_0…) 패턴으로 **200+ 핸들 통째 지어냄.** 유명선수 몇 개만 실제값.
- 샘플 10개 imginn 검증 → **8개 HTTP_410(존재안함)**. **bulk 적용 시 검증된 진짜 핸들 파괴.**
- **모든 핸들은 imginn 검증 통과분만 적용.** AI 개요·Naver 무검증 적용 금지.

## 2026-06-10b 색출·정정 (전수 재검증)
- **제거 4**: 박지훈(KT) 0529.jihoon.ig=아이돌(7.6M·[RE:FLECT]) · 박찬호(OB·95년생) chanhopark61=MLB 레전드(등번호61) · 이준혁(NC) leejunhyuk05=배우(996.7K) · 신동건(LT) s1nd0ngun=표시이름 tnpzi_ 무관(양도 의심)
- **신규 13**: 화이트 owen_white12·데일 jarryd_dale·강민성 k__a_ng_·장현식 sikkkkkkkkk_·김진욱 _jinukkim_·데이비슨 mattdavidson_24·오영수 yeongsuoh·김민석(OB) kmszz__·타케다 shotatakeda18·디아즈 lewin_dh19·알칸타라 alcantararaul26·유토 yuto.hros.1480·김현수(KT) hyeon0_0soo
- **본인 확인(유지)**: 조상우 940904no.11(생년 일치)·장성우 zzangdoo22(등번호22)·한석현 han9405(94.05생)·외국인 본명 로마자 전원(페라자=Yonathan Perlaza 등)·전준우/노진혁/한준수/장승현(bio 1인칭)·임병욱 lim.bang_(한자 林秉昱=임병욱)
- **보류 6건 수동확인 완료(2026-06-10c — namu 본인문서 SNS란 대조)**: ① skyjun_16 = **김민준(2004) 문서 등재 → id 3958(내야수#5)** 등록 (06년생 투수 김민준 #164는 IG 미상 유지) ② 이민호(2001) 문서 = minoooooooo0o0 → id 348 등록 (0팔로워 = 계정 재생성 추정) ③ **김진수 진짜 핸들 = l._.star_** (김진수(1998) 문서 + imginn disp ⭐️김진수⭐️ + bio 'LG트윈스 김진수') → id 3777 등록. naver 후보 jinsu_jung_a0531 = 동명이인(거부 정당) ④ 박세혁 parksseho — namu 등재 확인 = 본인 확정 유지 ⑤ 강승호 atoi_zila·서건창 seo___bb — namu 등재 = 본인(비공개, '높음' 등급) ⑥ 이상영 _lee_s_y_ — **사용자 직접 확인(2026-06-10) = 본인 확정** (disp '이상빵'=별명. namu/naver론 검증 불가했던 건)
- SQL = `insta_audit_20260610.sql`(+보류 3건 수동 UPDATE) / 산출물 = insta_dual.csv·insta_recheck.csv·insta_fill_verified.csv (로컬) / **최종 370명**

## 색출·정정한 오류 (namu/Wikidata만으론 못 잡던 것 — imginn이 잡음)
- **가족계정**: 양석환 luvinbloom(꽃집)→ysghw_53 · 김재윤 extraordinaryleia(아기)→제거 · 김도영 im.__.zandi(강아지)→do_0000 · 류지혁 i_hyun_deun_el(자녀)→ryujihyuk_ · 허경민 heo_jamong_(자몽맘=아내)→kyoungmin1623 · 양창섭 cello_min_(자녀)→제거 · 박동원/이유찬/오영수 가족·없음 → 제거
- **동명이인(이름만 맞음)**: 김종수 alrun85(배우)·박정현 lenaparklive(가수 Lena Park)·박지훈 0529.jihoon.ig(아이돌 7.6M) → 야구 바이오 부재로 거부, 진짜는 따로(6.3_cm·jeonghyeon8719)
- **핸들 교체**: 임기영→ki_young17, 전병우→j_byeong_w, 현도훈→dohoon______, 양재훈→jax_1uxn, 박시후→shu_57_, 장준원→j_jun_won, 임종성→dlawhdtjd_, 김상수→kim.ss__7

## 추가 워크플로
1. **실제 인스타 앱/웹 또는 namu SNS란**에서 핸들 확인 (Google AI 개요 ❌)
2. `generate_missing_html.ps1` → insta_missing.html서 핸들 입력 → Generate → `id|이름|핸들`
3. **imginn 본인검증** (표시이름=선수명 or 바이오에 구단핸들) → 통과만 `UPDATE players SET insta_handle`
4. 신규/변경 오류 = **앱 신고버튼** (`POST /players/{id}/report-insta` → `insta_handle_reports` 테이블, psql 검토)

## DB
- `players.insta_handle`
- `insta_handle_reports(id, player_id FK CASCADE, handle, user_id FK SET NULL, created_at)` — 사용자 신고
- ⚠️ 데이터 이슈: **양현종·이태양 = KIA·키움 양쪽 중복** (동명이인 team_id 오배정 의심, 미해결)
