"""
FCM 푸시 알림 서비스
Firebase Admin SDK 사용.
서비스 계정 키: ~/playball/backend/firebase-service-account.json
"""
import os
import logging
from database.connection import get_connection

logger = logging.getLogger(__name__)

_app = None


def _get_app():
    global _app
    if _app is not None:
        return _app
    try:
        import firebase_admin
        from firebase_admin import credentials
        key_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "firebase-service-account.json",
        )
        if not os.path.exists(key_path):
            return None
        cred = credentials.Certificate(key_path)
        _app = firebase_admin.initialize_app(cred)
        return _app
    except Exception as e:
        logger.error(f"[FCM] Firebase 초기화 실패: {e}")
        return None


# ── 토큰 조회 헬퍼 ────────────────────────────────────────────────────────────

def _get_targets(notify_type: str, team_ids: list[int]) -> list[tuple[int, str]]:
    """
    경기 알림용. user_settings(notify_{type}, notify_my_team_only) 반영.
    user_settings 미설정 → 기본값(전부 ON, my_team_only=OFF).
    """
    allowed = ('notify_game_start', 'notify_score_change', 'notify_game_end',
               'notify_walkoff', 'notify_starter_ko',  # notify_starter_ko = 투수 교체 알림용 재사용
               'notify_clutch', 'notify_briefing')  # 06-13 전용 토글 신설
    if notify_type not in allowed:
        return []
    conn = get_connection()
    if not conn:
        return []
    try:
        cur = conn.cursor()
        cur.execute(f"""
            SELECT DISTINCT pt.user_id, pt.token
            FROM push_tokens pt
            LEFT JOIN user_settings us ON us.user_id = pt.user_id
            WHERE COALESCE(us.{notify_type}, TRUE) = TRUE
              AND (
                COALESCE(us.notify_my_team_only, FALSE) = FALSE
                OR EXISTS (
                    SELECT 1 FROM user_favorite_teams uft
                    WHERE uft.user_id = pt.user_id
                      AND uft.team_id = ANY(%s)
                )
              )
        """, (team_ids,))
        return cur.fetchall()
    except Exception as e:
        logger.error(f"[FCM] 토큰 조회 실패: {e}")
        return []
    finally:
        conn.close()


def _get_team_fan_targets(team_id: int, setting_col: str = None) -> list[tuple[int, str]]:
    """해당 팀 마이팀 팬의 (user_id, token). setting_col 지정 시 해당 설정 ON인 유저만."""
    conn = get_connection()
    if not conn:
        return []
    try:
        cur = conn.cursor()
        if setting_col:
            cur.execute(f"""
                SELECT DISTINCT pt.user_id, pt.token
                FROM push_tokens pt
                JOIN user_favorite_teams uft ON uft.user_id = pt.user_id
                LEFT JOIN user_settings us ON us.user_id = pt.user_id
                WHERE uft.team_id = %s
                  AND COALESCE(us.{setting_col}, TRUE) = TRUE
            """, (team_id,))
        else:
            cur.execute("""
                SELECT DISTINCT pt.user_id, pt.token
                FROM push_tokens pt
                JOIN user_favorite_teams uft ON uft.user_id = pt.user_id
                WHERE uft.team_id = %s
            """, (team_id,))
        return cur.fetchall()
    except Exception as e:
        logger.error(f"[FCM] 팬 토큰 조회 실패: {e}")
        return []
    finally:
        conn.close()


def _get_player_fan_targets(player_id: int, setting_col: str = 'notify_roster') -> list[tuple[int, str]]:
    """즐겨찾기 선수 팬의 (user_id, token). setting_col ON인 유저만."""
    conn = get_connection()
    if not conn:
        return []
    try:
        cur = conn.cursor()
        cur.execute(f"""
            SELECT DISTINCT pt.user_id, pt.token
            FROM push_tokens pt
            JOIN user_favorite_players ufp ON ufp.user_id = pt.user_id
            LEFT JOIN user_settings us ON us.user_id = pt.user_id
            WHERE ufp.player_id = %s
              AND COALESCE(us.{setting_col}, TRUE) = TRUE
        """, (player_id,))
        return cur.fetchall()
    except Exception as e:
        logger.error(f"[FCM] 선수 팬 토큰 조회 실패: {e}")
        return []
    finally:
        conn.close()


def _get_user_targets(user_id: int) -> list[tuple[int, str]]:
    """특정 유저의 (user_id, token) 목록. notify_comment ON인 경우만."""
    conn = get_connection()
    if not conn:
        return []
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT pt.user_id, pt.token
            FROM push_tokens pt
            LEFT JOIN user_settings us ON us.user_id = pt.user_id
            WHERE pt.user_id = %s
              AND COALESCE(us.notify_comment, TRUE) = TRUE
        """, (user_id,))
        return cur.fetchall()
    except Exception:
        return []
    finally:
        conn.close()


# ── 공통 발송 (푸시 게이트웨이 — 메가B) ──────────────────────────────────────
# 모든 notify_* → _send 단일 경유. quiet hours / Android 채널 라우팅 여기서 일괄.

# ntype → Android 알림 채널 (클라 main.dart에서 동일 id 3종 생성)
_CHANNEL_LIVE = 'playball_live'        # 경기 진행 (스코어/결정적순간/끝내기 등)
_CHANNEL_MYTEAM = 'playball_myteam'    # 마이팀/선수 소식 (순위/등록말소/마일스톤/브리핑)
_CHANNEL_COMMUNITY = 'playball_community'

_LIVE_TYPES = {
    'game_start', 'score_change', 'comeback', 'game_end', 'extra_innings',
    'cancelled', 'walkoff', 'clutch_moment', 'pitcher_change', 'starter_announced',
}
_COMMUNITY_TYPES = {'new_comment'}


def _channel_for(ntype: str) -> str:
    if ntype in _LIVE_TYPES:
        return _CHANNEL_LIVE
    if ntype in _COMMUNITY_TYPES:
        return _CHANNEL_COMMUNITY
    return _CHANNEL_MYTEAM


def _is_quiet_now() -> bool:
    """KST 23:30~07:30 = quiet hours (연장전도 23:30 전 대부분 종료)"""
    from datetime import datetime, timedelta, timezone
    now = datetime.now(timezone.utc) + timedelta(hours=9)
    hm = now.hour * 60 + now.minute
    return hm >= 23 * 60 + 30 or hm < 7 * 60 + 30


def _filter_quiet_optout(user_ids: list[int]) -> set[int]:
    """quiet hours 중에도 푸시 받겠다고 한(notify_quiet=FALSE) 유저 집합"""
    if not user_ids:
        return set()
    conn = get_connection()
    if not conn:
        return set()
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT user_id FROM user_settings
            WHERE user_id = ANY(%s) AND COALESCE(notify_quiet, TRUE) = FALSE
        """, (user_ids,))
        return {r[0] for r in cur.fetchall()}
    except Exception:
        return set()
    finally:
        conn.close()


