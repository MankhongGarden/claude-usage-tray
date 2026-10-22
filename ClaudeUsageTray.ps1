# ClaudeUsageTray - Claude plan usage (5-hour + weekly) and Anthropic server status in one tray icon.
# Icon: 5h % on a coloured tile, weekly % as a bar along the bottom, a dot in the
# corner while Claude Code is not operational. Left-click = popup, right-click = menu.
# Saved as UTF-8 with BOM so Windows PowerShell 5.1 reads the Thai strings correctly.

$AppName = 'ClaudeUsageTray'
$Cfg = $null
$CfgF = Join-Path $PSScriptRoot 'config.json'
try { if (Test-Path -LiteralPath $CfgF) { $Cfg = Get-Content -LiteralPath $CfgF -Raw -Encoding UTF8 | ConvertFrom-Json } } catch { }
function Opt([string]$name, $default) {
    if ($Cfg -and $Cfg.PSObject.Properties[$name]) {
        $v = $Cfg.$name
        if ($null -ne $v -and -not ($v -is [string] -and $v -eq '')) { return $v }
    }
    return $default
}

$Root = [Environment]::ExpandEnvironmentVariables((Opt 'dataDir' (Join-Path $env:LOCALAPPDATA 'claude-usage-tray')))
if (-not (Test-Path -LiteralPath $Root)) { New-Item -ItemType Directory -Force -Path $Root | Out-Null }
$LogF    = Join-Path $Root 'claude-usage-tray.log'
$StateF  = Join-Path $Root 'state.json'
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
$CredF   = [Environment]::ExpandEnvironmentVariables((Opt 'credentialsFile' (Join-Path $ClaudeDir '.credentials.json')))
$Account = [string](Opt 'accountLabel' '')
$Lang    = [string](Opt 'language' 'en')
$QuotaMin = [int](Opt 'quotaMinutes' 5)
$StatusSec = [int](Opt 'statusSeconds' 60)
$AlertPct = [double](Opt 'alertPercent' 95)
$WatchComp = 'yyzkbfz2thpt'   # Claude Code: drives the icon dot and notifications
$Comps = [ordered]@{ 'yyzkbfz2thpt' = 'Claude Code'; 'bpp5gb3hpjcl' = 'Cowork'; 'k8w3r06qmzrp' = 'API'; 'rwppv331jlwc' = 'claude.ai' }

function Log([string]$m) {
    try {
        if ((Test-Path $LogF) -and (Get-Item $LogF).Length -gt 1MB) { Move-Item $LogF "$LogF.old" -Force }
        Add-Content -LiteralPath $LogF -Value ("{0} {1}" -f (Get-Date -Format s), $m) -Encoding UTF8
    } catch { }
}
$ErrorActionPreference = 'Stop'
function Safe([scriptblock]$b, [string]$where) {
    try { & $b } catch { Log ("ERR {0}: {1} @ {2}" -f $where, $_.Exception.Message, $_.InvocationInfo.PositionMessage -replace '\s+', ' ') }
}

$RootKey = [BitConverter]::ToString([Security.Cryptography.SHA1]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($Root.ToLowerInvariant()))).Replace('-', '').Substring(0, 12)
$mtx = New-Object System.Threading.Mutex($false, "Local\$AppName-$RootKey")
if (-not $mtx.WaitOne(0)) { exit 0 }

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CtNative {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr hIcon);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int v);
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);
}
"@
[void][CtNative]::SetProcessDPIAware()
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({ param($s, $e) Log ("TICK-ERR " + $e.Exception.Message + " @ " + $e.Exception.StackTrace) })
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Log "START pid=$PID"

$DOT = [string][char]0xB7

