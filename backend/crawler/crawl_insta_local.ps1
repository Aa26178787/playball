# 나무위키 인스타 핸들 수집 (로컬 PC 실행용 — 서버 IP는 403)
# 출력: insta_candidates.csv (검수 후 crawl_insta_handles.py --apply)
$ErrorActionPreference = 'Continue'
$H = @{'User-Agent'='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'}
$base = 'https://playball.duckdns.org'

# 선수 목록 (타자 + 투수, 시즌 기록 보유 현역)
$players = @()
foreach ($kind in @('hitters','pitchers')) {
  $d = Invoke-RestMethod -Uri "$base/players/$($kind)?limit=500&sort_by=$(if($kind -eq 'hitters'){'avg'}else{'era'})" -TimeoutSec 30
  foreach ($p in $d.$kind) {
    $players += [pscustomobject]@{ id=$p.id; name=$p.name; team=$p.team_name; code=$p.team_code }
  }
}
Write-Output "대상 $($players.Count)명"

$reserved = @('p','reel','reels','explore','accounts','stories','tv','about','directory')
$rows = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($p in $players) {
  $i++
  $handle = ''; $src = 'none'
  foreach ($title in @($p.name, "$($p.name)(야구선수)")) {
    try {
      $enc = [uri]::EscapeDataString($title)
      $r = Invoke-WebRequest -UseBasicParsing -Uri "https://namu.wiki/w/$enc" -Headers $H -TimeoutSec 12
      if ($r.StatusCode -eq 200) {
        $ms = [regex]::Matches($r.Content, 'instagram\.com/([A-Za-z0-9._]{2,30})')
        foreach ($m in $ms) {
          $h = $m.Groups[1].Value.TrimEnd('.')
          if ($reserved -notcontains $h.ToLower()) { $handle = $h; $src = "namu:$title"; break }
        }
        # 야구 문서인지 약식 확인 (동명이인 가드)
        if ($handle -and ($r.Content -notmatch '야구')) { $handle = ''; $src = 'not_baseball' }
        if ($handle) { break }
      }
    } catch { $src = "err:$($_.Exception.Message.Substring(0,[math]::Min(30,$_.Exception.Message.Length)))" }
    Start-Sleep -Milliseconds 1500
  }
  $rows.Add([pscustomobject]@{ player_id=$p.id; name=$p.name; team=$p.team; handle=$handle; source=$src })
  Write-Output "[$i/$($players.Count)] $($p.team) $($p.name) -> $(if($handle){$handle}else{'-'}) ($src)"
  Start-Sleep -Milliseconds 1800
}
$rows | Export-Csv -Path "$PSScriptRoot\insta_candidates.csv" -NoTypeInformation -Encoding UTF8
$found = ($rows | Where-Object { $_.handle }).Count
Write-Output "완료 — $found/$($rows.Count) 후보. insta_candidates.csv 검수 필요"