def _save_notifications(user_ids: list[int], title: str, body: str,
                        ntype: str, game_id: int | None):
    if not user_ids:
        return
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        cur.executemany(
            "INSERT INTO user_notifications (user_id, title, body, type, game_id) VALUES (%s,%s,%s,%s,%s)",
            [(uid, title, body, ntype, game_id) for uid in user_ids],
        )
        conn.commit()
        cur.close()
    except Exception as e:
        logger.error(f"[FCM] 알림 저장 실패: {e}")
    finally:
        conn.close()


def _remove_invalid_tokens(tokens: list[str]):
    if not tokens:
        return
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM push_tokens WHERE token = ANY(%s)", (tokens,))
        conn.commit()
        cur.close()
    except Exception:
        pass
    finally:
        conn.close()


def _collapse_key(ntype: str, game_id: int | None, data: dict) -> str:
    """트레이 collapse_key / Android tag. 같은 키 = 트레이서 최신 알림이 이전 것 교체.
    - game_id 有: 경기·타입당 1슬롯 (고빈도 score_change가 Android 50개 캡 채우는 것 방지).
    - game_id 無: data의 player_id/team_id로 엔티티별 분리. 없으면 bare ntype(하위호환).
    ⚠️ bare ntype이면 같은 타입 다수 이벤트(예: 같은 날 여러 선수 등록말소)가 한 슬롯으로
    합쳐져 마지막 1건만 트레이에 남음 — 06-30 오재원/정민규 등말소 1건 누락 사고 원인."""
    if game_id:
        return f"{ntype}_{game_id}"
    disc = data.get('player_id') or data.get('team_id')
    return f"{ntype}_{disc}" if disc else ntype


def _send(targets: list[tuple[int, str]], title: str, body: str,
          data: dict, ntype: str, game_id: int | None):
    if not targets:
        return
    user_ids = list(dict.fromkeys(t[0] for t in targets))
    # 인앱 알림함은 quiet hours 무관 전원 저장
    _save_notifications(user_ids, title, body, ntype, game_id)
    # quiet hours: opt-out(받겠다) 유저만 푸시 (기본 = 억제)
    if _is_quiet_now():
        allow = _filter_quiet_optout(user_ids)
        targets = [(uid, tok) for uid, tok in targets if uid in allow]
        if not targets:
            logger.info(f"[FCM] quiet hours 억제: {title}")
            return
    tokens = [t[1] for t in targets]
    if _get_app() is None:
        return
    try:
        from firebase_admin import messaging
        # 같은 (타입,경기) 알림은 tag로 트레이서 교체(누적 X) → Android 50개/앱 캡
        # (MAX_PACKAGE_NOTIFICATIONS) 도달 시 이후 푸시 무음 드롭되던 문제 방지.
        # 각 이벤트는 그대로 재알림(소리/진동), 트레이만 경기·타입당 1개 유지.
        # collapse_key = 기기 오프라인 시 미수신분도 최신만 전달.
        collapse = _collapse_key(ntype, game_id, data)
        # Android high priority + APNs alert → Doze 우회, background에서도 즉시 표시
        msg = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in data.items()},
            android=messaging.AndroidConfig(
                priority='high',
                collapse_key=collapse,
                notification=messaging.AndroidNotification(
                    channel_id=_channel_for(ntype),
                    sound='default',
                    default_vibrate_timings=True,
                    tag=collapse,
                ),
            ),
            apns=messaging.APNSConfig(
                headers={
                    'apns-priority': '10',
                    'apns-collapse-id': collapse[:64],
                },
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound='default', badge=1),
                ),
            ),
            tokens=tokens,
        )
        resp = messaging.send_each_for_multicast(msg)
        logger.info(f"[FCM] {title}: {resp.success_count}성공/{resp.failure_count}실패")
        _INVALID_TOKEN_MSGS = (
            'registration-token-not-registered',
            'Requested entity was not found',
            'invalid-registration-token',
            'not a valid FCM registration token',  # 형식 불량 (InvalidArgumentError)
            'SenderId mismatch',                   # 타 프로젝트 토큰
        )
        failed = [
            tokens[i] for i, r in enumerate(resp.responses)
            if not r.success and r.exception and
            any(m in str(r.exception) for m in _INVALID_TOKEN_MSGS)
        ]
        _remove_invalid_tokens(failed)
    except Exception as e:
        logger.error(f"[FCM] 발송 실패: {e}")


# ── 경기 알림 (user_settings 반영) ───────────────────────────────────────────

def notify_game_start(game_id: int, home_team: str, away_team: str,
                      home_team_id: int, away_team_id: int,
                      start_time: str = '',
                      home_starter: str = '', away_starter: str = ''):
    targets = _get_targets('notify_game_start', [home_team_id, away_team_id])
    time_str = f" ({start_time})" if start_time else ""
    title = f"⚾ {home_team} vs {away_team} 시작!{time_str}"
    if home_starter and away_starter:
        body = f"홈: {home_team} ({home_starter}) vs 원정: {away_team} ({away_starter})"
    elif home_starter or away_starter:
        body = f"{home_team}(홈) vs {away_team}(원정) | 선발: {home_starter or away_starter}"
    else:
        body = f"{home_team}(홈) vs {away_team}(원정) 경기가 시작되었습니다."
    _send(targets, title, body,
          {"game_id": str(game_id), "type": "game_start"}, "game_start", game_id)