# ------------------------------------------------------------ strings
$Str = @{
    en = @{
        noToken = 'No Claude Code login token found'; expired = 'Token expired - open Claude Code once to renew it'
        badFile = 'Cannot read the token file'; netErr = 'Cannot reach api.anthropic.com'
        rejected = 'Token rejected - open Claude Code once to renew it'; limited = 'Rate limited (429) - retrying in 10 min'
        five = '5-hour'; week = 'Weekly'; reset = 'resets'; used = 'Claude {0} usage at {1:N0}%'
        statusErr = 'Cannot check server status'; backOk = 'Claude Code is back to normal'; before = 'Before: '
        seeStatus = 'See status.claude.com for details'; soon = 'soon'; inMin = 'in {0} min'; inHM = 'in {0} h {1} min'
        loading = 'Loading...'; updated = 'updated '; refresh = 'refresh'; noData = 'No data yet'; weekly = '{0} weekly'
        checking = 'Checking server status...'; ok = 'operational'; started = 'since '; unknown = 'unknown'
        mRefresh = 'Refresh now'; mStatus = 'Open status.claude.com'; mUsage = 'Open usage page'; mLog = 'Open log folder'; mExit = 'Exit'
        operational = 'operational'; degraded_performance = 'degraded performance'; partial_outage = 'partial outage'; major_outage = 'major outage'; under_maintenance = 'under maintenance'
        investigating = 'investigating'; identified = 'identified'; monitoring = 'monitoring'; scheduled = 'scheduled'; in_progress = 'in progress'; verifying = 'verifying'
    }
    th = @{
        noToken = 'ไม่พบ token ของ Claude Code'; expired = 'token หมดอายุ · เปิด Claude Code สักครั้งเพื่อต่ออายุ'
        badFile = 'อ่านไฟล์ token ไม่ได้'; netErr = 'ต่อ api.anthropic.com ไม่ได้'
        rejected = 'token ใช้ไม่ได้ · เปิด Claude Code สักครั้งเพื่อต่ออายุ'; limited = 'ถูกจำกัดความถี่ (429) · จะลองใหม่ใน 10 นาที'
        five = '5 ชั่วโมง'; week = 'รายสัปดาห์'; reset = 'รีเซ็ต'; used = 'Claude quota {0} ใช้ไป {1:N0}%'
        statusErr = 'ตรวจสถานะเซิร์ฟเวอร์ไม่ได้'; backOk = 'Claude Code กลับมาปกติแล้ว'; before = 'ก่อนหน้านี้: '
        seeStatus = 'ดูรายละเอียดที่ status.claude.com'; soon = 'เร็วๆ นี้'; inMin = 'ในอีก {0} นาที'; inHM = 'ในอีก {0} ชม. {1} นาที'
        loading = 'กำลังโหลด...'; updated = 'อัปเดต '; refresh = 'รีเฟรช'; noData = 'ยังไม่มีข้อมูล'; weekly = '{0} รายสัปดาห์'
        checking = 'กำลังตรวจสถานะเซิร์ฟเวอร์...'; ok = 'ปกติ'; started = 'เริ่ม '; unknown = 'ไม่ทราบ'
        mRefresh = 'รีเฟรชเดี๋ยวนี้'; mStatus = 'เปิด status.claude.com'; mUsage = 'เปิดหน้า usage'; mLog = 'เปิดโฟลเดอร์ log'; mExit = 'ออก'
        operational = 'ปกติ'; degraded_performance = 'ทำงานช้าบางส่วน'; partial_outage = 'ล่มบางส่วน'; major_outage = 'ล่ม'; under_maintenance = 'ปิดปรับปรุง'
        investigating = 'กำลังตรวจสอบ'; identified = 'พบสาเหตุแล้ว'; monitoring = 'กำลังติดตามผล'; scheduled = 'นัดปิดปรับปรุง'; in_progress = 'กำลังปรับปรุง'; verifying = 'กำลังตรวจผล'
    }
}
if (-not $Str.ContainsKey($Lang)) { $Lang = 'en' }
$L = $Str[$Lang]
$Cul = if ($Lang -eq 'th') { [Globalization.CultureInfo]::GetCultureInfo('th-TH') } else { [Globalization.CultureInfo]::CurrentCulture }

# ------------------------------------------------------------ state
$script:St = @{ quotaAlert = @{}; codeStatus = $null }
try {
    if (Test-Path $StateF) {
        $l = Get-Content $StateF -Raw | ConvertFrom-Json
        if ($l.quotaAlert) { foreach ($p in $l.quotaAlert.PSObject.Properties) { $script:St.quotaAlert[$p.Name] = $p.Value } }
        $script:St.codeStatus = $l.codeStatus
    }
} catch { Log "STATE-LOAD $($_.Exception.Message)" }
function Save-State { try { $script:St | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $StateF -Encoding UTF8 } catch { Log "STATE-SAVE $($_.Exception.Message)" } }

function D($v) {
    if ($null -eq $v -or $v -eq '') { return $null }
    return [datetimeoffset]::Parse([string]$v, [Globalization.CultureInfo]::InvariantCulture).LocalDateTime
}

# ------------------------------------------------------------ HTTP (async, polled by the timer)
$http = New-Object System.Net.Http.HttpClient
$http.Timeout = [TimeSpan]::FromSeconds(25)
$script:Req = @{}
function Start-Http([string]$kind, [System.Net.Http.HttpRequestMessage]$msg) {
    $script:Req[$kind] = @{ T = $http.SendAsync($msg); C = $null; Code = 0 }
}
function Poll-Http([string]$kind) {
    # $null while pending; afterwards @{ Code; Body; Err }
    $r = $script:Req[$kind]
    if (-not $r) { return $null }
    if (-not $r.C) {
        if (-not $r.T.IsCompleted) { return $null }
        if ($r.T.IsFaulted -or $r.T.IsCanceled) {
            $script:Req.Remove($kind)
            $m = if ($r.T.Exception) { $r.T.Exception.GetBaseException().Message } else { 'timeout' }
            return @{ Code = 0; Body = $null; Err = $m }
        }
        $r.Code = [int]$r.T.Result.StatusCode
        $r.C = $r.T.Result.Content.ReadAsStringAsync()
        return $null
    }
    if (-not $r.C.IsCompleted) { return $null }
    $script:Req.Remove($kind)
    if ($r.C.IsFaulted) { return @{ Code = $r.Code; Body = $null; Err = $r.C.Exception.GetBaseException().Message } }
    return @{ Code = $r.Code; Body = $r.C.Result; Err = $null }
}

