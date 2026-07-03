"""투구 물리값 백필 — 위치 있으나 물리값 없는 종료경기 재크롤(replace).
현 INSERT는 ON CONFLICT 없어 game별 DELETE 후 재삽입. live-guard·resume.
⚠️ DELETE 후 재크롤 실패 시 그 경기는 위치 0행 → crawl_all_past_pitch_locations(NOT EXISTS)가 재수집 대상."""
import sys, time
from datetime import datetime
from database.connection import get_connection
from crawler.crawl_pitch_locations import save_pitch_locations_for_game


def _targets(limit):
    conn = get_connection()
    if not conn:
        return []
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT g.id, g.naver_game_id, COALESCE(MAX(gi.inning),9)
            FROM games g LEFT JOIN game_innings gi ON gi.game_id=g.id
            WHERE g.status='종료' AND g.naver_game_id IS NOT NULL
              AND EXISTS (SELECT 1 FROM game_pitch_locations l WHERE l.game_id=g.id)
              AND NOT EXISTS (SELECT 1 FROM game_pitch_locations l WHERE l.game_id=g.id AND l.x0 IS NOT NULL)
            GROUP BY g.id, g.naver_game_id ORDER BY g.game_date DESC LIMIT %s
        """, (limit,))
        rows = cur.fetchall()
        cur.close()
        return rows
    finally:
        conn.close()


def main():
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 100000
    done = 0
    while True:
        batch = _targets(50)
        if not batch:
            break
        for gid, ngid, max_inn in batch:
            h = datetime.now().hour  # KST 서버 시간
            if 17 <= h < 23:
                print("[백필] live-guard 정지"); return
            # 기존 물리없는 위치 DELETE (커넥션 try/finally 반납)
            c = get_connection()
            if not c:
                continue
            try:
                cu = c.cursor()
                cu.execute("DELETE FROM game_pitch_locations WHERE game_id=%s", (gid,))
                c.commit()
                cu.close()
            except Exception as e:
                print(f"[백필] game={gid} DELETE 오류 {e}", flush=True)
                continue
            finally:
                c.close()
            # 재크롤(replace) — 실패 시 그 경기 위치 삭제된 상태(재수집 대상)로 남으니 명시 로그
            try:
                n = save_pitch_locations_for_game(gid, ngid, int(max_inn))
                done += 1
                print(f"[백필] game={gid} {n}구 (누적 {done})", flush=True)
            except Exception as e:
                print(f"[백필] game={gid} DELETE됨·재크롤 실패 — 재수집 필요: {e}", flush=True)
            time.sleep(0.5)
            if done >= limit:
                return


if __name__ == '__main__':
    main()