def notify_score_change(game_id: int, home_team: str, away_team: str,
                        home_score: int, away_score: int,
                        home_team_id: int, away_team_id: int,
                        is_comeback: bool = False,
                        big_comeback: bool = False,
                        inning: int = 0, inning_half: str = '',
                        scoring_team: str = '',
                        runs: int = 1,
                        batter: str = '', pitcher: str = '', play_text: str = '',
                        stuff: str = '', speed: int = 0, homein: list = None,
                        pitch_num: int = 0):
    import re as _re
    targets = _get_targets('notify_score_change', [home_team_id, away_team_id])
    half_str = (inning_half if inning_half in ('초', '말')
                else '초' if inning_half == 'top'
                else '말' if inning_half == 'bottom'
                else '')
    inning_str = f" [{inning}회 {half_str}]" if inning > 0 and half_str else f" [{inning}회]" if inning > 0 else ""

    # 제목: 이모지 + 스코어 + 이닝 (스코어가 핵심 정보)
    if big_comeback:
        title = f"🔥 {home_team} {home_score}:{away_score} {away_team}{inning_str}"
    elif is_comeback:
        title = f"⚡ {home_team} {home_score}:{away_score} {away_team}{inning_str}"
    else:
        title = f"⚾ {home_team} {home_score}:{away_score} {away_team}{inning_str}"

    # play_text에서 "N구 " 접두사 분리 → 투구 번호 + 순수 타구 결과
    clean_text = play_text
    embedded_num = 0
    if play_text:
        m = _re.match(r'^(\d+)구\s+(.+)', play_text)
        if m:
            embedded_num = int(m.group(1))
            clean_text = m.group(2)

    # "볼" 단독 → 볼넷 득점 상황
    if clean_text and clean_text.strip() == '볼':
        clean_text = '볼넷'

    # clean_text가 batter 이름으로 시작하면 prefix 제거 (중복 표시 방지)
    # 예: batter="박찬호", clean_text="박찬호 : 우익수 오른쪽 3루타" → "우익수 오른쪽 3루타"
    if batter and clean_text:
        _stripped = clean_text.lstrip()
        if _stripped.startswith(batter):
            _rest = _stripped[len(batter):].lstrip()
            # 공통 구분자(: / : 등) 제거
            for _sep in (':', ':', '-', '–', '—'):
                if _rest.startswith(_sep):
                    _rest = _rest[len(_sep):].lstrip()
                    break
            if _rest:
                clean_text = _rest

    display_pitch_num = embedded_num or pitch_num

    lines = []

    # 폭투/보크/패스트볼/볼넷은 타점 아님 → "득점" 표기
    _NO_RBI_KW = ('폭투', '보크', '패스트볼', '낫아웃', '볼넷')
    is_no_rbi = clean_text and any(kw in clean_text for kw in _NO_RBI_KW)

    team_label = f"[{scoring_team}] " if scoring_team else ""

    # 1줄: [득점팀] 타자 vs 투수 — 타구 결과 (n타점/득점)
    if batter:
        line1 = f"{team_label}{batter} vs {pitcher}" if pitcher else f"{team_label}{batter}"
        if clean_text:
            line1 += f" — {clean_text}"
        if runs > 0:
            line1 += f" ({runs}{'득점' if is_no_rbi else '타점'})"
        lines.append(line1)
    elif clean_text:
        lines.append(f"{team_label}{clean_text}")
    elif team_label:
        lines.append(f"{team_label}{runs}득점")

    # 2줄: 투구 번호 + 구종 + 구속
    if stuff:
        pitch_line = f"{display_pitch_num}구 {stuff}" if display_pitch_num > 0 else stuff
        if speed > 0:
            pitch_line += f" {speed}km/h"
        lines.append(pitch_line)

    # 홈인
    if homein:
        lines.append(f"홈인: {', '.join(homein)}")

    body = "\n".join(lines) if lines else f"{scoring_team or home_team} {runs}득점"
    ntype = "comeback" if is_comeback else "score_change"
    _send(targets, title, body,
          {"game_id": str(game_id), "type": ntype}, ntype, game_id)


def notify_game_end(game_id: int, home_team: str, away_team: str,
                    home_score: int, away_score: int,
                    home_team_id: int, away_team_id: int):
    targets = _get_targets('notify_game_end', [home_team_id, away_team_id])
    if home_score > away_score:
        winner, loser = home_team, away_team
        result_emoji = "🏆"
    elif away_score > home_score:
        winner, loser = away_team, home_team
        result_emoji = "🏆"
    else:
        winner = loser = ''
        result_emoji = "🤝"
    diff = abs(home_score - away_score)
    title = (f"{result_emoji} {winner} {home_score}:{away_score} 승리!"
             if winner else f"🤝 {home_team} {home_score}:{away_score} 무승부")
    body = (f"{home_team} {home_score} : {away_score} {away_team} | {winner} {diff}점 차 승리"
            if winner else f"{home_team} {home_score} : {away_score} {away_team}")
    _send(targets, title, body,
          {"game_id": str(game_id), "type": "game_end"}, "game_end", game_id)


# ── 추가 경기 상황 알림 ───────────────────────────────────────────────────────

def notify_extra_innings(game_id: int, home_team: str, away_team: str,
                         inning: int, home_team_id: int, away_team_id: int):
    """연장전 돌입 — 마이팀 팬에게 (score_change 설정 공유)"""
    targets = _get_targets('notify_score_change', [home_team_id, away_team_id])
    _send(targets,
          f"🔄 연장 {inning}회 돌입!",
          f"{home_team} vs {away_team} — 연장전이 시작됩니다.",
          {"game_id": str(game_id), "type": "extra_innings"}, "extra_innings", game_id)


def notify_game_cancelled(game_id: int, home_team: str, away_team: str,
                          home_team_id: int, away_team_id: int):
    """우천/기타 취소 — 마이팀 팬에게"""
    targets = _get_targets('notify_game_start', [home_team_id, away_team_id])
    _send(targets,
          "🌧️ 경기 취소",
          f"{home_team} vs {away_team} 경기가 취소되었습니다.",
          {"game_id": str(game_id), "type": "cancelled"}, "cancelled", game_id)


