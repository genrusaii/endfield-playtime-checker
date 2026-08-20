param(
    [string]$CustomPath,
    [switch]$ExportJson,
    [switch]$ExportCsv
)

& {
    Write-Host "`n┌─────────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "║          endfield-playtime-checker 1.21         ║" -ForegroundColor White
    Write-Host "└─────────────────────────────────────────────────┘" -ForegroundColor DarkGray
    
    Write-Host "`n[i] Scanning for Arknights: Endfield logs..." -ForegroundColor Gray

    $user = $env:USERNAME
    $searchPaths = [System.Collections.Generic.List[string]]::new()

    if ($CustomPath) {
        $searchPaths.Add($CustomPath)
    }

    $searchPaths.Add("C:\Users\$user\AppData\LocalLow\Gryphline")

    Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        $searchPaths.Add("$($_.Root)Gryphline")
        $searchPaths.Add("$($_.Root)Games\Gryphline")
        $searchPaths.Add("$($_.Root)Program Files\Gryphline")
    }

    $files = @()
    foreach ($path in $searchPaths) {
        if ($path -and (Test-Path $path)) {
            $files += Get-ChildItem -Path $path -Filter "games*.log" -Recurse -ErrorAction SilentlyContinue
        }
    }

    $files = $files | Sort-Object FullName -Unique
    if (-not $files) { 
        Write-Host "[x] Gryphline log files not found. Use -CustomPath 'C:\YourPath' to specify manually." -ForegroundColor Red 
        Write-Host "`nPress any key to exit..." -ForegroundColor Gray
        $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return 
    }

    $sessions = [System.Collections.Generic.List[PSCustomObject]]::new()
    $year = [DateTime]::Now.Year
    
    $totalFiles = $files.Count
    $currentFileIndex = 0

    foreach ($file in $files) {
        $currentFileIndex++
        $percent = [math]::Round(($currentFileIndex / $totalFiles) * 100)
        $filled = [math]::Round($percent / 5)
        $empty = 20 - $filled
        $barProg = ("=" * $filled) + ("-" * $empty)
        
        Write-Host -NoNewline "`r[>] Parsing logs: [$barProg] $percent% ($currentFileIndex/$totalFiles) - $($file.Name)" -ForegroundColor Gray

        try {
            $stream = [System.IO.File]::Open($file.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $reader = [System.IO.StreamReader]::new($stream)
            $start = $null

            while ($null -ne ($line = $reader.ReadLine())) {
                if ($line.Length -lt 12) { continue }
                if ($line -match 'enter main|create game process|OnGameStart') {
                    $raw = $line.Substring(1, 11)
                    $start = try { [DateTime]::new($year, $raw[0..1] -join '', $raw[3..4] -join '', $raw[6..7] -join '', $raw[9..10] -join '', 0) } catch {}
                }
                elseif ($start -and ($line -match 'OnAppAboutToQuit|Child process exits|leave main')) {
                    $raw = $line.Substring(1, 11)
                    $end = try { [DateTime]::new($year, $raw[0..1] -join '', $raw[3..4] -join '', $raw[6..7] -join '', $raw[9..10] -join '', 0) } catch {}
                    if ($end) {
                        if ($end -lt $start) { $end = $end.AddDays(1) }
                        $mins = ($end - $start).TotalMinutes
                        if ($mins -ge 1) { 
                            $sessions.Add([PSCustomObject]@{ Start = $start; End = $end; Duration = ($end - $start); Mins = $mins }) 
                        }
                    }
                    $start = $null
                }
            }
        } catch {} finally { if ($reader) { $reader.Dispose() }; if ($stream) { $stream.Dispose() } }
    }
    Write-Host ""

    if ($sessions.Count -eq 0) { 
        Write-Host "[x] No valid session data found in logs." -ForegroundColor Yellow
        Write-Host "`nPress any key to exit..." -ForegroundColor Gray
        $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return 
    }

    $totalMins = ($sessions | Measure-Object Mins -Sum).Sum
    $totalSpan = [TimeSpan]::FromMinutes($totalMins)
    $uniqueDays = $sessions | Group-Object { $_.Start.ToString('yyyy-MM-dd') } | Sort-Object Name
    $sortedSess = $sessions | Sort-Object Mins

    $streak = $maxStreak = 0; $prev = $null
    foreach ($d in $uniqueDays) {
        $curr = [DateTime]::Parse($d.Name)
        $streak = if ($prev -and $curr -eq $prev.AddDays(1)) { $streak + 1 } else { 1 }
        if ($streak -gt $maxStreak) { $maxStreak = $streak }
        $prev = $curr
    }

    if ($ExportJson) {
        $sessions | ConvertTo-Json | Out-File "endfield_stats.json" -Encoding utf8
        Write-Host "[+] Exported to endfield_stats.json" -ForegroundColor Green
    }
    if ($ExportCsv) {
        $sessions | Export-Csv -Path "endfield_stats.csv" -NoTypeInformation -Encoding utf8
        Write-Host "[+] Exported to endfield_stats.csv" -ForegroundColor Green
    }

    Write-Host "`n────────────────[ OPERATIONAL STATISTICS ]────────────────" -ForegroundColor DarkGray
    Write-Host " > Total Playtime       : " -NoNewline; Write-Host "$([math]::Floor($totalSpan.TotalHours))h $($totalSpan.Minutes)m" -ForegroundColor Green
    Write-Host " > Total Sessions       : $($sessions.Count)" -ForegroundColor Gray
    Write-Host " > Unique Active Days   : $($uniqueDays.Count)" -ForegroundColor Gray
    Write-Host " > Longest Streak       : $maxStreak consecutive days!" -ForegroundColor Yellow
    Write-Host " > Average Session      : " -NoNewline; Write-Host "$([math]::Floor(($totalMins / $sessions.Count) / 60))h $([math]::Round(($totalMins / $sessions.Count) % 60))m" -ForegroundColor Green

    Write-Host "`n─────────────────[ SESSION RECORDS ]─────────────────" -ForegroundColor DarkGray
    Write-Host " > Longest Session      : " -NoNewline; Write-Host "$([math]::Floor($sortedSess[-1].Duration.TotalHours))h $($sortedSess[-1].Duration.Minutes)m" -ForegroundColor Green -NoNewline; Write-Host "  (Date: $($sortedSess[-1].Start.ToString('yyyy-MM-dd')))" -ForegroundColor Gray
    Write-Host " > Shortest Session     : " -NoNewline; Write-Host "$($sortedSess[0].Duration.Minutes)m" -ForegroundColor Green -NoNewline; Write-Host "  (Date: $($sortedSess[0].Start.ToString('yyyy-MM-dd')))" -ForegroundColor Gray

    Write-Host "`n──────────────────[ GAMING RHYTHM ]──────────────────" -ForegroundColor DarkGray
    $nightMins = ($sessions | Where-Object { $_.Start.Hour -ge 22 -or $_.Start.Hour -lt 6 } | Measure-Object Mins -Sum).Sum
    $nightPct = [math]::Round(($nightMins / $totalMins) * 100)
    Write-Host " > Night Gaming (22-06) : $nightPct% of time" -ForegroundColor Gray
    Write-Host " > Daytime Gaming       : $(100 - $nightPct)% of time" -ForegroundColor Gray
    Write-Host " > Quick Checks (<30m)  : $($sessions | Where-Object Mins -lt 30 | Measure-Object | Select-Object -ExpandProperty Count)" -ForegroundColor Gray
    Write-Host " > Standard (30m-3h)    : $($sessions | Where-Object { $_.Mins -ge 30 -and $_.Mins -le 180 } | Measure-Object | Select-Object -ExpandProperty Count)" -ForegroundColor Gray
    Write-Host " > Hardcore Marathons   : $($sessions | Where-Object Mins -gt 180 | Measure-Object | Select-Object -ExpandProperty Count)" -ForegroundColor Gray

    Write-Host "`n────────────────[ LAUNCH DISTRIBUTION ]────────────────" -ForegroundColor DarkGray
    Write-Host " > Frequency of game launches by time of day (00:00 - 23:00)" -ForegroundColor Gray
    $hourly = 0..23 | Select-Object @{N='Hour';E={$_}}, @{N='Count';E={ $h=$_; ($sessions | Where-Object { $_.Start.Hour -eq $h }).Count }}
    $maxCount = ($hourly | Measure-Object Count -Max).Maximum

    foreach ($h in $hourly) {
        $barLen = if ($maxCount -gt 0) { [math]::Round(($h.Count / $maxCount) * 20) } else { 0 }
        $bar = "■" * $barLen
        $hourStr = "{0:D2}:00" -f $h.Hour
        $countStr = "{0,2}" -f $h.Count
        Write-Host " $hourStr │ " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($bar.PadRight(20))" -NoNewline -ForegroundColor Cyan
        Write-Host " │ " -NoNewline -ForegroundColor DarkGray
        Write-Host "$countStr" -ForegroundColor DarkGray
    }

    Write-Host "`n──────────────[ TIME PLAYED BY DAY OF WEEK ]──────────────" -ForegroundColor DarkGray
    'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday' | ForEach-Object {
        $day = $_
        $dMins = ($sessions | Where-Object { $_.Start.DayOfWeek -eq $day } | Measure-Object Mins -Sum).Sum
        if ($dMins) { 
            $span = [TimeSpan]::FromMinutes($dMins)
            Write-Host " > $($day.PadRight(10)) : " -NoNewline -ForegroundColor Gray
            Write-Host "$([math]::Floor($span.TotalHours))h $($span.Minutes)m" -ForegroundColor Green
        }
    }

    Write-Host "`n────────────────[ MONTHLY BREAKDOWN ]────────────────" -ForegroundColor DarkGray
    $sessions | Group-Object { $_.Start.ToString('yyyy-MM (MMMM)') } | Sort-Object Name | ForEach-Object {
        $mMins = ($_.Group | Measure-Object Mins -Sum).Sum
        $span = [TimeSpan]::FromMinutes($mMins)
        Write-Host " > $($_.Name.PadRight(18)) : " -NoNewline -ForegroundColor Gray
        Write-Host "$([math]::Floor($span.TotalHours))h $($span.Minutes)m" -ForegroundColor Green
    }
    Write-Host "───────────────────────────────────────────────────────" -ForegroundColor DarkGray

    Write-Host "`nPress any key to exit..." -ForegroundColor Gray
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
