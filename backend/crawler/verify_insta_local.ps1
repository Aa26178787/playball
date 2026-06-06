# Verify risky insta candidates: namu doc must contain player's team name
$ErrorActionPreference = 'Continue'
$UAHDR = @{'User-Agent'='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'}
$csv = Import-Csv "$PSScriptRoot\insta_candidates.csv"
$out = New-Object System.Collections.Generic.List[object]
$risky = @($csv | Where-Object { $_.handle -and $_.source -notmatch [char]0xC57C })  # source without yagu-bunki marker fallback below
# safer: split by source pattern '(...)'
$risky = @($csv | Where-Object { $_.handle -and $_.source -notmatch '\(' })
$safe  = @($csv | Where-Object { $_.handle -and $_.source -match '\(' })
Write-Output "safe=$($safe.Count) risky=$($risky.Count)"
foreach ($r in $safe) { $out.Add([pscustomobject]@{ player_id=$r.player_id; name=$r.name; team=$r.team; handle=$r.handle; verdict='safe_branch' }) }
$i = 0
foreach ($r in $risky) {
  $i++
  $verdict = 'drop_no_team'
  try {
    $enc = [uri]::EscapeDataString($r.name)
    $resp = Invoke-WebRequest -UseBasicParsing -Uri "https://namu.wiki/w/$enc" -Headers $UAHDR -TimeoutSec 12
    if ($resp.StatusCode -eq 200 -and $r.team -and ($resp.Content -match [regex]::Escape($r.team))) {
      $verdict = 'team_ok'
    }
  } catch { $verdict = 'err' }
  if ($verdict -eq 'team_ok') {
    $out.Add([pscustomobject]@{ player_id=$r.player_id; name=$r.name; team=$r.team; handle=$r.handle; verdict=$verdict })
  } else {
    $out.Add([pscustomobject]@{ player_id=$r.player_id; name=$r.name; team=$r.team; handle=''; verdict=$verdict })
  }
  Write-Output "[$i/$($risky.Count)] $($r.team) $($r.name) -> $verdict"
  Start-Sleep -Milliseconds 1800
}
$out | Export-Csv -Path "$PSScriptRoot\insta_verified.csv" -NoTypeInformation -Encoding UTF8
$kept = ($out | Where-Object { $_.handle }).Count
Write-Output "DONE verified=$kept/$($out.Count) -> insta_verified.csv"
