"""승리 예측 API."""
import os
from typing import Optional
from fastapi import APIRouter, HTTPException, Request, Header, Query
from api.cache import cached
from api.security_log import log_admin_access
from api.prediction.model import predict_win_probability, reload_model
from api.prediction.park_factors import get_park_factors, invalidate_park_factors

router = APIRouter(prefix="/prediction", tags=["prediction"])

_ADMIN_KEY = os.environ.get("ADMIN_KEY", "")


@router.get("/game/{game_id}")
@cached(600)
def get_game_win_prediction(game_id: int):
    """게임 1건 승리 확률 + top factors. 캐시 10분 (선발 변경 빈도 낮음)."""
    result = predict_win_probability(game_id)
    if 'error' in result:
        raise HTTPException(status_code=404, detail=result['error'])
    return result


@router.get("/park-factors")
@cached(3600)
def get_park_factors_endpoint():
    """구장별 파크 팩터 (runs/hr)."""
    return get_park_factors()


@router.post("/admin/reload-model")
def admin_reload_model(request: Request, x_admin_key: Optional[str] = Header(None)):
    """모델 재로드 (학습 후). X-Admin-Key 헤더 인증 (URL pw 파라미터 대체)."""
    ip = request.client.host if request.client else "?"
    ep = "POST /prediction/admin/reload-model"
    if not _ADMIN_KEY:
        log_admin_access(ip, ep, "reload", "FAIL_NO_ENV")
        raise HTTPException(status_code=503, detail="관리자 기능 비활성화")
    if x_admin_key != _ADMIN_KEY:
        log_admin_access(ip, ep, "reload", "FAIL_WRONG_KEY")
        raise HTTPException(status_code=403, detail="권한 없음")
    log_admin_access(ip, ep, "reload", "OK")
    reload_model()
    invalidate_park_factors()
    return {"status": "reloaded"}


@router.get("/accuracy")
@cached(300)
def get_accuracy_history(limit: int = Query(30, ge=1, le=200)):
    """일별 정확도 + 최근 모델 정보."""
    from database.connection import get_connection
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500)
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT log_date, games, correct, accuracy, avg_log_loss
            FROM prediction_accuracy_daily
            ORDER BY log_date DESC LIMIT %s
        """, (limit,))
        rows = cur.fetchall()
        daily = [
            {'date': r[0].isoformat(), 'games': r[1], 'correct': r[2],
             'accuracy': round(float(r[3] or 0), 3),
             'log_loss': round(float(r[4] or 0), 3)}
            for r in rows
        ]
        # 전체 누적
        cur.execute("""
            SELECT COUNT(*) total, SUM(CASE WHEN correct THEN 1 ELSE 0 END) corr,
                   AVG(log_loss) avg_ll
            FROM prediction_log WHERE actual_winner IS NOT NULL
        """)
        total, corr, avg_ll = cur.fetchone()
        cur.close()
        overall = {
            'total': total or 0,
            'correct': corr or 0,
            'accuracy': round((corr / total) if total else 0, 3),
            'log_loss': round(float(avg_ll or 0), 3),
        }
        return {'daily': daily, 'overall': overall}
    finally:
        conn.close()
