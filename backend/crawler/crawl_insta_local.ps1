# Namu wiki insta handle crawler (run from LOCAL PC - server IP gets 403)
# Output: insta_candidates.csv (review, then crawl_insta_handles.py --apply)
# NOTE: ASCII-only messages (PS5.1 reads no-BOM UTF8 as ANSI)
$ErrorActionPreference = 'Continue'
$H = @{'User-Agent'='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'}
$base = 'https://playball.duckdns.org'

$players = @()
foreach ($kind in @('hitters','pitchers')) {
  $sort = if ($kind -eq 'hitters') { 'avg' } else { 'era' }
  # PS5.1 charset bug: manual UTF-8 decode (Invoke-RestMethod mojibakes korean)
  $raw = Invoke-WebRequest -UseBasicParsing -Uri "$base/players/$($kind)?limit=500&sort_by=$sort" -TimeoutSec 30
  $json = [Text.Encoding]::UTF8.GetString($raw.RawContentStream.ToArray()) | ConvertFrom-Json
  foreach ($p in $json.$kind) {
    $tname = if ($p.team_name) { $p.team_name } elseif ($p.team) { $p.team } else { '' }
    $players += [pscustomobject]@{ id=$p.id; name=$p.name; team=$tname }
  }
}
Write-Output "total players: $($players.Count)"

$reserved = @('p','reel','reels','explore','accounts','stories','tv','about','directory')
$kw = [char]0xC57C + [char]0xAD6C   # 'yagu' korean word for baseball-doc guard
$suffix = '(' + $kw + [char]0xC120 + [char]0xC218 + ')'  # (yagu-seonsu)
$rows = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($p in $players) {
  $i++
  $handle = ''; $src = 'none'
  foreach ($title in @($p.name, ($p.name + $suffix))) {
    try {
      $enc = [uri]::EscapeDataString($title)
      $r = Invoke-WebRequest -UseBasicParsing -Uri "https://namu.wiki/w/$enc" -Headers $H -TimeoutSec 12
      if ($r.StatusCode -eq 200) {
        $ms = [regex]::Matches($r.Content, 'instagram\.com/([A-Za-z0-9._]{2,30})')
        foreach ($m in $ms) {
          $h = $m.Groups[1].Value.TrimEnd('.')
          if ($reserved -notcontains $h.ToLower()) { $handle = $h; $src = "namu:$title"; break }
        }
        if ($handle -and ($r.Content -notmatch $kw)) { $handle = ''; $src = 'not_baseball' }
        if ($handle) { break }
      }
    } catch {
      $msg = $_.Exception.Message
      $src = 'err:' + $msg.Substring(0, [math]::Min(30, $msg.Length))
    }
    Start-Sleep -Milliseconds 1500
  }
  $rows.Add([pscustomobject]@{ player_id=$p.id; name=$p.name; team=$p.team; handle=$handle; source=$src })
  $shown = if ($handle) { $handle } else { '-' }
  Write-Output "[$i/$($players.Count)] $($p.team) $($p.name) -> $shown ($src)"
  Start-Sleep -Milliseconds 1800
}
$rows | Export-Csv -Path "$PSScriptRoot\insta_candidates.csv" -NoTypeInformation -Encoding UTF8
$found = ($rows | Where-Object { $_.handle }).Count
Write-Output "DONE - $found/$($rows.Count) candidates. review insta_candidates.csv then --apply"
