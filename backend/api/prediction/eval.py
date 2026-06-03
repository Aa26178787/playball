"""예측 정확도 일별 평가 + 로깅."""
import math
from datetime import date as _date_cls, timedelta
from database.connection import get_connection
from api.prediction.model import predict_win_probability
from api.prediction.features import get_features


def log_prediction(game_id: int):
    """현재 모델 예측 결과를 prediction_log에 저장 (게임 시작 전)."""
    pred = predict_win_probability(game_id)
    if 'error' in pred or 'home_prob' not in pred:
        return
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        winner = 'home' if pred['home_prob'] > pred['away_prob'] else 'away'
        cur.execute("""
            INSERT INTO prediction_log
                (game_id, home_prob, away_prob, predicted_winner, model_version)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (game_id) DO UPDATE SET
                home_prob = EXCLUDED.home_prob,
                away_prob = EXCLUDED.away_prob,
                predicted_winner = EXCLUDED.predicted_winner,
                model_version = EXCLUDED.model_version,
                predicted_at = NOW()
        """, (game_id, pred['home_prob'], pred['away_prob'], winner,
              str(pred.get('model_version', ''))))
        conn.commit()
        cur.close()
    except Exception as e:
        print(f"[eval] log_prediction 오류 game={game_id}: {e}")
    finally:
        conn.close()


def evaluate_finished_games():
    """종료 게임 + prediction_log 있는 row → actual_winner, correct, log_loss 채우기."""
    conn = get_connection()
    if not conn:
        return 0
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT pl.game_id, pl.home_prob, pl.predicted_winner,
                   g.home_score, g.away_score
            FROM prediction_log pl
            JOIN games g ON g.id = pl.game_id
            WHERE g.status='종료' AND pl.actual_winner IS NULL
              AND g.home_score IS NOT NULL AND g.away_score IS NOT NULL
        """)
        rows = cur.fetchall()
        updates = 0
        for gid, home_prob, pred_winner, hs, as_ in rows:
            if hs == as_:
                continue  # 무승부는 평가 제외
            actual = 'home' if hs > as_ else 'away'
            correct = (pred_winner == actual)
            # log loss: -log(p_correct)
            p = home_prob if actual == 'home' else (1 - home_prob)
            p = max(min(p, 0.999), 0.001)
            ll = -math.log(p)
            cur.execute("""
                UPDATE prediction_log
                SET actual_winner=%s, correct=%s, log_loss=%s, evaluated_at=NOW()
                WHERE game_id=%s
            """, (actual, correct, ll, gid))
            updates += 1
        conn.commit()
        cur.close()
        return updates
    except Exception as e:
        print(f"[eval] evaluate 오류: {e}")
        return 0
    finally:
        conn.close()


def aggregate_daily_accuracy(target_date=None):
    """일별 accuracy 집계 → prediction_accuracy_daily."""
    if target_date is None:
        target_date = _date_cls.today() - timedelta(days=1)
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT COUNT(*) games,
                   SUM(CASE WHEN correct THEN 1 ELSE 0 END) correct,
                   AVG(log_loss) avg_ll,
                   MAX(model_version) mv
            FROM prediction_log pl
            JOIN games g ON g.id = pl.game_id
            WHERE g.game_date = %s AND pl.actual_winner IS NOT NULL
        """, (target_date,))
        row = cur.fetchone()
        if not row or not row[0]:
            cur.close()
            return
        games, correct, avg_ll, mv = row
        acc = (correct or 0) / games if games > 0 else 0.0
        cur.execute("""
            INSERT INTO prediction_accuracy_daily
                (log_date, games, correct, accuracy, avg_log_loss, model_version)
            VALUES (%s, %s, %s, %s, %s, %s)
            ON CONFLICT (log_date) DO UPDATE SET
                games = EXCLUDED.games,
                correct = EXCLUDED.correct,
                accuracy = EXCLUDED.accuracy,
                avg_log_loss = EXCLUDED.avg_log_loss,
                model_version = EXCLUDED.model_version,
                created_at = NOW()
        """, (target_date, games, correct or 0, acc, avg_ll, mv))
        conn.commit()
        cur.close()
        print(f"[eval] {target_date}: {correct}/{games} ({acc:.3f}), logloss={avg_ll:.3f}")
    except Exception as e:
        print(f"[eval] daily aggregate 오류: {e}")
    finally:
        conn.close()


def log_today_predictions():
    """오늘 예정/진행중 게임 전체 예측 로깅."""
    conn = get_connection()
    if not conn:
        return
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT id FROM games
            WHERE game_date = CURRENT_DATE AND status IN ('예정', '라인업', '진행')
        """)
        ids = [r[0] for r in cur.fetchall()]
        cur.close()
    finally:
        conn.close()
    for gid in ids:
        try:
            log_prediction(gid)
        except Exception:
            pass
    print(f"[eval] 오늘 {len(ids)}개 예측 로깅")


def daily_pipeline():
    """매일 자정 호출: 어제 평가 + 집계 + 오늘 로깅 + 재학습."""
    print("[daily-pipeline] 시작")
    n = evaluate_finished_games()
    print(f"[daily-pipeline] evaluate: {n}건")
    aggregate_daily_accuracy()
    log_today_predictions()
    # 재학습
    try:
        from api.prediction.model import train_model, reload_model
        train_model()
        reload_model()
        print("[daily-pipeline] 재학습 + reload 완료")
    except Exception as e:
        print(f"[daily-pipeline] 재학습 오류: {e}")