def notify_rain_delay(game_id: int, home_team: str, away_team: str,
                      home_team_id: int, away_team_id: int):
    """우천중단(경기 중 일시 중단) — 양 팀 팬에게 (취소와 동일 타겟)"""
    targets = _get_targets('notify_game_start', [home_team_id, away_team_id])
    _send(targets,
          "🌧️ 우천 중단",
          f"{home_team} vs {away_team} 경기가 우천으로 중단됐습니다.",
          {"game_id": str(game_id), "type": "rain_delay"}, "rain_delay", game_id)


# ── 순위 알림 ─────────────────────────────────────────────────────────────────

def notify_rank_change(team_id: int, team_name: str,
                       old_rank: int, new_rank: int, games_behind: float):
    """순위 변동 — 해당 팀 마이팀 팬에게 (notify_rank_change ON)"""
    targets = _get_team_fan_targets(team_id, 'notify_rank_change')
    direction = "▲" if new_rank < old_rank else "▼"
    moved = abs(old_rank - new_rank)
    if new_rank == 1:
        gb_str = " — 단독 선두!"
    elif games_behind is not None and games_behind > 0:
        gb_str = f" (1위와 {games_behind:.1f}게임차)"
    else:
        gb_str = ""
    title = f"📊 {team_name} {direction}{moved}계단 → {new_rank}위"
    body = f"{old_rank}위 → {new_rank}위 변동{gb_str}"
    _send(targets, title, body,
          {"team_id": str(team_id), "type": "rank_change"}, "rank_change", None)


# ── 연승/연패 알림 ────────────────────────────────────────────────────────────

def notify_streak(team_id: int, team_name: str, count: int, is_winning: bool,
                  rank: int = 0):
    targets = _get_team_fan_targets(team_id, 'notify_streak')
    rank_str = f" (현재 {rank}위)" if rank > 0 else ""
    if is_winning:
        _send(targets,
              f"🔥 {team_name} {count}연승!",
              f"{team_name} {count}연승 행진 중!{rank_str} 다음 경기도 응원해요.",
              {"team_id": str(team_id), "type": "winning_streak"}, "winning_streak", None)
    else:
        _send(targets,
              f"😰 {team_name} {count}연패",
              f"{team_name} {count}연패 중...{rank_str} 반등을 기다려요.",
              {"team_id": str(team_id), "type": "losing_streak"}, "losing_streak", None)


# ── 로스터 알림 ───────────────────────────────────────────────────────────────

def notify_roster_change(player_id: int, player_name: str, change_type: str):
    """즐겨찾기 선수 등록/말소 알림"""
    targets = _get_player_fan_targets(player_id)
    if not targets:
        return
    emoji = "✅" if "등록" in change_type else "❌"
    _send(targets,
          f"{emoji} {player_name} {change_type}",
          f"즐겨찾기 선수 {player_name}이(가) {change_type} 되었습니다.",
          {"player_id": str(player_id), "type": "roster_change"}, "roster_change", None)