# Claude Code version for the User-Agent header: config, else `claude --version`, else a fallback.
$script:CliVer = [string](Opt 'claudeVersion' '')
if (-not $script:CliVer) {
    try {
        $v = (& claude --version 2>$null | Select-Object -First 1)
        if ($v -match '(\d+\.\d+\.\d+)') { $script:CliVer = $Matches[1] }
    } catch { }
}
if (-not $script:CliVer) { $script:CliVer = '2.1.280' }

# ------------------------------------------------------------ data
$script:Q = $null          # parsed quota
$script:QAt = $null
$script:QErr = ''
$script:S = $null          # parsed status
$script:SAt = $null
$script:SErr = ''
$script:NextQuota = Get-Date
$script:NextStatus = Get-Date

function Start-Quota {
    if ($script:Req['quota']) { return }
    if ([System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -eq 'Offline' -and $script:Q) { return }
    try {
        $c = (Get-Content $CredF -Raw | ConvertFrom-Json).claudeAiOauth
        if (-not $c.accessToken) { $script:QErr = $L.noToken; return }
        if ($c.expiresAt -and [DateTimeOffset]::FromUnixTimeMilliseconds([long]$c.expiresAt) -lt [DateTimeOffset]::Now) {
            $script:QErr = $L.expired; Update-View; return
        }
        $msg = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, 'https://api.anthropic.com/api/oauth/usage')
        [void]$msg.Headers.TryAddWithoutValidation('Authorization', 'Bearer ' + $c.accessToken)
        [void]$msg.Headers.TryAddWithoutValidation('anthropic-beta', 'oauth-2025-04-20')
        [void]$msg.Headers.TryAddWithoutValidation('User-Agent', "claude-code/$($script:CliVer) (external, cli)")
        Start-Http 'quota' $msg
    } catch { $script:QErr = $L.badFile; Log "QUOTA-START $($_.Exception.Message)" }
}

function Parse-Quota($p) {
    $q = @{ five = $null; week = $null; scoped = @() }
    foreach ($k in 'five_hour', 'seven_day') {
        $b = $p.$k
        if ($b -and $null -ne $b.utilization) {
            $o = @{ pct = [double]$b.utilization; reset = (D $b.resets_at) }
            if ($k -eq 'five_hour') { $q.five = $o } else { $q.week = $o }
        }
    }
    $sc = @()
    foreach ($l in @($p.limits)) {
        if ($l.kind -eq 'weekly_scoped' -and $l.scope -and $l.scope.model) {
            $sc += @{ name = [string]$l.scope.model.display_name; pct = [double]$l.percent }
        }
    }
    foreach ($pair in @(@('seven_day_opus', 'Opus'), @('seven_day_sonnet', 'Sonnet'))) {
        $b = $p.($pair[0])
        if ($b -and $null -ne $b.utilization -and -not ($sc | Where-Object { $_.name -eq $pair[1] })) { $sc += @{ name = $pair[1]; pct = [double]$b.utilization } }
    }
    $q.scoped = $sc
    return $q
}

function Finish-Quota($r) {
    if ($r.Err) { $script:QErr = $L.netErr; Log "QUOTA-ERR $($r.Err)"; return }
    if ($r.Code -eq 401 -or $r.Code -eq 403) { $script:QErr = $L.rejected; Log "QUOTA-HTTP $($r.Code)"; return }
    if ($r.Code -eq 429) { $script:QErr = $L.limited; $script:NextQuota = (Get-Date).AddMinutes(10); Log 'QUOTA-HTTP 429'; return }
    if ($r.Code -ne 200) { $script:QErr = "HTTP $($r.Code)"; Log "QUOTA-HTTP $($r.Code) $($r.Body)"; return }
    $script:Q = Parse-Quota ($r.Body | ConvertFrom-Json)
    $script:QAt = Get-Date
    $script:QErr = ''
    try { Set-Content -LiteralPath (Join-Path $Root 'last-usage.json') -Value $r.Body -Encoding UTF8 } catch { }
    foreach ($pair in @(@('five', $L.five), @('week', $L.week))) {
        $b = $script:Q[$pair[0]]
        if (-not $b -or $b.pct -lt $AlertPct) { continue }
        $key = if ($b.reset) { $b.reset.ToString('s') } else { 'x' }
        if ($script:St.quotaAlert[$pair[0]] -eq $key) { continue }
        $script:St.quotaAlert[$pair[0]] = $key; Save-State
        Notify ($L.used -f $pair[1], $b.pct) ($L.reset + ' ' + (Reset-Text $b.reset $pair[0])) 'warn'
    }
}

