"""FCM 트레이 collapse_key 분리 순수 테스트 (네트워크/firebase 불요).

회귀 방어: 같은 날 여러 선수 등록말소가 한 트레이 슬롯으로 합쳐져 마지막 1건만
남던 버그(06-30 오재원/정민규 — 정민규만 수신). game_id 없는 같은-타입 다수
이벤트는 player_id/team_id로 분리돼야 한다."""
import api.fcm_service as fcm
from api.fcm_service import _collapse_key, _failure_reason_counts


def test_roster_two_players_distinct_keys():
    # 같은 날 같은 change_type 두 선수 → 트레이 키 달라야 둘 다 남음
    a = _collapse_key('roster_change', None, {'player_id': '17', 'type': 'roster_change'})
    b = _collapse_key('roster_change', None, {'player_id': '8291', 'type': 'roster_change'})
    assert a != b
    assert a == 'roster_change_17'
    assert b == 'roster_change_8291'


def test_game_id_keys_per_game():
    # 고빈도 score_change는 경기당 1슬롯 (Android 50캡 방지) — 기존 동작 보존
    assert _collapse_key('score_change', 494, {'game_id': '494'}) == 'score_change_494'
    assert _collapse_key('score_change', 495, {'game_id': '495'}) == 'score_change_495'


def test_team_entity_distinct_keys():
    # rank_change/streak 등 game_id 없는 팀 알림도 team_id로 분리
    a = _collapse_key('rank_change', None, {'team_id': '5', 'type': 'rank_change'})
    b = _collapse_key('rank_change', None, {'team_id': '9', 'type': 'rank_change'})
    assert a != b


def test_bare_ntype_fallback():
    # 분별자 없으면 bare ntype (하위호환)
    assert _collapse_key('daily_briefing', None, {'type': 'daily_briefing'}) == 'daily_briefing'


def test_game_id_precedence_over_entity():
    # game_id 있으면 player_id보다 우선 (마일스톤 단일경기 등)
    assert _collapse_key('milestone', 494, {'player_id': '17', 'game_id': '494'}) == 'milestone_494'


def test_failure_reasons_are_aggregated_without_tokens():
    class Result:
        def __init__(self, success, exception=None):
            self.success = success
            self.exception = exception

    reasons = _failure_reason_counts([
        Result(False, ValueError('expired token')),
        Result(False, ValueError('expired token')),
        Result(False, RuntimeError('sender mismatch')),
        Result(True),
    ])

    assert reasons == {
        'ValueError: no-code': 2,
        'RuntimeError: no-code': 1,
    }


def test_send_splits_multicast_into_500_token_batches(monkeypatch):
    from firebase_admin import messaging

    sizes = []

    class Result:
        success = True
        exception = None

    class Response:
        def __init__(self, count):
            self.success_count = count
            self.failure_count = 0
            self.responses = [Result() for _ in range(count)]

    def send(message):
        sizes.append(len(message.tokens))
        return Response(len(message.tokens))

    monkeypatch.setattr(fcm, '_get_app', lambda: object())
    monkeypatch.setattr(fcm, '_save_notifications', lambda *args: None)
    monkeypatch.setattr(fcm, '_is_quiet_now', lambda: False)
    monkeypatch.setattr(messaging, 'send_each_for_multicast', send)

    targets = [(index, f'token-{index}') for index in range(1001)]
    assert fcm._send(targets, 'title', 'body', {}, 'test', None) is True
    assert sizes == [500, 500, 1]
