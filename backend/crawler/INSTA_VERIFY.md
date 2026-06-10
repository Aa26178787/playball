# 선수 인스타 핸들 검증 (players.insta_handle)

## 현황 (2026-06-10)
- **등록 358명 / 미등록 140명** (활성 2026 batter/pitcher_stats 기준, 미등록 중 외국인 ~31)
- imginn 본인확인 ~290 + namu 본인섹션(비공개) ~30 + 이름철자 추정 소수
- 원본(namu만 크롤)서 가족계정 ~9건·동명이인 다수 박멸함

## 핵심 원리
- **IG는 완전 로그인월** — 비로그인 직접 검증 불가 (og메타 제거됨, 계정 존재확인도 실제/가짜 동일 780KB 셸)
- **imginn.com = 우회 (⭐ gold)** — 3rd-party 뷰어가 비로그인서 **프로필 표시이름+바이오+팔로워** 노출. `og:title="이름(@핸들)"` → 선수명 대조로 **본인확인**. 가족계정(꽃집·아기·강아지·자녀)·동명이인(배우·가수·아이돌) 색출의 결정타.
  - imginn 상태: 200=데이터 / **410=비공개 or 삭제** / 429=일시차단(재시도하면 풀림)
  - **NFC 정규화 필수** (imginn 한글 NFD vs DB NFC → 안 하면 강백호=강백호도 불일치)

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