def notify_team_roster_change(team_id: int, player_id: int, player_name: str, change_type: str):
    """마이팀 등록말소 - 해당 선수를 즐겨찾기하지 않은 팀 팬에게 (중복 방지)"""
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT DISTINCT pt.user_id, pt.token
            FROM push_tokens pt
            JOIN user_favorite_teams uft ON uft.user_id = pt.user_id
            LEFT JOIN user_settings us ON us.user_id = pt.user_id
            WHERE uft.team_id = %s
              AND COALESCE(us.notify_roster, TRUE) = TRUE
              AND NOT EXISTS (
                  SELECT 1 FROM user_favorite_players ufp
                  WHERE ufp.user_id = pt.user_id AND ufp.player_id = %s
              )
        """, (team_id, player_id))
        targets = cur.fetchall()
        cur.close()
    except Exception:
        return
    finally:
        conn.close()
    if not targets:
        return
    emoji = "✅" if "등록" in change_type else "❌"
    _send(targets,
          f"{emoji} {player_name} {change_type}",
          f"마이팀 {player_name}이(가) {change_type} 되었습니다.",
          {"player_id": str(player_id), "type": "roster_change"}, "roster_change", None)


# ── 페넌트레이스 알림 ─────────────────────────────────────────────────────────

def notify_gb_zero(team_id: int, team_name: str, first_team_name: str):
    """게임차 0 달성 - 동률 1위 팬에게"""
    targets = _get_team_fan_targets(team_id, 'notify_rank_change')
    opp = f" ({first_team_name}과 동률)" if first_team_name else ""
    _send(targets,
          f"🔥 {team_name} 게임차 0!",
          f"{team_name}이(가) 1위와 게임차 0입니다{opp}!",
          {"team_id": str(team_id), "type": "rank_change"}, "rank_change", None)


def notify_pennant_race(team_id: int, team_name: str, curr_gap: float, prev_gap: float):
    """1위 마이팀 + 2위 게임차 좁혀질 때 — notify_pennant_race ON 팬에게"""
    targets = _get_team_fan_targets(team_id, 'notify_pennant_race')
    _send(targets,
          f"⚠️ {team_name} 추격 받는 중!",
          f"2위와의 게임차가 {prev_gap:.1f} → {curr_gap:.1f}게임으로 좁혀졌습니다.",
          {"team_id": str(team_id), "type": "pennant_race"}, "pennant_race", None)


# ── 경기 결과 요약 ────────────────────────────────────────────────────────────

def notify_game_summary(game_id: int, home_team: str, away_team: str,
                        home_score: int, away_score: int,
                        home_team_id: int, away_team_id: int,
                        win_pitcher: str = '', win_ip: str = '', win_er: int = 0,
                        loss_pitcher: str = '',
                        hold_pitcher: str = '', save_pitcher: str = '',
                        mvp_name: str = '', mvp_hits: int = 0,
                        mvp_hr: int = 0, mvp_rbi: int = 0,
                        review_text: str = ''):
    """경기 종료 30분 후 결과 요약 — notify_game_end ON 유저에게.
    review_text(AI 한줄평) 있으면 본문으로 사용, 없으면 기존 라인 조립(하위호환)."""
    targets = _get_targets('notify_game_end', [home_team_id, away_team_id])
    if home_score > away_score:
        winner, loser, ws, ls = home_team, away_team, home_score, away_score
    else:
        winner, loser, ws, ls = away_team, home_team, away_score, home_score
    title = f"📋 {winner} {ws}:{ls} {loser} 경기결과"
    lines = []
    if win_pitcher:
        wp = f"승: {win_pitcher}"
        if win_ip:
            wp += f" ({win_ip}이닝 {win_er}자책)"
        lines.append(wp)
    lp_parts = []
    if loss_pitcher:
        lp_parts.append(f"패: {loss_pitcher}")
    if hold_pitcher:
        lp_parts.append(f"홀드: {hold_pitcher}")
    if save_pitcher:
        lp_parts.append(f"세이브: {save_pitcher}")
    if lp_parts:
        lines.append("  ".join(lp_parts))
    if mvp_name:
        mvp_stats = []
        if mvp_hits:
            mvp_stats.append(f"{mvp_hits}안타")
        if mvp_hr:
            mvp_stats.append(f"{mvp_hr}홈런")
        if mvp_rbi:
            mvp_stats.append(f"{mvp_rbi}타점")
        lines.append(f"⭐ {mvp_name} {' '.join(mvp_stats)}")
    body = review_text if review_text else "\n".join(lines)
    _send(targets, title, body,
          {"game_id": str(game_id), "type": "game_summary"}, "game_end", game_id)


# ── 승부예측 결과 (메가F) ─────────────────────────────────────────────────────

def notify_prediction_result(user_id: int, game_id: int, home_team: str,
                             away_team: str, outcome: str, points: int):
    """승부예측 정산 결과 — 예측한 본인에게. outcome ∈ win/lose/draw.
    dedup은 호출측(정산)에서 notification_log (game_id,'prediction_result',user_id)."""
    matchup = f"{home_team} vs {away_team}"
    if outcome == 'win':
        title, body = "🎯 예측 적중!", f"{matchup} — 적중! +{points}P"
    elif outcome == 'draw':
        title, body = "⚾ 무승부", f"{matchup} — 무승부 참여 +{points}P"
    else:
        title, body = "승부예측 결과", f"{matchup} — 아쉽게 빗나감 +{points}P"

    targets: list[tuple[int, str]] = []
    conn = get_connection()
    if conn:
        try:
            cur = conn.cursor()
            cur.execute("SELECT token FROM push_tokens WHERE user_id = %s", (user_id,))
            targets = [(user_id, r[0]) for r in cur.fetchall()]
            cur.close()
        except Exception as e:
            logger.error(f"[FCM] 예측결과 토큰조회 실패 uid={user_id}: {e}")
        finally:
            conn.close()

    data = {"game_id": str(game_id), "type": "prediction_result"}
    if targets:
        _send(targets, title, body, data, "prediction_result", game_id)
    else:
        # 푸시 토큰 없는 유저(웹 등)도 인앱 알림함엔 저장
        _save_notifications([user_id], title, body, "prediction_result", game_id)


# ── 결정적 순간 (승률 급변) ───────────────────────────────────────────────────

def notify_clutch_moment(game_id: int, home_team: str, away_team: str,
                         home_team_id: int, away_team_id: int,
                         situation: str, gainer: str,
                         prob_from: float, prob_to: float):
    """인게임 승률 ±20%p 급변 — notify_clutch ON 양팀 팬에게 (전용 토글 06-13).
    situation: '8회말 2사 1·3루' / gainer: 유리해진 팀명"""
    targets = _get_targets('notify_clutch', [home_team_id, away_team_id])
    title = f"🔥 결정적 순간! {home_team} vs {away_team}"
    body = (f"{situation} — {gainer} 승률 "
            f"{prob_from:.0f}%→{prob_to:.0f}%")
    _send(targets, title, body,
          {"game_id": str(game_id), "type": "clutch_moment"}, "clutch_moment", game_id)


# ── 아침 브리핑 ───────────────────────────────────────────────────────────────

def notify_daily_briefing(team_id: int, title: str, body: str):
    """아침 브리핑 (어제 마이팀 결과 + 오늘 경기) — notify_briefing ON 팬에게 팀별 1통 (전용 토글 06-13)"""
    targets = _get_targets('notify_briefing', [team_id])
    _send(targets, title, body,
          {"type": "daily_briefing"}, "daily_briefing", None)


# ── 즐겨찾기 선수 선발 출전 ────────────────────────────────────────────────────

def notify_fav_player_lineup(player_id: int, player_name: str, team_name: str,
                              game_id: int, opponent_team: str,
                              batting_order: int = 0, position: str = ''):
    """즐겨찾기 선수 선발 출전 알림 — notify_game_start ON 팬에게"""
    targets = _get_player_fan_targets(player_id, 'notify_fav_lineup')
    if not targets:
        return
    order_str = f"{batting_order}번" if batting_order else ''
    pos_str = position or ''
    detail = f"{order_str} {pos_str}".strip() if (order_str or pos_str) else ''
    body = (f"{team_name} vs {opponent_team} — {detail}"
            if detail else f"{team_name} vs {opponent_team}")
    _send(targets,
          f"⚾ {player_name} 오늘 선발 출전!",
          body,
          {"player_id": str(player_id), "game_id": str(game_id), "type": "player_lineup"},
          "game_start", game_id)


# ── 커뮤니티 알림 (user_settings 무관, 직접 수신) ────────────────────────────

def notify_new_comment(post_author_id: int, post_id: int,
                       post_title: str, commenter_nickname: str):
    targets = _get_user_targets(post_author_id)
    title_short = post_title[:25] + ('…' if len(post_title) > 25 else '')
    _send(targets,
          f"💬 {commenter_nickname}님이 댓글을 달았습니다",
          f"'{title_short}' — 댓글을 확인해보세요",
          {"post_id": str(post_id), "type": "new_comment"}, "new_comment", None)


# ── 즐겨찾기 선수 홈런 ──────────────────────────────────────────────────────────

def notify_fav_hr(player_id: int, player_name: str, team_name: str, game_id: int,
                  hr_type: str = ''):
    """즐겨찾기 선수 홈런 — notify_fav_hr ON 팬에게"""
    targets = _get_player_fan_targets(player_id, 'notify_fav_hr')
    if not targets:
        return
    hr_str = f" ({hr_type})" if hr_type else ""
    _send(targets,
          f"💣 {player_name} 홈런!{hr_str}",
          f"{team_name} {player_name} 홈런{hr_str}! 담장을 넘었습니다.",
          {"game_id": str(game_id), "player_id": str(player_id), "type": "fav_hr"},
          "fav_hr", game_id)


# ── 끝내기 승리 알림 ──────────────────────────────────────────────────────────

def notify_walkoff(game_id: int, home_team: str, away_team: str,
                   home_score: int, away_score: int,
                   home_team_id: int, away_team_id: int):
    """끝내기 승리 — notify_walkoff ON 유저에게"""
    targets = _get_targets('notify_walkoff', [home_team_id, away_team_id])
    _send(targets,
          f"🎉 끝내기! {home_team} 승리!",
          f"{home_team} {home_score}:{away_score} {away_team} — 극적인 끝내기 승리!",
          {"game_id": str(game_id), "type": "walkoff"}, "walkoff", game_id)


# ── 선발투수 발표 / 투수 교체 알림 ───────────────────────────────────────────

def notify_starter_announced(game_id: int, home_team: str, away_team: str,
                             home_team_id: int, away_team_id: int,
                             home_starter: str = '', away_starter: str = ''):
    """라인업 발표 시 선발투수 알림 — notify_game_start ON 유저에게"""
    targets = _get_targets('notify_game_start', [home_team_id, away_team_id])
    title = f"📋 선발투수 발표 — {home_team} vs {away_team}"
    parts = []
    if home_starter:
        parts.append(f"홈 {home_team}: {home_starter}")
    if away_starter:
        parts.append(f"원정 {away_team}: {away_starter}")
    body = "\n".join(parts) if parts else f"{home_team} vs {away_team}"
    _send(targets, title, body,
          {"game_id": str(game_id), "type": "starter_announced"}, "game_start", game_id)


def notify_pitcher_change(game_id: int, home_team: str, away_team: str,
                          new_pitcher: str, team_name: str, prev_pitcher: str = '',
                          home_team_id: int = 0, away_team_id: int = 0):
    """투수 교체 알림 — notify_starter_ko(재사용) ON 유저에게"""
    targets = _get_targets('notify_starter_ko', [home_team_id, away_team_id])
    title = f"🔄 [{team_name}] 투수 교체"
    body = f"{prev_pitcher} → {new_pitcher}" if prev_pitcher else f"신규 등판: {new_pitcher}"
    body += f"\n{home_team} vs {away_team}"
    _send(targets, title, body,
          {"game_id": str(game_id), "type": "pitcher_change"}, "game_start", game_id)


# ── 대기록 알림 ───────────────────────────────────────────────────────────────

_MILESTONE_LABELS: dict[str, tuple] = {
    # (emoji, 카테고리, 단위)  →  "{emoji} {이름} {월}카테고리 {값}단위!"
    # 월간
    'monthly_hits':  ('🔥', '월간', '안타'),
    'monthly_hr':    ('💣', '월간', '홈런'),
    'monthly_rbi':   ('🏆', '월간', '타점'),
    'monthly_sb':    ('💨', '월간', '도루'),
    'monthly_so':    ('🔥', '월간', '탈삼진'),
    # 시즌
    'season_hr':     ('💣', '시즌', '홈런'),
    'season_rbi':    ('🏆', '시즌', '타점'),
    'season_hits':   ('🔥', '시즌', '안타'),
    'season_sb':     ('💨', '시즌', '도루'),
    'season_bb':     ('👁️', '시즌', '볼넷'),
    'season_runs':   ('🏃', '시즌', '득점'),
    'season_wins':   ('🏆', '시즌', '승리'),
    'season_so':     ('🔥', '시즌', '탈삼진'),
    'season_saves':  ('💾', '시즌', '세이브'),
    'season_holds':  ('✋', '시즌', '홀드'),
    # 단일경기
    'game_hits':       ('💥', '단일경기', '안타'),
    'game_hr':         ('💣', '단일경기', '홈런'),
    'game_rbi':        ('🏆', '단일경기', '타점'),
    'game_sb':         ('💨', '단일경기', '도루'),
    'game_so':         ('🔥', '단일경기', '탈삼진'),
    'game_cg':         ('🎯', '완봉', ''),
    'game_shutout':    ('🔒', '완봉승', ''),
    'game_no_hitter':  ('🚫', '노히터', ''),
    'game_qs':         ('✅', 'QS 달성', ''),
    # 연속 안타
    'hitting_streak':  ('🔥', '연속 경기 안타', '경기'),
    # 통산
    'career_hits':   ('✨', '통산', '안타'),
    'career_hr':     ('💣', '통산', '홈런'),
    'career_rbi':    ('🏆', '통산', '타점'),
    'career_sb':     ('💨', '통산', '도루'),
    'career_bb':     ('👁️', '통산', '볼넷'),
    'career_wins':   ('🏆', '통산', '승리'),
    'career_so':     ('🔥', '통산', '탈삼진'),
    'career_saves':  ('💾', '통산', '세이브'),
    'career_holds':  ('✋', '통산', '홀드'),
    'career_tb':     ('✨', '통산', '루타'),
    # 확장(07-02)
    'walkoff_hr':        ('🎉', '끝내기 홈런', ''),
    'walkoff_hit':       ('🎉', '끝내기 안타', ''),
    'game_cycle':        ('🌈', '사이클링 히트', ''),
    'game_multi_hr':     ('💣', '한 경기', '홈런'),
    'season_hr_vs_all':  ('🎯', '전 구단 상대 홈런', ''),
    'season_20_20':      ('⚡', '20-20 클럽', ''),
    'season_30_30':      ('⚡', '30-30 클럽', ''),
    'season_40_40':      ('🔥', '40-40 클럽', ''),
    # 개인 월간 최다 경신
    'personal_monthly_hits': ('📈', '개인 최다', '안타'),
    'personal_monthly_hr':   ('📈', '개인 최다', '홈런'),
    'personal_monthly_rbi':  ('📈', '개인 최다', '타점'),
    'personal_monthly_sb':   ('📈', '개인 최다', '도루'),
    'personal_monthly_so':   ('📈', '개인 최다', '탈삼진'),
    # 최연소 (extra_label에 나이 포함)
    'young_season_hr':    ('🌟', '시즌', '홈런'),
    'young_season_rbi':   ('🌟', '시즌', '타점'),
    'young_season_hits':  ('🌟', '시즌', '안타'),
    'young_season_wins':  ('🌟', '시즌', '승리'),
    'young_season_so':    ('🌟', '시즌', '탈삼진'),
    'young_season_saves': ('🌟', '시즌', '세이브'),
    'young_career_hr':    ('🌟', '통산', '홈런'),
    'young_career_hits':  ('🌟', '통산', '안타'),
}


def notify_milestone(player_id: int, player_name: str, team_name: str,
                     milestone_type: str, milestone_value: int,
                     season: int, month: int, game_id: int | None = None,
                     extra_label: str = '', team_id: int = 0):
    """대기록 달성 알림.
    - 통산(career_*): 즐겨찾기 선수 팬 + 즐겨찾기 팀 팬
    - 시즌/월간/단일경기/연속안타/연소(young)/개인최다(personal_*): 즐겨찾기 팀 팬 (선수팬 X)
    """
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO player_milestone_alerts (player_id, milestone_type, milestone_value, season, month)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT DO NOTHING
            RETURNING id
        """, (player_id, milestone_type, milestone_value, season, month))
        if cur.fetchone() is None:
            cur.close()
            conn.commit()
            conn.close()
            return
        conn.commit()
        cur.close()
    except Exception as e:
        logger.error(f"[FCM] 마일스톤 저장 실패: {e}")
        return
    finally:
        conn.close()

    # team_id 자동 조회 (호출 측 전달 안 한 경우)
    if not team_id:
        try:
            _c = get_connection()
            if _c:
                _cur = _c.cursor()
                _cur.execute("SELECT team_id FROM players WHERE id=%s", (player_id,))
                _row = _cur.fetchone()
                team_id = _row[0] if _row and _row[0] else 0
                _cur.close(); _c.close()
        except Exception:
            pass

    # 분류: 통산은 통산 토글(선수팬+팀팬), 나머지는 팀 마일스톤 토글(팀팬만)
    _CAREER_LIKE = {'walkoff_hr', 'walkoff_hit', 'season_hr_vs_all'}
    is_career = (milestone_type.startswith('career_')
                 or milestone_type.startswith('young_career_')
                 or milestone_type in _CAREER_LIKE)
    targets = []
    if is_career:
        targets.extend(_get_player_fan_targets(player_id, 'notify_milestone'))
        if team_id:
            targets.extend(_get_team_fan_targets(team_id, 'notify_milestone'))
    else:
        if team_id:
            targets = _get_team_fan_targets(team_id, 'notify_team_milestone')
    # 중복 제거 (user_id 기준)
    seen_uids = set()
    unique_targets = []
    for uid, tok in targets:
        if uid not in seen_uids:
            seen_uids.add(uid)
            unique_targets.append((uid, tok))
    if not unique_targets:
        return

    emoji, cat, unit = _MILESTONE_LABELS.get(milestone_type, ('⭐', milestone_type, ''))
    month_str = f"{month}월 " if month > 0 and 'monthly' in milestone_type else ''
    extra_str = f" ({extra_label})" if extra_label else ''

    from api.milestone_detect import format_milestone_title
    title = format_milestone_title(emoji, player_name, month_str, cat, milestone_value, unit, extra_str)
    body = f"{team_name} {player_name} {month_str}{cat} {milestone_value}{unit} 달성!{extra_str}"

    _send(unique_targets, title, body,
          {"player_id": str(player_id), "type": "milestone",
           **({"game_id": str(game_id)} if game_id else {})},
          "score_change", game_id)


