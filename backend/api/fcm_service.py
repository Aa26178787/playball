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


# ── 토큰 조회 헬퍼 ────────────────────────────────────────────────────────────

def _get_targets(notify_type: str, team_ids: list[int]) -> list[tuple[int, str]]:
    """
    경기 알림용. user_settings(notify_{type}, notify_my_team_only) 반영.
    user_settings 미설정 → 기본값(전부 ON, my_team_only=OFF).
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
        print(f"[FCM] 팬 토큰 조회 실패: {e}")
        return []
    finally:
        conn.close()


def _get_player_fan_targets(player_id: int) -> list[tuple[int, str]]:
    """즐겨찾기 선수 팬의 (user_id, token). notify_roster ON인 유저만."""
    conn = get_connection()
    if not conn:
        return []
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT DISTINCT pt.user_id, pt.token
            FROM push_tokens pt
            JOIN user_favorite_players ufp ON ufp.user_id = pt.user_id
            LEFT JOIN user_settings us ON us.user_id = pt.user_id
            WHERE ufp.player_id = %s
              AND COALESCE(us.notify_roster, TRUE) = TRUE
        """, (player_id,))
        return cur.fetchall()
    except Exception as e:
        print(f"[FCM] 선수 팬 토큰 조회 실패: {e}")
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


# ── 공통 발송 ─────────────────────────────────────────────────────────────────

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
        print(f"[FCM] {title}: {resp.success_count}성공/{resp.failure_count}실패")
        failed = [
            tokens[i] for i, r in enumerate(resp.responses)
            if not r.success and r.exception and
            'registration-token-not-registered' in str(r.exception)
        ]
        _remove_invalid_tokens(failed)
    except Exception as e:
        print(f"[FCM] 발송 실패: {e}")


# ── 경기 알림 (user_settings 반영) ───────────────────────────────────────────

def notify_game_start(game_id: int, home_team: str, away_team: str,
                      home_team_id: int, away_team_id: int):
    targets = _get_targets('notify_game_start', [home_team_id, away_team_id])
    _send(targets,
          f"⚾ {home_team} vs {away_team} 시작!",
          "경기가 시작되었습니다.",
          {"game_id": str(game_id), "type": "game_start"}, "game_start", game_id)


def notify_score_change(game_id: int, home_team: str, away_team: str,
                        home_score: int, away_score: int,
                        home_team_id: int, away_team_id: int,
                        is_comeback: bool = False):
    targets = _get_targets('notify_score_change', [home_team_id, away_team_id])
    title = "⚡ 역전!" if is_comeback else "⚾ 득점!"
    body  = f"{home_team} {home_score} : {away_score} {away_team}"
    ntype = "comeback" if is_comeback else "score_change"
    _send(targets, title, body,
          {"game_id": str(game_id), "type": ntype}, ntype, game_id)


def notify_game_end(game_id: int, home_team: str, away_team: str,
                    home_score: int, away_score: int,
                    home_team_id: int, away_team_id: int):
    targets = _get_targets('notify_game_end', [home_team_id, away_team_id])
    result = (f"{home_team} 승리!" if home_score > away_score
              else f"{away_team} 승리!" if away_score > home_score else "무승부")
    _send(targets,
          "⚾ 경기 종료",
          f"{home_team} {home_score} : {away_score} {away_team} — {result}",
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


# ── 순위 알림 ─────────────────────────────────────────────────────────────────

def notify_rank_change(team_id: int, team_name: str,
                       old_rank: int, new_rank: int, games_behind: float):
    """순위 변동 — 해당 팀 마이팀 팬에게 (notify_rank_change ON)"""
    targets = _get_team_fan_targets(team_id, 'notify_rank_change')
    direction = "▲" if new_rank < old_rank else "▼"
    gb_str = f" (1위와 {games_behind}게임차)" if new_rank > 1 and games_behind is not None else " (1위!)" if new_rank == 1 else ""
    _send(targets,
          f"📊 {team_name} {direction}{abs(old_rank - new_rank)}위 {new_rank}위",
          f"{old_rank}위에서 {new_rank}위로 변동{gb_str}",
          {"team_id": str(team_id), "type": "rank_change"}, "rank_change", None)


# ── 연승/연패 알림 ────────────────────────────────────────────────────────────

def notify_streak(team_id: int, team_name: str, count: int, is_winning: bool):
    targets = _get_team_fan_targets(team_id, 'notify_streak')
    if is_winning:
        _send(targets,
              f"🔥 {team_name} {count}연승!",
              f"{team_name}가 {count}연승을 달리고 있습니다!",
              {"team_id": str(team_id), "type": "winning_streak"}, "winning_streak", None)
    else:
        _send(targets,
              f"😰 {team_name} {count}연패",
              f"{team_name}가 {count}연패 중입니다.",
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
          f"즐겨찾기 선수 {player_name}의 로스터가 변경되었습니다.",
          {"player_id": str(player_id), "type": "roster_change"}, "roster_change", None)


# ── 커뮤니티 알림 (user_settings 무관, 직접 수신) ────────────────────────────

def notify_new_comment(post_author_id: int, post_id: int,
                       post_title: str, commenter_nickname: str):
    targets = _get_user_targets(post_author_id)
    _send(targets,
          f"💬 새 댓글",
          f"{commenter_nickname}님이 '{post_title[:20]}...' 에 댓글을 달았습니다",
          {"post_id": str(post_id), "type": "new_comment"}, "new_comment", None)
