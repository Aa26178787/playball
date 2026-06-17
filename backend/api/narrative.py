"""내러티브 엔진 — 경기 데이터 → 한국어 문구 (템플릿 v1, DB 없음).

generate 인터페이스를 추상화: 추후 LLM 백엔드는 game_review/live_caption을
동일 시그니처로 교체하면 된다. 모든 함수는 입력 누락/빈값에 안전(예외 던지지 않음).
"""


def mvp_line(mvp: dict) -> str:
    """타자 성적 → '1홈런 3안타 4타점' 류 한 줄. 빈 입력은 빈 문자열."""
    parts = []
    h = mvp.get("hits") or 0
    hr = mvp.get("home_runs") or 0
    rbi = mvp.get("rbis") or 0
    if hr:
        parts.append(f"{hr}홈런")
    if h:
        parts.append(f"{h}안타")
    if rbi:
        parts.append(f"{rbi}타점")
    return " ".join(parts)


def _template_review(facts: dict) -> str:
    """종료 한줄평 (템플릿 폴백). 분기 우선순위: 무승부 > 끝내기 > 연장 > 대승 > 접전 > 평이."""
    h = facts.get("home_team", "")
    a = facts.get("away_team", "")
    hs = facts.get("home_score", 0) or 0
    as_ = facts.get("away_score", 0) or 0

    if hs == as_:
        return f"{h} {hs}-{as_} {a}, 팽팽한 무승부"

    winner = h if hs > as_ else a
    loser = a if hs > as_ else h
    wscore, lscore = max(hs, as_), min(hs, as_)
    diff = wscore - lscore

    if facts.get("walkoff"):
        lead = f"{winner}, {wscore}-{lscore} 끝내기 승리"
    elif facts.get("extra_innings"):
        lead = f"{winner}, 연장 접전 끝 {wscore}-{lscore} 승"
    elif facts.get("comeback"):
        lead = f"{winner}, 뒤지다 뒤집은 {wscore}-{lscore} 역전승"
    elif diff >= 8:
        lead = f"{winner}, {wscore}-{lscore} 대승"
    elif diff <= 1:
        lead = f"{winner}, {wscore}-{lscore} 진땀승"
    else:
        lead = f"{winner}, {wscore}-{lscore}로 {loser} 제압"

    # 결정적 장면 한 조각 (있으면 우선 노출 — 결과 나열 탈피)
    kp = facts.get("key_play")
    if kp and kp.get("batter") and kp.get("text"):
        sit = f"{kp.get('inning')}회{kp.get('half', '')}".strip()
        return f"{lead}. {sit} {kp['batter']}의 {kp['text']}가 승부처"

    mvp_name = facts.get("mvp_name", "")
    mvp_l = facts.get("mvp_line", "")
    if mvp_name and mvp_l:
        return f"{lead}. {mvp_name} {mvp_l}"
    if facts.get("win_pitcher"):
        return f"{lead}. 승리투수 {facts['win_pitcher']}"
    return lead


def _runners_phrase(b1: bool, b2: bool, b3: bool) -> str:
    if b1 and b2 and b3:
        return "만루"
    n = int(b1) + int(b2) + int(b3)
    if n == 0:
        return "주자 없음"
    if b2 or b3:
        return "득점권 주자"
    return "1루 주자"


def live_caption(state: dict) -> str:
    """relay current_state → 짧은 상황 한 줄. 경기 외/데이터 부족이면 빈 문자열."""
    inning = state.get("inning") or state.get("current_inning") or 0
    if not inning:
        return ""
    half = state.get("half") or state.get("inning_half") or ""
    out = state.get("out", 0) or 0
    b1 = bool(state.get("base1"))
    b2 = bool(state.get("base2"))
    b3 = bool(state.get("base3"))
    hs = state.get("home_score", 0) or 0
    as_ = state.get("away_score", 0) or 0
    diff = abs(hs - as_)

    runners = _runners_phrase(b1, b2, b3)
    situation = f"{inning}회{half} {out}사 {runners}"

    if diff == 0:
        tone = "동점 승부"
    elif diff <= 1:
        tone = "1점차 접전"
    elif diff <= 3:
        tone = f"{diff}점차"
    else:
        tone = f"{diff}점차 리드"
    return f"{situation}, {tone}"