# ── 신규 선수 알림 함수들 (Phase 1-3) ─────────────────────────────────────────

def notify_hitting_streak(player_id: int, player_name: str, team_name: str,
                          streak: int, game_id: int | None = None):
    """연속 안타 기록 (8경기 이상) — 즐겨찾기 선수 팬에게."""
    if streak < 8:
        return
    targets = _get_player_fan_targets(player_id, 'notify_player_news')
    if not targets:
        return
    _send(targets,
          f"🔥 {player_name} {streak}경기 연속 안타!",
          f"{team_name} {player_name} 선수가 {streak}경기 연속 안타 기록을 이어갑니다!",
          {"player_id": str(player_id), "type": "hitting_streak"},
          "score_change", game_id)


def notify_daily_player_summary(player_id: int, player_name: str, team_name: str,
                                 player_type: str, stats: dict, game_date):
    """매일 자정 즐겨찾기 선수 활약 요약. stats: {hits, at_bats, rbi, hr, ip, er, so, ...}"""
    targets = _get_player_fan_targets(player_id, 'notify_player_daily')
    if not targets:
        return
    parts = []
    if player_type == '타자':
        ab = stats.get('at_bats', 0) or 0
        h = stats.get('hits', 0) or 0
        hr = stats.get('home_runs', 0) or 0
        rbi = stats.get('rbi', 0) or 0
        bb = stats.get('walks', 0) or 0
        sb = stats.get('sb', 0) or 0
        if ab == 0 and bb == 0:
            return  # 출전 안 함
        parts.append(f"{h}안타")
        if hr > 0: parts.append(f"{hr}홈런")
        if rbi > 0: parts.append(f"{rbi}타점")
        if sb > 0: parts.append(f"{sb}도루")
        if bb > 0: parts.append(f"{bb}볼넷")
    else:
        ip = stats.get('ip', 0) or 0
        er = stats.get('er', 0) or 0
        so = stats.get('so', 0) or 0
        result = stats.get('result', '') or ''
        if ip == 0:
            return
        if result:
            parts.append(result)
        parts.append(f"{ip}이닝")
        parts.append(f"{er}자책")
        if so > 0: parts.append(f"{so}K")
    body = ' · '.join(parts) if parts else '경기 출전'
    _send(targets,
          f"⭐ 오늘의 {player_name}",
          f"{team_name} {player_name} — {body}",
          {"player_id": str(player_id), "type": "daily_player_summary"},
          "score_change", None)


