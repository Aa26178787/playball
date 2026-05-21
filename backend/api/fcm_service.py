"""
FCM 푸시 알림 서비스
Firebase Admin SDK 사용.
서버에 firebase-admin 설치 필요: pip install firebase-admin
서비스 계정 키: ~/playball/backend/firebase-service-account.json
"""
import os
import json
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


def _get_tokens(user_ids: list[int] | None = None, team_id: int | None = None) -> list[str]:
    """알림 대상 FCM 토큰 목록 조회"""
    conn = get_connection()
    if not conn:
        return []
    try:
        cur = conn.cursor()
        if team_id is not None:
            # 해당 팀을 마이팀으로 등록한 유저의 토큰
            cur.execute("""
                SELECT DISTINCT pt.token
                FROM push_tokens pt
                JOIN user_favorite_teams uft ON uft.user_id = pt.user_id
                WHERE uft.team_id = %s
            """, (team_id,))
        elif user_ids:
            cur.execute(
                "SELECT token FROM push_tokens WHERE user_id = ANY(%s)",
                (user_ids,),
            )
        else:
            cur.execute("SELECT token FROM push_tokens")
        rows = cur.fetchall()
        cur.close()
        return [r[0] for r in rows]
    except Exception as e:
        print(f"[FCM] 토큰 조회 실패: {e}")
        return []
    finally:
        conn.close()


def send_notification(title: str, body: str, data: dict | None = None,
                      team_id: int | None = None, user_ids: list[int] | None = None):
    """FCM 멀티캐스트 알림 발송"""
    if _get_app() is None:
        return
    tokens = _get_tokens(user_ids=user_ids, team_id=team_id)
    if not tokens:
        return
    try:
        from firebase_admin import messaging
        msg = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            tokens=tokens,
        )
        resp = messaging.send_each_for_multicast(msg)
        print(f"[FCM] 알림 발송: {resp.success_count}성공 / {resp.failure_count}실패")
    except Exception as e:
        print(f"[FCM] 알림 발송 실패: {e}")


def notify_game_start(game_id: int, home_team: str, away_team: str,
                      home_team_id: int, away_team_id: int):
    """경기 시작 알림 (마이팀 포함 유저에게)"""
    for team_id, team_name in [(home_team_id, home_team), (away_team_id, away_team)]:
        send_notification(
            title=f"⚾ {home_team} vs {away_team} 시작!",
            body=f"{team_name} 경기가 시작되었습니다.",
            data={"game_id": str(game_id), "type": "game_start"},
            team_id=team_id,
        )


def notify_score_change(game_id: int, home_team: str, away_team: str,
                        home_score: int, away_score: int,
                        home_team_id: int, away_team_id: int):
    """득점 알림"""
    body = f"{home_team} {home_score} : {away_score} {away_team}"
    for team_id in [home_team_id, away_team_id]:
        send_notification(
            title="⚾ 득점!",
            body=body,
            data={"game_id": str(game_id), "type": "score_change"},
            team_id=team_id,
        )


def notify_game_end(game_id: int, home_team: str, away_team: str,
                    home_score: int, away_score: int,
                    home_team_id: int, away_team_id: int):
    """경기 종료 알림"""
    if home_score > away_score:
        result = f"{home_team} 승리!"
    elif away_score > home_score:
        result = f"{away_team} 승리!"
    else:
        result = "무승부"
    body = f"{home_team} {home_score} : {away_score} {away_team} — {result}"
    for team_id in [home_team_id, away_team_id]:
        send_notification(
            title="⚾ 경기 종료",
            body=body,
            data={"game_id": str(game_id), "type": "game_end"},
            team_id=team_id,
        )
