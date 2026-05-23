"""
FCM 푸시 알림 서비스
Firebase Admin SDK 사용.
서비스 계정 키: ~/playball/backend/firebase-service-account.json
"""
import os
from database.connection import get_connection

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
        print(f"[FCM] Firebase 초기화 실패: {e}")
        return None


def _get_targets(notify_type: str, team_ids: list[int]) -> list[tuple[int, str]]:
    """
    알림 수신 대상 (user_id, token) 목록 반환.

    user_settings 반영:
    - notify_{type} = FALSE → 제외
    - notify_my_team_only = TRUE → team_ids 중 마이팀 포함 유저만
    - notify_my_team_only = FALSE (기본) → 모든 경기 알림
    - user_settings 미설정 → 기본값(전부 ON, my_team_only=OFF)
    """
    allowed = ('notify_game_start', 'notify_score_change', 'notify_game_end')
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
        print(f"[FCM] 토큰 조회 실패: {e}")
        return []
    finally:
        conn.close()


def _save_notifications(user_ids: list[int], title: str, body: str,
                        ntype: str, game_id: int | None):
    """알림 이력 DB 저장"""
    if not user_ids:
        return
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        cur.executemany(
            "INSERT INTO user_notifications (user_id, title, body, type, game_id) VALUES (%s, %s, %s, %s, %s)",
            [(uid, title, body, ntype, game_id) for uid in user_ids],
        )
        conn.commit()
        cur.close()
    except Exception as e:
        print(f"[FCM] 알림 저장 실패: {e}")
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


def _send(targets: list[tuple[int, str]], title: str, body: str,
          data: dict, ntype: str, game_id: int | None):
    if not targets:
        return

    user_ids = [t[0] for t in targets]
    tokens   = [t[1] for t in targets]

    # 알림 이력 저장 (FCM 성공 여부 무관하게 저장)
    _save_notifications(user_ids, title, body, ntype, game_id)

    if _get_app() is None:
        return
    try:
        from firebase_admin import messaging
        msg = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in data.items()},
            tokens=tokens,
        )
        resp = messaging.send_each_for_multicast(msg)
        print(f"[FCM] {title}: {resp.success_count}성공 / {resp.failure_count}실패")

        failed_tokens = [
            tokens[i] for i, r in enumerate(resp.responses)
            if not r.success and r.exception and
            'registration-token-not-registered' in str(r.exception)
        ]
        _remove_invalid_tokens(failed_tokens)
    except Exception as e:
        print(f"[FCM] 발송 실패: {e}")


def notify_game_start(game_id: int, home_team: str, away_team: str,
                      home_team_id: int, away_team_id: int):
    targets = _get_targets('notify_game_start', [home_team_id, away_team_id])
    title = f"⚾ {home_team} vs {away_team} 시작!"
    body  = "경기가 시작되었습니다."
    _send(targets, title, body,
          {"game_id": str(game_id), "type": "game_start"}, "game_start", game_id)


def notify_score_change(game_id: int, home_team: str, away_team: str,
                        home_score: int, away_score: int,
                        home_team_id: int, away_team_id: int):
    targets = _get_targets('notify_score_change', [home_team_id, away_team_id])
    title = "⚾ 득점!"
    body  = f"{home_team} {home_score} : {away_score} {away_team}"
    _send(targets, title, body,
          {"game_id": str(game_id), "type": "score_change"}, "score_change", game_id)


def notify_game_end(game_id: int, home_team: str, away_team: str,
                    home_score: int, away_score: int,
                    home_team_id: int, away_team_id: int):
    targets = _get_targets('notify_game_end', [home_team_id, away_team_id])
    if home_score > away_score:
        result = f"{home_team} 승리!"
    elif away_score > home_score:
        result = f"{away_team} 승리!"
    else:
        result = "무승부"
    title = "⚾ 경기 종료"
    body  = f"{home_team} {home_score} : {away_score} {away_team} — {result}"
    _send(targets, title, body,
          {"game_id": str(game_id), "type": "game_end"}, "game_end", game_id)