def notify_player_transaction(player_id: int, player_name: str,
                              transaction_type: str, detail: str = ''):
    """트레이드/방출/은퇴/FA — 즐겨찾기 선수 팬에게.
    transaction_type: 'trade' / 'release' / 'retire' / 'fa_signed' / 'fa_filed'."""
    targets = _get_player_fan_targets(player_id, 'notify_player_news')
    if not targets:
        return
    emoji_map = {
        'trade': '🔄', 'release': '👋', 'retire': '🎬',
        'fa_signed': '✍️', 'fa_filed': '📝',
    }
    label_map = {
        'trade': '트레이드', 'release': '방출', 'retire': '은퇴',
        'fa_signed': 'FA 계약', 'fa_filed': 'FA 선언',
    }
    emoji = emoji_map.get(transaction_type, '📰')
    label = label_map.get(transaction_type, transaction_type)
    _send(targets,
          f"{emoji} {player_name} {label}",
          f"{player_name} 선수 {label}{f' — {detail}' if detail else ''}",
          {"player_id": str(player_id), "type": f"transaction_{transaction_type}"},
          "score_change", None)


def notify_injury_list(player_id: int, player_name: str, team_name: str,
                       action: str, reason: str = ''):
    """부상자 명단 등재/복귀 — 즐겨찾기 선수 팬에게.
    action: 'listed' / 'returned'"""
    targets = _get_player_fan_targets(player_id, 'notify_player_news')
    if not targets:
        return
    if action == 'listed':
        emoji = '🤕'
        title = f"{emoji} {player_name} 부상자 명단 등재"
        body = f"{team_name} {player_name} 부상자 명단 등재{f' — {reason}' if reason else ''}"
    else:
        emoji = '💪'
        title = f"{emoji} {player_name} 부상자 명단 복귀"
        body = f"{team_name} {player_name} 부상자 명단 복귀!"
    _send(targets, title, body,
          {"player_id": str(player_id), "type": f"injury_{action}"},
          "score_change", None)