function Start-Status {
    if ($script:Req['status']) { return }
    if ($env:CLAUDE_USAGE_TRAY_STATUS_FILE) { Finish-Status @{ Code = 200; Body = (Get-Content $env:CLAUDE_USAGE_TRAY_STATUS_FILE -Raw -Encoding UTF8); Err = $null }; Update-View; return }
    $msg = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, 'https://status.claude.com/api/v2/summary.json')
    Start-Http 'status' $msg
}

function Finish-Status($r) {
    if ($r.Err -or $r.Code -ne 200) { $script:SErr = $L.statusErr; Log "STATUS-ERR $($r.Code) $($r.Err)"; return }
    $j = $r.Body | ConvertFrom-Json
    $comp = @{}
    foreach ($c in $j.components) { if ($Comps.Contains($c.id)) { $comp[$c.id] = [string]$c.status } }
    $inc = @()
    foreach ($i in @($j.incidents) + @($j.scheduled_maintenances)) {
        if (-not $i -or $i.status -in 'resolved', 'completed', 'postmortem') { continue }
        if ($i.PSObject.Properties['scheduled_for'] -and $i.status -eq 'scheduled') { continue }
        $ids = @($i.components | ForEach-Object { $_.id })
        $hit = @($ids | Where-Object { $Comps.Contains($_) })
        if ($ids.Count -and -not $hit.Count) { continue }
        $inc += @{ name = [string]$i.name; status = [string]$i.status; at = (D $i.created_at); code = ($hit -contains $WatchComp) }
    }
    $script:S = @{ comp = $comp; inc = $inc }
    $script:SAt = Get-Date
    $script:SErr = ''
    $now = $comp[$WatchComp]
    $prev = $script:St.codeStatus
    if ($now -and $prev -and $now -ne $prev) {
        $iname = ($inc | Where-Object { $_.code } | Select-Object -First 1).name
        if ($now -eq 'operational') { Notify $L.backOk ($L.before + (Status-Text $prev)) 'ok' }
        else { Notify ("Claude Code " + (Status-Text $now)) $(if ($iname) { $iname } else { $L.seeStatus }) $(if ($now -eq 'major_outage') { 'bad' } else { 'warn' }) }
    }
    if ($now -and $now -ne $prev) { $script:St.codeStatus = $now; Save-State }
}
function Status-Text([string]$s) { if ($s -and $L.ContainsKey($s)) { $L[$s] } elseif ($s) { $s } else { $L.unknown } }

# ------------------------------------------------------------ text helpers
function Reset-Text($t, [string]$kind) {
    if (-not $t) { return '-' }
    if ($kind -eq 'five') {
        $m = [int][Math]::Ceiling(($t - (Get-Date)).TotalMinutes)
        if ($m -le 0) { return $L.soon }
        if ($m -lt 60) { return ($L.inMin -f $m) }
        return ($L.inHM -f [int][Math]::Floor($m / 60), ($m % 60))
    }
    return $t.ToString('ddd HH:mm', $Cul)
}

# ------------------------------------------------------------ drawing
$g0 = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $Sc = $g0.DpiX / 96.0; $g0.Dispose()
$Px = [System.Drawing.GraphicsUnit]::Pixel
function C($r, $g, $b) { [System.Drawing.Color]::FromArgb($r, $g, $b) }
$ColBg = C 32 32 36; $ColText = C 240 240 244; $ColDim = C 150 150 160; $ColLine = C 58 58 64; $ColTrack = C 62 62 70; $ColInk = C 18 18 20
$ColOk = C 34 197 94; $ColYel = C 250 204 21; $ColOra = C 249 115 22; $ColRed = C 239 68 68; $ColBlue = C 59 130 246; $ColGrey = C 130 130 138
function Pct-Color($p) { if ($null -eq $p) { $ColGrey } elseif ($p -lt 50) { $ColOk } elseif ($p -lt 75) { $ColYel } elseif ($p -lt 90) { $ColOra } else { $ColRed } }
function Status-Color([string]$s) {
    switch ($s) { 'operational' { $ColOk } 'degraded_performance' { $ColYel } 'partial_outage' { $ColOra } 'major_outage' { $ColRed } 'under_maintenance' { $ColBlue } default { $ColGrey } }
}
$FontUi = if ($Lang -eq 'th') { 'Leelawadee UI' } else { 'Segoe UI' }
$fHead  = New-Object System.Drawing.Font($FontUi, [single](12 * $Sc), [System.Drawing.FontStyle]::Bold, $Px)
$fSmall = New-Object System.Drawing.Font($FontUi, [single](11.5 * $Sc), [System.Drawing.FontStyle]::Regular, $Px)
$fLabel = New-Object System.Drawing.Font($FontUi, [single](13 * $Sc), [System.Drawing.FontStyle]::Regular, $Px)
$fBig   = New-Object System.Drawing.Font('Segoe UI', [single](22 * $Sc), [System.Drawing.FontStyle]::Bold, $Px)
$fIncB  = New-Object System.Drawing.Font($FontUi, [single](12 * $Sc), [System.Drawing.FontStyle]::Bold, $Px)

