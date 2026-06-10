# Build a single-page HTML to review ALL insta handles fast.
# Input : insta_review.tsv  (id<TAB>team<TAB>name<TAB>handle<TAB>photo<TAB>reports)
# Output: insta_review.html  (open in browser; check WRONG / type correct handle; click 'Generate SQL')
$rows = Import-Csv "$PSScriptRoot\insta_review.tsv" -Delimiter "`t" -Header id,team,name,handle,photo,rep -Encoding UTF8

$head = @'
<!doctype html><html><head><meta charset="utf-8"><title>insta review</title>
<style>
body{font-family:-apple-system,Segoe UI,sans-serif;margin:0;background:#0d0d10;color:#eee}
#bar{position:sticky;top:0;background:#16161b;padding:10px 14px;border-bottom:1px solid #333;z-index:9}
#bar b{color:#7ab8ff}
.team{font-weight:700;color:#7ab8ff;margin:18px 14px 4px;font-size:15px}
.r{display:flex;align-items:center;gap:10px;padding:7px 14px;border-bottom:1px solid #1d1d22}
.r img{width:46px;height:46px;border-radius:8px;object-fit:cover;background:#222}
.r .nm{flex:0 0 150px}
.r .nm b{font-size:14px}.r .nm .t{color:#888;font-size:11px}
.r a{color:#ff7aa8;text-decoration:none;font-size:13px}.r a:hover{text-decoration:underline}
.r .lk{flex:1;font-size:12px;color:#888}
.r .lk a.g{color:#9ad} .r .lk a.n{color:#9d9}
.r input.fix{width:150px;background:#1d1d22;border:1px solid #333;color:#eee;padding:5px;border-radius:5px;font-size:12px}
.r label{font-size:12px;color:#f88;white-space:nowrap}
.rep{background:#a33;color:#fff;border-radius:8px;padding:1px 6px;font-size:11px}
#gen{position:fixed;right:16px;bottom:16px;background:#2a6;color:#fff;border:0;padding:12px 18px;border-radius:24px;font-size:15px;cursor:pointer;z-index:20}
#out{position:fixed;left:0;right:0;bottom:0;height:0;background:#000;color:#0f0;font-family:monospace;font-size:12px;overflow:auto;transition:height .2s;white-space:pre;padding:0 12px}
#out.show{height:40vh;padding:12px}
</style></head><body>
<div id="bar"><b>insta review</b> &middot; WRONG 체크하면 NULL / 올바른 핸들 입력하면 교체 &middot; <span id="cnt">0</span> marked</div>
'@

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append($head)
$lastTeam = ''
foreach ($r in $rows) {
  if ($r.team -ne $lastTeam) { [void]$sb.Append("<div class='team'>$($r.team)</div>"); $lastTeam = $r.team }
  $repBadge = if ([int]$r.rep -gt 0) { "<span class='rep'>!$($r.rep)</span>" } else { '' }
  $g = "https://www.google.com/search?q=$([uri]::EscapeDataString($r.name + ' ' + $r.handle))"
  $n = "https://namu.wiki/w/$([uri]::EscapeDataString($r.name))"
  [void]$sb.Append("<div class='r' data-id='$($r.id)'><img src='$($r.photo)' loading='lazy' onerror=`"this.style.opacity=.15`"><div class='nm'><b>$($r.name)</b> $repBadge<br><span class='t'>$($r.team)</span></div><a href='https://instagram.com/$($r.handle)' target='_blank'>@$($r.handle)</a><div class='lk'> &middot; <a class='g' href='$g' target='_blank'>google</a> &middot; <a class='n' href='$n' target='_blank'>namu</a></div><input class='fix' placeholder='correct handle'><label><input type='checkbox' class='wrong'> WRONG</label></div>")
}

$foot = @'
<button id="gen" onclick="gen()">Generate SQL</button>
<div id="out"></div>
<script>
function upd(){var c=0;document.querySelectorAll(".r").forEach(function(r){var w=r.querySelector(".wrong").checked,f=r.querySelector(".fix").value.trim();if(w||f)c++;});document.getElementById("cnt").textContent=c;}
document.addEventListener("input",upd);document.addEventListener("change",upd);
function gen(){var s=[];document.querySelectorAll(".r").forEach(function(r){var id=r.dataset.id,w=r.querySelector(".wrong").checked,f=r.querySelector(".fix").value.trim();if(f){s.push("UPDATE players SET insta_handle='"+f.replace(/^@/,"")+"' WHERE id="+id+";");}else if(w){s.push("UPDATE players SET insta_handle=NULL WHERE id="+id+";");}});var o=document.getElementById("out");o.textContent=s.length?s.join("\n"):"(nothing marked)";o.classList.add("show");o.scrollIntoView();}
</script></body></html>
'@
[void]$sb.Append($foot)
[IO.File]::WriteAllText("$PSScriptRoot\insta_review.html", $sb.ToString(), (New-Object Text.UTF8Encoding $true))
Write-Output "wrote insta_review.html  ($($rows.Count) players)"