def notify_award(player_id: int, player_name: str, team_name: str,
                 award_type: str, season: int, position: str = ''):
    """시상 (MVP/신인왕/GG) — 즐겨찾기 선수 팬에게.
    award_type: 'mvp' / 'rookie' / 'gg' / 'pitcher_gg' / 'goldenglove'"""
    targets = _get_player_fan_targets(player_id, 'notify_player_news')
    if not targets:
        return
    emoji_map = {'mvp': '👑', 'rookie': '🌟', 'gg': '🏆', 'goldenglove': '🏆'}
    label_map = {'mvp': f'{season}시즌 MVP', 'rookie': f'{season}시즌 신인왕',
                 'gg': f'{season}시즌 골든글러브{f" ({position})" if position else ""}',
                 'goldenglove': f'{season}시즌 골든글러브{f" ({position})" if position else ""}'}
    emoji = emoji_map.get(award_type, '🏅')
    label = label_map.get(award_type, award_type)
    _send(targets,
          f"{emoji} {player_name} {label}!",
          f"{team_name} {player_name} 선수 {label} 수상!",
          {"player_id": str(player_id), "type": f"award_{award_type}"},
          "score_change", None)


def notify_allstar(player_id: int, player_name: str, team_name: str,
                   season: int, league: str = '', vote_rank: int = 0):
    """올스타 선발 — 즐겨찾기 선수 팬에게.
    league: 'dream' / 'nanum'"""
    targets = _get_player_fan_targets(player_id, 'notify_player_news')
    if not targets:
        return
    league_str = f"({'드림' if league == 'dream' else '나눔'} 올스타) " if league else ""
    rank_str = f" · 팬투표 {vote_rank}위" if vote_rank > 0 else ""
    _send(targets,
          f"⭐ {player_name} {season} 올스타 선발!",
          f"{team_name} {player_name} 선수가 {season} 올스타전에 선발되었습니다 {league_str}{rank_str}",
          {"player_id": str(player_id), "type": "allstar"},
          "score_change", None)


def notify_allstar_vote_period(stage: str, season: int, deadline: str = '',
                                 vote_url: str = ''):
    """올스타 팬투표 기간 알림 — 모든 사용자에게 (notify_allstar_vote 토글).
    stage: 'opened' (시작) / 'closing_d3' (D-3) / 'closing_d1' (D-1).
    deadline: 'MM월 DD일' 형식."""
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT pt.user_id, pt.token
            FROM push_tokens pt
            JOIN user_settings us ON us.user_id = pt.user_id
            WHERE COALESCE(us.notify_allstar_vote, TRUE) = TRUE
              AND pt.token IS NOT NULL
        """)
        targets = [(r[0], r[1]) for r in cur.fetchall()]
        cur.close()
    finally:
        conn.close()
    if not targets:
        return
    if stage == 'opened':
        title = f"🗳️ {season} 올스타 팬투표 시작!"
        body = f"마이팀 선수를 응원해 주세요{f' · 마감 {deadline}' if deadline else ''}"
    elif stage == 'closing_d3':
        title = f"⏰ {season} 올스타 팬투표 마감 D-3"
        body = f"{deadline} 마감 · 아직 투표 안 하셨다면 서둘러주세요!"
    elif stage == 'closing_d1':
        title = f"🚨 {season} 올스타 팬투표 마감 D-1"
        body = f"내일 {deadline} 마감 · 마지막 기회입니다!"
    else:
        title = f"🗳️ {season} 올스타 팬투표"
        body = deadline or "진행 중"
    _send(targets, title, body,
          {"type": "allstar_vote", "stage": stage,
           **({"vote_url": vote_url} if vote_url else {})},
          "score_change", None)