# ── LLM 백엔드 (Gemini 무료 API) — 실패/키없음 시 _template_review 폴백 ──
# env GEMINI_API_KEY(Google AI Studio 무료), GEMINI_MODEL(기본 gemini-2.5-flash).
# 검증된 facts만 프롬프트에 — 스탯/사실 환각 금지. 1~2문장 한국어 평문.
def _gemini_review(facts: dict) -> str:
    import os
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        return ""
    from google import genai
    from google.genai import types

    h = facts.get("home_team", "")
    a = facts.get("away_team", "")
    hs = facts.get("home_score", 0) or 0
    as_ = facts.get("away_score", 0) or 0
    lines = [f"{h} {hs} : {as_} {a} (홈 {h} / 원정 {a})"]
    if hs != as_:
        lines.append(f"승팀: {h if hs > as_ else a}")
    if facts.get("walkoff"):
        lines.append("끝내기 승리")
    if facts.get("extra_innings"):
        lines.append("연장 경기")
    if facts.get("win_pitcher"):
        lines.append(f"승리투수: {facts['win_pitcher']}")
    if facts.get("save_pitcher"):
        lines.append(f"세이브: {facts['save_pitcher']}")
    if facts.get("mvp_name"):
        ml = facts.get("mvp_line", "")
        lines.append(f"수훈선수: {facts['mvp_name']}" + (f" ({ml})" if ml else ""))
    if facts.get("comeback"):
        lines.append(f"{h if hs > as_ else a}가 경기 도중 뒤지다 역전한 역전승")
    kp = facts.get("key_play")
    if kp and kp.get("batter"):
        sit = f"{kp.get('inning')}회{kp.get('half', '')} {kp.get('outs', 0)}사 {kp.get('runners', '')}".strip()
        txt = kp.get("text") or ""
        desc = f"승부를 가른 결정적 장면: {sit}에서 {kp['batter']}"
        if txt:
            desc += f"의 '{txt}'"
        desc += f" (홈 승리확률 {kp.get('swing', 0)}%p 변동)"
        lines.append(desc)
    fact_block = "\n".join(f"- {x}" for x in lines)

    prompt = (
        "다음 KBO 프로야구 경기 정보로 한국어 한줄평을 2~3문장으로 작성해라.\n"
        "규칙:\n"
        "1) 아래 '사실'에 적힌 것만 사용한다. 사실에 없는 점수·선수·기록·이닝·안타수는 절대 언급하지 않는다(추측·과장 금지).\n"
        "2) 단순히 결과만 나열하지 말고, '결정적 장면'과 '역전' 같은 경기 흐름·상황을 자연스럽게 녹여 생생하게 묘사해라.\n"
        "3) '승리확률 N%p 변동' 같은 수치 표현이나 괄호 안 부연은 본문에 그대로 쓰지 말고, 그 장면이 승부처였다는 뉘앙스로만 표현해라.\n"
        "4) '역전'·'대역전'은 사실에 '역전승'이라고 적혀 있을 때만 언급한다(없으면 역전이라 단정하지 마라).\n"
        "5) 야구 중계 자막처럼 담백하고 팬 친화적인 톤. 마크다운·따옴표·줄바꿈 없이 평문으로.\n\n"
        f"사실:\n{fact_block}\n\n한줄평:"
    )
    model = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash")
    client = genai.Client(api_key=key, http_options=types.HttpOptions(timeout=12000))  # 12s (Gemini 최소 10s)
    resp = client.models.generate_content(
        model=model, contents=prompt,
        config=types.GenerateContentConfig(
            temperature=0.8, max_output_tokens=400,
            # gemini-2.5 기본 thinking이 출력토큰 소진→본문 잘림. 한줄평엔 thinking 불요.
            thinking_config=types.ThinkingConfig(thinking_budget=0),
        ),
    )
    text = (resp.text or "").strip().strip('"').strip("'").replace("\n", " ").strip()
    # 안전: 비었거나 비정상 길이면 폴백
    if not text or len(text) > 300:
        return ""
    return text


def game_review(facts: dict) -> str:
    """종료 한줄평. Gemini(무료) 우선 → 실패/키없음 시 템플릿 폴백(절대 안 죽음)."""
    try:
        g = _gemini_review(facts)
        if g:
            return g
    except Exception as e:
        import sys
        print(f"[narrative] gemini 폴백({type(e).__name__}): {e}", file=sys.stderr)
    return _template_review(facts)