function New-RoundRect([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = [Math]::Min($r * 2, [Math]::Min($w, $h))
    if ($d -lt 1) { $p.AddRectangle((New-Object System.Drawing.RectangleF($x, $y, $w, $h))); return ,$p }
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure(); return ,$p
}

$IconPx = [System.Windows.Forms.SystemInformation]::SmallIconSize.Width
$script:IconHandle = [IntPtr]::Zero; $script:IconKey = ''
function Update-TrayIcon([string]$text, [System.Drawing.Color]$fill, $weekPct, $dotColor) {
    $key = "$text|$($fill.ToArgb())|$weekPct|$(if ($dotColor) { $dotColor.ToArgb() })"
    if ($key -eq $script:IconKey) { return }
    $n = $IconPx
    $bmp = New-Object System.Drawing.Bitmap $n, $n
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear([System.Drawing.Color]::Transparent)
    $path = New-RoundRect 0 0 ($n - 1) ($n - 1) ([single]($n * 0.22))
    $br = New-Object System.Drawing.SolidBrush $fill
    $g.FillPath($br, $path)
    $barH = [single][Math]::Max(2, [Math]::Round($n * 0.16))
    $textH = [single]($n - $barH - 2)
    $sf = [System.Drawing.StringFormat]::GenericTypographic.Clone()
    $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $sf.FormatFlags = $sf.FormatFlags -bor [System.Drawing.StringFormatFlags]::NoWrap -bor [System.Drawing.StringFormatFlags]::NoClip
    $size = [single]($n * 0.62)
    do {
        $f = New-Object System.Drawing.Font('Segoe UI', $size, [System.Drawing.FontStyle]::Bold, $Px)
        $ms = $g.MeasureString($text, $f, 1000, $sf)
        $fits = $ms.Width -le ($n - 2) -and $ms.Height -le ($textH + 2)
        if (-not $fits) { $f.Dispose(); $size -= 0.5 }
    } until ($fits -or $size -lt 6)
    $tb = New-Object System.Drawing.SolidBrush $ColInk
    $g.DrawString($text, $f, $tb, (New-Object System.Drawing.RectangleF(0, [single]1, $n, $textH)), $sf)
    if ($null -ne $weekPct) {
        $bx = [single]2; $bw = [single]($n - 5); $by = [single]($n - $barH - 2)
        $tr = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(90, 0, 0, 0))
        $tp = New-RoundRect $bx $by $bw $barH ($barH / 2); $g.FillPath($tr, $tp); $tp.Dispose(); $tr.Dispose()
        $fw = [single]([Math]::Max(0, [Math]::Min(100, $weekPct)) / 100 * $bw)
        if ($fw -ge 1) { $fp = New-RoundRect $bx $by $fw $barH ($barH / 2); $g.FillPath($tb, $fp); $fp.Dispose() }
    }
    if ($dotColor) {
        $d = [single][Math]::Round($n * 0.42)
        $ring = New-Object System.Drawing.SolidBrush $ColInk
        $g.FillEllipse($ring, [single]($n - $d), [single]0, $d, $d)
        $db = New-Object System.Drawing.SolidBrush $dotColor
        $g.FillEllipse($db, [single]($n - $d + 1.5), [single]1.5, [single]($d - 3), [single]($d - 3))
        $ring.Dispose(); $db.Dispose()
    }
    $g.Dispose(); $br.Dispose(); $tb.Dispose(); $f.Dispose(); $path.Dispose()
    $h = $bmp.GetHicon(); $bmp.Dispose()
    $tray.Icon = [System.Drawing.Icon]::FromHandle($h)
    if ($script:IconHandle -ne [IntPtr]::Zero) { [void][CtNative]::DestroyIcon($script:IconHandle) }
    $script:IconHandle = $h; $script:IconKey = $key
}

function Draw-Right($g, [string]$s, $font, $brush, [single]$right, [single]$y) {
    $sz = $g.MeasureString($s, $font)
    $g.DrawString($s, $font, $brush, [single]($right - $sz.Width), $y)
    return $sz
}

