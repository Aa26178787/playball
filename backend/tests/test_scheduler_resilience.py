import schedule

import crawler.scheduler as scheduler
import crawler.statiz_crawler as stats


class _Cursor:
    def __init__(self):
        self.commands = []

    def execute(self, sql, params=None):
        self.commands.append((sql, params))


def test_derived_failure_rolls_back_only_savepoint(monkeypatch):
    cur = _Cursor()

    def fail(_cur, _season):
        raise OverflowError("numeric field overflow")

    monkeypatch.setattr(stats, "recompute_pitcher_derived", fail)

    assert stats.recompute_derived_safely(cur, "PITCHER", 2026) is False
    assert [sql for sql, _ in cur.commands] == [
        "SAVEPOINT sp_derived",
        "ROLLBACK TO SAVEPOINT sp_derived",
        "RELEASE SAVEPOINT sp_derived",
    ]


def test_derived_success_releases_savepoint(monkeypatch):
    cur = _Cursor()
    called = []
    monkeypatch.setattr(
        stats,
        "recompute_batter_derived",
        lambda _cur, season: called.append(season),
    )

    assert stats.recompute_derived_safely(cur, "HITTER", 2026) is True
    assert called == [2026]
    assert [sql for sql, _ in cur.commands] == [
        "SAVEPOINT sp_derived",
        "RELEASE SAVEPOINT sp_derived",
    ]


def test_pitcher_babip_is_clamped_to_valid_probability():
    cur = _Cursor()
    stats.recompute_pitcher_derived(cur, 2026)
    derived_sql = cur.commands[1][0]
    assert "LEAST(1, GREATEST(0" in derived_sql


def test_scheduled_job_failure_is_consumed():
    def fail():
        raise RuntimeError("boom")

    assert scheduler._run_scheduled_job(fail) is None


def test_scheduled_job_does_not_propagate_cancel():
    assert scheduler._run_scheduled_job(lambda: schedule.CancelJob) is None


def test_one_shot_failure_is_cancelled():
    def fail():
        raise RuntimeError("boom")

    assert scheduler._run_once(fail) is schedule.CancelJob
