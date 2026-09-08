# playball-backend

## Local setup (PowerShell)

Use a project-local Python 3.11 environment. Do not install packages into
`backend/Lib` or commit virtual-environment files.

```powershell
uv python install 3.11
uv venv .venv --python 3.11
uv pip install --python .venv\Scripts\python.exe -r requirements.txt pytest
$env:JWT_SECRET_KEY = 'local-development-only'
.\.venv\Scripts\python.exe -m pytest tests
.\.venv\Scripts\python.exe -m uvicorn api.main:app --reload
```

Development-only verification codes are disabled by default. To print email/SMS
codes locally, explicitly set `ALLOW_DEV_VERIFICATION_CODES=1`.

## Database migrations

On the server, apply named migrations before restarting the API or scheduler:

```bash
cd /home/ubuntu/playball/backend
bash Scripts/apply_migrations.sh \
  2026-09-08_auth_verification_hardening.sql \
  2026-09-08_pitcher_stats_numeric_range.sql
```

Applied filenames and checksums are recorded in `schema_migrations`.