$script:Hits = @()
function Render-Popup {
    $PW = [int](340 * $Sc); $pad = [single](16 * $Sc)
    $bmp = New-Object System.Drawing.Bitmap $PW, ([int](900 * $Sc))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
    $g.Clear($ColBg)
    $txt = New-Object System.Drawing.SolidBrush $ColText
    $dim = New-Object System.Drawing.SolidBrush $ColDim
    $pen = New-Object System.Drawing.Pen $ColLine, ([single](1 * $Sc))
    $trk = New-Object System.Drawing.SolidBrush $ColTrack
    $hits = New-Object System.Collections.ArrayList
    $R = [single]($PW - $pad)

    $y = [single](12 * $Sc)
    $head = if ($Account) { "Claude $DOT $Account" } else { 'Claude' }
    $g.DrawString($head, $fHead, $txt, $pad, $y)
    $busy = $script:Req['quota'] -or $script:Req['status']
    $right = if ($busy) { $L.loading } elseif ($script:QAt) { $L.updated + $script:QAt.ToString('HH:mm') + '   ' + $L.refresh } else { $L.refresh }
    $sz = Draw-Right $g $right $fSmall $dim $R ([single]($y + 1 * $Sc))
    [void]$hits.Add(@{ Y0 = 0; Y1 = [single](36 * $Sc); X0 = [single]($R - $sz.Width); A = 'refresh' })
    $y += [single](30 * $Sc)

    if ($script:QErr) {
        $eb = New-Object System.Drawing.SolidBrush $ColOra
        $g.DrawString($script:QErr, $fSmall, $eb, (New-Object System.Drawing.RectangleF($pad, $y, ($R - $pad), [single](34 * $Sc))))
        $eb.Dispose(); $y += [single](22 * $Sc)
    }

    foreach ($pair in @(@('five', $L.five, $L.reset), @('week', $L.week, $L.reset))) {
        $b = if ($script:Q) { $script:Q[$pair[0]] } else { $null }
        $pc = if ($b) { $b.pct } else { $null }
        $col = Pct-Color $pc
        $cb = New-Object System.Drawing.SolidBrush $col
        $g.DrawString($pair[1], $fLabel, $txt, $pad, $y)
        $sub = if ($b) { $pair[2] + ' ' + (Reset-Text $b.reset $pair[0]) } else { $L.noData }
        $g.DrawString($sub, $fSmall, $dim, $pad, [single]($y + 19 * $Sc))
        $ptxt = if ($null -ne $pc) { '{0:N0}%' -f $pc } else { '-' }
        [void](Draw-Right $g $ptxt $fBig $cb $R ([single]($y + 4 * $Sc)))
        $by = [single]($y + 42 * $Sc); $bh = [single](6 * $Sc); $bw = [single]($R - $pad)
        $tp = New-RoundRect $pad $by $bw $bh ($bh / 2); $g.FillPath($trk, $tp); $tp.Dispose()
        if ($null -ne $pc) {
            $fw = [single]([Math]::Max(0, [Math]::Min(100, $pc)) / 100 * $bw)
            if ($fw -ge 1) { $fp = New-RoundRect $pad $by $fw $bh ($bh / 2); $g.FillPath($cb, $fp); $fp.Dispose() }
        }
        $cb.Dispose()
        $y += [single](58 * $Sc)
    }

    if ($script:Q -and $script:Q.scoped.Count) {
        foreach ($s in $script:Q.scoped) {
            $g.DrawString(($L.weekly -f $s.name), $fSmall, $dim, $pad, $y)
            [void](Draw-Right $g ('{0:N0}%' -f $s.pct) $fSmall $txt $R $y)
            $y += [single](20 * $Sc)
        }
    }

    $y += [single](6 * $Sc)
    $g.DrawLine($pen, $pad, $y, $R, $y)
    $y += [single](10 * $Sc)

    $dotD = [single](8 * $Sc)
    if (-not $script:S) {
        $g.DrawString($(if ($script:SErr) { $script:SErr } else { $L.checking }), $fSmall, $dim, $pad, $y)
        $y += [single](22 * $Sc)
    } else {
        $okNames = @()
        foreach ($id in $Comps.Keys) {
            $st = $script:S.comp[$id]
            if ($id -ne $WatchComp -and $st -eq 'operational') { $okNames += $Comps[$id]; continue }
            $sb = New-Object System.Drawing.SolidBrush (Status-Color $st)
            $g.FillEllipse($sb, $pad, [single]($y + 6 * $Sc), $dotD, $dotD); $sb.Dispose()
            $g.DrawString(("{0} $DOT {1}" -f $Comps[$id], (Status-Text $st)), $fSmall, $txt, [single]($pad + 14 * $Sc), $y)
            $y += [single](22 * $Sc)
            if ($id -eq $WatchComp) {
                foreach ($i in @($script:S.inc | Where-Object { $_.code })) { $y = Draw-Incident $g $i $pad $R $y }
            }
        }
        foreach ($i in @($script:S.inc | Where-Object { -not $_.code })) { $y = Draw-Incident $g $i $pad $R $y }
        if ($okNames.Count) {
            $sb = New-Object System.Drawing.SolidBrush $ColOk
            $g.FillEllipse($sb, $pad, [single]($y + 6 * $Sc), $dotD, $dotD); $sb.Dispose()
            $g.DrawString((($okNames -join " $DOT ") + " $DOT " + $L.ok), $fSmall, $txt, [single]($pad + 14 * $Sc), $y)
            $y += [single](22 * $Sc)
        }
        if ($script:SErr) { $g.DrawString($script:SErr, $fSmall, $dim, $pad, $y); $y += [single](20 * $Sc) }
    }
    $y += [single](8 * $Sc)

    $g.Dispose(); $txt.Dispose(); $dim.Dispose(); $pen.Dispose(); $trk.Dispose()
    $H = [int]$y
    $out = $bmp.Clone((New-Object System.Drawing.Rectangle(0, 0, $PW, $H)), $bmp.PixelFormat)
    $bmp.Dispose()
    $script:Hits = $hits
    $old = $pic.Image; $pic.Image = $out; $pop.ClientSize = $out.Size
    if ($old) { $old.Dispose() }
}

