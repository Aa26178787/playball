# Fill MISSING insta handles: namu finds candidates, imginn confirms ownership (avoid family-account fills)
# Input : insta_missing2.tsv  (id<TAB>team<TAB>name<TAB>is_foreign)
# Output: insta_fill_missing.csv  (status: FILLED / namu_unverified / no_namu)
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$UA = @{'User-Agent'='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'}
$ygkw = [char]0xC57C + [char]0xAD6C
$sfx  = '(' + $ygkw + [char]0xC120 + [char]0xC218 + ')'
$reserved = @('p','reel','reels','explore','accounts','stories','tv','about','directory','privacy','legal')
$TKW = @{
  'HH'='한화|hanwha'; 'HT'='KIA|타이거즈|tigers|kia'; 'KT'='위즈|wiz|ktwiz'; 'LG'='트윈스|twins|lgtwins';
  'LT'='롯데|자이언츠|giants|lotte'; 'NC'='다이노스|dinos|ncdinos'; 'OB'='두산|베어스|bears|doosan';
  'SK'='SSG|랜더스|landers'; 'SS'='삼성|라이온즈|lions|samsung'; 'WO'='키움|히어로즈|heroes|kiwoom'
}
function nz($s){ if($null -eq $s){return ''}; ($s.Normalize([Text.NormalizationForm]::FormC) -replace '\s','') }

$rows = Import-Csv "$PSScriptRoot\insta_missing2.tsv" -Delimiter "`t" -Header id,team,name,foreign -Encoding UTF8
Write-Output "missing: $($rows.Count)"
$out = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($r in $rows) {
  $i++
  # 1) namu candidates
  $cands = @()
  foreach ($title in @(($r.name + $sfx), $r.name)) {
    try {
      $resp = Invoke-WebRequest -UseBasicParsing -Uri "https://namu.wiki/w/$([uri]::EscapeDataString($title))" -Headers $UA -TimeoutSec 12
      if ($resp.StatusCode -eq 200 -and ($resp.Content -match $ygkw -or $r.foreign -eq 'true')) {
        $ms = [regex]::Matches($resp.Content,'instagram\.com/([A-Za-z0-9._]{2,30})') | ForEach-Object { $_.Groups[1].Value.TrimEnd('.') } | Where-Object { $reserved -notcontains $_.ToLower() } | Select-Object -Unique
        if ($ms) { $cands = @($ms); break }
      }
    } catch {}
    Start-Sleep -Milliseconds 1400
  }
  # 2) imginn verify each candidate (display name = player, or bio has team)
  $found = ''; $vby = ''
  foreach ($h in $cands) {
    try {
      $ir = Invoke-WebRequest -UseBasicParsing -Uri "https://imginn.com/$h/" -Headers $UA -TimeoutSec 15
      $disp = if ($ir.Content -match 'og:title" content="([^"]+)"') { ($Matches[1] -replace '\(@.*$','').Trim() } else { '' }
      $bio  = if ($ir.Content -match 'og:description" content="([^"]+)"') { $Matches[1] } else { '' }
      if ($disp) {
        if ((nz $disp) -and ((nz $disp).Contains((nz $r.name)) -or (nz $r.name).Contains((nz $disp)))) { $found = $h; $vby = 'name'; break }
        elseif ($TKW[$r.team] -and ($bio -match $TKW[$r.team])) { $found = $h; $vby = 'team'; break }
      }
    } catch {}
    Start-Sleep -Milliseconds 1600
  }
  $status = if ($found) { 'FILLED' } elseif ($cands.Count) { 'namu_unverified' } else { 'no_namu' }
  $out.Add([pscustomobject]@{ id=$r.id; team=$r.team; name=$r.name; found=$found; vby=$vby; status=$status; cands=($cands -join ',') })
  if ($found) { Write-Output "[$i/$($rows.Count)] *** FILLED $($r.team) $($r.name) -> $found ($vby)" }
  else { Write-Output "[$i/$($rows.Count)] $status $($r.team) $($r.name) cands=$($cands -join ',')" }
  Start-Sleep -Milliseconds 1200
}
$out | Export-Csv -Path "$PSScriptRoot\insta_fill_missing.csv" -NoTypeInformation -Encoding UTF8
$f = @($out | Where-Object { $_.status -eq 'FILLED' })
Write-Output "DONE -> insta_fill_missing.csv  FILLED=$($f.Count)"
