content = open('/home/ubuntu/playball/backend/crawler/scheduler.py').read()

insert_after = """                if cs == '진행' and curr_inn >= 10 and prev_inn < 10:
                    notify_extra_innings(gid, curr['home_team'], curr['away_team'],
                                         curr_inn,
                                         curr['home_team_id'], curr['away_team_id'])"""

new_block = """

                # 선발 조기강판 실시간 감지
                if cs == '진행' and gid not in _ko_notified_games:
                    try:
                        def _pip(iv):
                            try:
                                p = str(iv).strip().split('.')
                                return int(p[0] or 0) + (int(p[1]) if len(p) > 1 and p[1] else 0) / 3
                            except Exception:
                                return 0.0
                        _ck = get_connection()
                        if _ck:
                            _cr = _ck.cursor()
                            _cr.execute(
                                "SELECT p.name, gp.innings_pitched, gp.team_side "
                                "FROM game_pitchers gp JOIN players p ON p.id=gp.player_id "
                                "WHERE gp.game_id=%s AND gp.pitching_order=1 AND gp.innings_pitched>0",
                                (gid,))
                            _sts = _cr.fetchall()
                            _cr.execute(
                                "SELECT DISTINCT team_side FROM game_pitchers "
                                "WHERE game_id=%s AND pitching_order>=2 AND innings_pitched>0",
                                (gid,))
                            _rep = {r[0] for r in _cr.fetchall()}
                            _cr.close()
                            _ck.close()
                            if _rep:
                                from api.fcm_service import notify_starter_ko
                                _ok = False
                                for _nm, _ip, _sd in _sts:
                                    if _sd in _rep and 0 < _pip(_ip) < 5.0:
                                        _tm = curr.get('home_team') if _sd == 'home' else curr.get('away_team')
                                        notify_starter_ko(gid, _nm, _tm or '', str(_ip) if _ip else '0',
                                                          curr.get('home_team_id', 0),
                                                          curr.get('away_team_id', 0))
                                        _ok = True
                                if _ok:
                                    _ko_notified_games.add(gid)
                    except Exception as _ko_e:
                        print(f'[FCM] 조기강판 실시간 오류: {_ko_e}')"""

if insert_after in content:
    content = content.replace(insert_after, insert_after + new_block, 1)
    open('/home/ubuntu/playball/backend/crawler/scheduler.py', 'w').write(content)
    print('OK')
else:
    print('NOT FOUND')
    idx = content.find('notify_extra_innings')
    if idx >= 0:
        print(repr(content[idx-20:idx+120]))
