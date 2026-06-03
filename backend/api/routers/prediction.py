"""승리 예측 API."""
from fastapi import APIRouter, HTTPException
from api.cache import cached
from api.prediction.model import predict_win_probability, reload_model
from api.prediction.park_factors import get_park_factors, invalidate_park_factors

router = APIRouter(prefix="/prediction", tags=["prediction"])


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
def admin_reload_model(pw: str = ""):
    """모델 재로드 (학습 후)."""
    if pw != "playball1234":
        raise HTTPException(status_code=403)
    reload_model()
    invalidate_park_factors()
    return {"status": "reloaded"}