function Draw-Incident($g, $i, [single]$x, [single]$right, [single]$y) {
    $bw = [single]($right - $x); $innerW = [single]($bw - 18 * $Sc)
    $sfw = New-Object System.Drawing.StringFormat
    $nh = $g.MeasureString($i.name, $fIncB, [int]$innerW, $sfw).Height
    $bh = [single]($nh + 28 * $Sc)
    $box = New-RoundRect $x $y $bw $bh ([single](6 * $Sc))
    $fill = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(30, 250, 204, 21))
    $bp = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(90, 250, 204, 21)), ([single](1 * $Sc))
    $g.FillPath($fill, $box); $g.DrawPath($bp, $box)
    $yb = New-Object System.Drawing.SolidBrush $ColYel
    $g.DrawString($i.name, $fIncB, $yb, (New-Object System.Drawing.RectangleF([single]($x + 9 * $Sc), [single]($y + 6 * $Sc), $innerW, $nh)), $sfw)
    $st = Status-Text $i.status
    $when = if ($i.at) { $L.started + $i.at.ToString('d MMM HH:mm', $Cul) + " $DOT " } else { '' }
    $tb = New-Object System.Drawing.SolidBrush $ColText
    $g.DrawString(($when + $st), $fSmall, $tb, [single]($x + 9 * $Sc), [single]($y + 8 * $Sc + $nh))
    $box.Dispose(); $fill.Dispose(); $bp.Dispose(); $yb.Dispose(); $tb.Dispose()
    return [single]($y + $bh + 8 * $Sc)
}

# ------------------------------------------------------------ popup + tray
$pop = New-Object System.Windows.Forms.Form
$pop.FormBorderStyle = 'None'; $pop.TopMost = $true; $pop.ShowInTaskbar = $false
$pop.StartPosition = 'Manual'; $pop.BackColor = $ColBg
$pic = New-Object System.Windows.Forms.PictureBox; $pic.Dock = 'Fill'; $pop.Controls.Add($pic)
$pop.Add_HandleCreated({
    $ex = [CtNative]::GetWindowLong($pop.Handle, -20)
    [void][CtNative]::SetWindowLong($pop.Handle, -20, ($ex -bor 0x80))
    $round = 2; [void][CtNative]::DwmSetWindowAttribute($pop.Handle, 33, [ref]$round, 4)
})
$script:PopHiddenAt = [datetime]::MinValue
$pop.Add_Deactivate({ $pop.Hide(); $script:PopHiddenAt = Get-Date })

function Place-Popup {
    $cur = [System.Windows.Forms.Cursor]::Position
    $scr = [System.Windows.Forms.Screen]::FromPoint($cur); $wa = $scr.WorkingArea; $gap = [int](12 * $Sc)
    $x = [Math]::Max($wa.Left + $gap, [Math]::Min($cur.X - [int]($pop.Width / 2), $wa.Right - $pop.Width - $gap))
    $y = if ($wa.Top -gt $scr.Bounds.Top) { $wa.Top + $gap } else { $wa.Bottom - $pop.Height - $gap }
    $pop.Location = New-Object System.Drawing.Point($x, $y)
}
function Rerender-InPlace { $bottom = $pop.Bottom; Render-Popup; $pop.Top = [Math]::Max(0, $bottom - $pop.Height) }
$pic.Add_MouseClick({
    param($src, $e)
    Safe {
        foreach ($h in $script:Hits) {
            if ($e.Y -lt $h.Y0 -or $e.Y -ge $h.Y1 -or ($h.X0 -and $e.X -lt $h.X0)) { continue }
            if ($h.A -eq 'refresh') { Refresh-Now }
        }
    } 'popup-click'
})

