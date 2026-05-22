from fastapi import APIRouter
from database.connection import get_connection

router = APIRouter()

@router.get('')
def search(q: str = ''):
    if not q or len(q.strip()) < 1:
        return {'players': [], 'teams': []}
    conn = get_connection()
    if not conn:
        return {'players': [], 'teams': []}
    cur = conn.cursor()
    like = f'%{q.strip()}%'
    cur.execute("""
        SELECT p.id, p.name, p.player_type, p.position, p.profile_image, t.name AS team_name, t.short_name
        FROM players p
        LEFT JOIN teams t ON p.team_id = t.id
        WHERE p.name ILIKE %s
        LIMIT 15
    """, (like,))
    players = [{'id': r[0], 'name': r[1], 'player_type': r[2], 'position': r[3],
                'profile_image': r[4], 'team': r[5], 'team_code': r[6]} for r in cur.fetchall()]
    cur.execute("""
        SELECT id, name, short_name FROM teams WHERE name ILIKE %s OR short_name ILIKE %s LIMIT 5
    """, (like, like))
    teams = [{'id': r[0], 'name': r[1], 'short_name': r[2]} for r in cur.fetchall()]
    cur.close()
    conn.close()
    return {'players': players, 'teams': teams}
