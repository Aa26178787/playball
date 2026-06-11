# PlayBall DB 백업 오프사이트 pull — 매일 트리거 + 6일 스로틀 (실제 pull은 주 1회)
# 등록: schtasks /Create /SC DAILY /ST 12:00 /TN PlayballBackupPull /TR "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\Users\qq772\playball\backup_pull.ps1" /F
$ErrorActionPreference = 'Stop'
$dir = "$env:USERPROFILE\playball_backups"
$marker = Join-Path $dir '.last_pull'
$key = 'C:\Users\qq772\Downloads\ssh-key-2026-03-28 (2).key'
$srv = 'ubuntu@168.107.36.158'
$ssh = "$env:SystemRoot\System32\OpenSSH\ssh.exe"
$scp = "$env:SystemRoot\System32\OpenSSH\scp.exe"

if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
if (Test-Path $marker) {
    $age = (Get-Date) - (Get-Item $marker).LastWriteTime
    if ($age.TotalDays -lt 6) { exit 0 }
}

$latest = (& $ssh -i $key -o StrictHostKeyChecking=no $srv 'ls -t ~/backups/playball_*.sql.gz | head -1').Trim()
if (-not $latest) { exit 1 }
& $scp -i $key -o StrictHostKeyChecking=no "${srv}:$latest" $dir
if ($LASTEXITCODE -ne 0) { exit 1 }

# 무결성 최소 확인: 1MB 미만이면 실패 간주 (빈 백업 사고 방지)
$f = Join-Path $dir (Split-Path $latest -Leaf)
if ((Get-Item $f).Length -lt 1MB) { Remove-Item $f; exit 1 }

# 로컬 보관 4개 초과분 삭제
Get-ChildItem $dir -Filter 'playball_*.sql.gz' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 4 | Remove-Item
Set-Content -Path $marker -Value (Get-Date -Format s)