function Refresh-Now {
    $script:NextQuota = Get-Date; $script:NextStatus = Get-Date
    Start-Quota; Start-Status
    if ($pop.Visible) { Rerender-InPlace }
}

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Items.Add($L.mRefresh).Add_Click({ Safe { Refresh-Now } 'menu-refresh' })
$menu.Items.Add($L.mStatus).Add_Click({ Start-Process 'https://status.claude.com' })
$menu.Items.Add($L.mUsage).Add_Click({ Start-Process 'https://claude.ai/settings/usage' })
$menu.Items.Add($L.mLog).Add_Click({ Start-Process explorer.exe $Root })
[void]$menu.Items.Add('-')
$menu.Items.Add($L.mExit).Add_Click({ $timer.Stop(); $tray.Visible = $false; [System.Windows.Forms.Application]::Exit() })

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = [System.Drawing.SystemIcons]::Information
$tray.Text = $AppName     # InitialTooltip; Set-TrayPinned keys on it
$tray.ContextMenuStrip = $menu
$tray.Visible = $true
$tray.Add_MouseClick({
    param($src, $e)
    Safe {
        if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
        if ($pop.Visible) { $pop.Hide(); return }
        if (((Get-Date) - $script:PopHiddenAt).TotalMilliseconds -lt 400) { return }
        Render-Popup; Place-Popup
        $pop.Show(); $pop.Activate(); [void][CtNative]::SetForegroundWindow($pop.Handle)
    } 'tray-click'
})
$tray.Add_BalloonTipClicked({ Start-Process 'https://status.claude.com' })

# Keep the icon on the taskbar instead of the overflow flyout (set "pinTray": false to skip).
$PinTray = [bool](Opt 'pinTray' $true)
function Set-TrayPinned {
    if (-not $PinTray) { return }
    try {
        Get-ChildItem 'HKCU:\Control Panel\NotifyIconSettings' | ForEach-Object {
            $p = Get-ItemProperty -LiteralPath $_.PSPath
            if ($p.InitialTooltip -eq $AppName -and $p.IsPromoted -ne 1) { Set-ItemProperty -LiteralPath $_.PSPath -Name IsPromoted -Value 1 -Type DWord; Log 'PINNED' }
        }
    } catch { Log "PIN-ERR $($_.Exception.Message)" }
}

function Notify([string]$title, [string]$body, [string]$kind) {
    $icon = if ($kind -eq 'bad') { 'Error' } elseif ($kind -eq 'warn') { 'Warning' } else { 'Info' }
    $tray.ShowBalloonTip(10000, $title, $body, $icon)
    Log "NOTIFY $title | $body"
}

function Update-View {
    $five = if ($script:Q) { $script:Q.five } else { $null }
    $week = if ($script:Q) { $script:Q.week } else { $null }
    $code = if ($script:S) { $script:S.comp[$WatchComp] } else { $null }
    $dotCol = if ($code -and $code -ne 'operational') { Status-Color $code } else { $null }
    if ($five) {
        $t = if ($five.pct -ge 100) { '!!' } else { '{0:N0}' -f $five.pct }
        Update-TrayIcon $t (Pct-Color $five.pct) $(if ($week) { $week.pct } else { $null }) $dotCol
    } else {
        Update-TrayIcon '?' $ColGrey $null $dotCol
    }
    $l1 = if ($five) { "Claude 5h {0:N0}% $DOT week {1}" -f $five.pct, $(if ($week) { '{0:N0}%' -f $week.pct } else { '-' }) } else { 'Claude ' + $(if ($script:QErr) { 'quota error' } else { 'loading' }) }
    $l2 = if ($code) { 'Code: ' + (Status-Text $code) } else { '' }
    $tip = (($l1, $l2 | Where-Object { $_ }) -join "`n")
    $tray.Text = $tip.Substring(0, [Math]::Min(63, $tip.Length))
    if ($pop.Visible) { Rerender-InPlace }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$script:Ticks = 0
$timer.Add_Tick({
    Safe {
        $changed = $false
        $r = Poll-Http 'quota';  if ($r) { Finish-Quota $r; $changed = $true }
        $r = Poll-Http 'status'; if ($r) { Finish-Status $r; $changed = $true }
        $now = Get-Date
        if ($now -ge $script:NextQuota)  { $script:NextQuota  = $now.AddMinutes($QuotaMin); Start-Quota }
        if ($now -ge $script:NextStatus) { $script:NextStatus = $now.AddSeconds($StatusSec); Start-Status }
        $script:Ticks++
        if ($changed -or ($pop.Visible -and $script:Ticks % 30 -eq 0)) { Update-View }
        if ($script:Ticks % 600 -eq 20) { Set-TrayPinned }
    } 'tick'
})
Update-TrayIcon '..' $ColGrey $null $null
$timer.Start()
[void][System.Windows.Forms.Application]::Run()
$tray.Visible = $false
