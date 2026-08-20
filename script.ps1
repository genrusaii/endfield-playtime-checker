& {
    $user = $env:USERNAME
    $defaultPath = "C:\Users\$user\AppData\LocalLow\Gryphline"
    $files = if (Test-Path $defaultPath) { Get-ChildItem $defaultPath -Filter "games*.log" -Recurse -ErrorAction SilentlyContinue }
    if (-not $files) {
        $files = Get-PSDrive -PSProvider FileSystem | ForEach-Object { Get-ChildItem "$($_.Root)" -Filter "games*.log" -Recurse -ErrorAction SilentlyContinue }
    }
    $files = $files | Sort-Object LastWriteTime -Unique
    if (-not $files) { Write-Host "Gryphline log files not found." -ForegroundColor Red; return }

    $sessions = [System.Collections.Generic.List[PSCustomObject]]::new()
    $year = [DateTime]::Now.Year

    foreach ($file in $files) {
        try {
            $stream = [System.IO.File]::Open($file.FullName, 'Open', 'Read', 'ReadWrite')
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
                        if ($mins -ge 1) { $sessions.Add([PSCustomObject]@{ Start = $start; End = $end; Duration = ($end - $start); Mins = $mins }) }
                    }
                    $start = $null
                }
            }
        } catch {} finally { if ($reader) { $reader.Dispose() }; if ($stream) { $stream.Dispose() } }
    }

    if ($sessions.Count -eq 0) { Write-Host "No valid session data found in logs." -ForegroundColor Yellow; return }

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

    Write-Host "`n=-- ARKNIGHTS: ENDFIELD MAXIMUM ANALYTICS --=" -ForegroundColor Cyan
    Write-Host "> Total Playtime:        $([math]::Floor($totalSpan.TotalHours))h $($totalSpan.Minutes)m" -ForegroundColor Green
    Write-Host "> Total Sessions:        $($sessions.Count)"
    Write-Host "> Unique Active Days:    $($uniqueDays.Count)"
    Write-Host "> Longest Streak:        $maxStreak consecutive days!" -ForegroundColor Yellow
    Write-Host "> Average Session:       $([math]::Floor(($totalMins / $sessions.Count) / 60))h $([math]::Round(($totalMins / $sessions.Count) % 60))m"

    Write-Host "`n=-- Session Records --=" -ForegroundColor Yellow
    Write-Host " > Longest Session:      $([math]::Floor($sortedSess[-1].Duration.TotalHours))h $($sortedSess[-1].Duration.Minutes)m  (Date: $($sortedSess[-1].Start.ToString('yyyy-MM-dd')))"
    Write-Host " > Shortest Session:     $($sortedSess[0].Duration.Minutes)m  (Date: $($sortedSess[0].Start.ToString('yyyy-MM-dd')))"

    Write-Host "`n=-- Gaming Rhythm & Breakdown --=" -ForegroundColor Yellow
    $nightMins = ($sessions | Where-Object { $_.Start.Hour -ge 22 -or $_.Start.Hour -lt 6 } | Measure-Object Mins -Sum).Sum
    $nightPct = [math]::Round(($nightMins / $totalMins) * 100)
    Write-Host " > Night Gaming (22:00-06:00): $nightPct% of time"
    Write-Host " > Daytime Gaming:              $(100 - $nightPct)% of time"
    Write-Host " > Quick Checks (<30m):         $($sessions | Where-Object Mins -lt 30 | Measure-Object | Select-Object -ExpandProperty Count)"
    Write-Host " > Standard Sessions (30m-3h): $($sessions | Where-Object { $_.Mins -ge 30 -and $_.Mins -le 180 } | Measure-Object | Select-Object -ExpandProperty Count)"
    Write-Host " > Hardcore Marathons (>3h):   $($sessions | Where-Object Mins -gt 180 | Measure-Object | Select-Object -ExpandProperty Count)"

    Write-Host "`n=-- Launch Distribution by Hour (00:00 - 23:00) --=" -ForegroundColor Yellow
    $hourly = 0..23 | Select-Object @{N='Hour';E={$_}}, @{N='Count';E={ $h=$_; ($sessions | Where-Object { $_.Start.Hour -eq $h }).Count }}
    $maxCount = ($hourly | Measure-Object Count -Max).Maximum

    foreach ($h in $hourly) {
        $barLen = if ($maxCount -gt 0) { [math]::Round(($h.Count / $maxCount) * 20) } else { 0 }
        $bar = "█" * $barLen
        $hourStr = "{0:D2}:00" -f $h.Hour
        Write-Host " $hourStr | $($bar.PadRight(20)) ($($h.Count))" -ForegroundColor DarkCyan
    }

    Write-Host "`n=-- Time Played by Day of Week --=" -ForegroundColor Yellow
    'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday' | ForEach-Object {
        $day = $_
        $dMins = ($sessions | Where-Object { $_.Start.DayOfWeek -eq $day } | Measure-Object Mins -Sum).Sum
        if ($dMins) { $span = [TimeSpan]::FromMinutes($dMins); Write-Host " > $($day.PadRight(10)) : $([math]::Floor($span.TotalHours))h $($span.Minutes)m" }
    }

    Write-Host "`n=-- Monthly Breakdown --=" -ForegroundColor Yellow
    $sessions | Group-Object { $_.Start.ToString('yyyy-MM (MMMM)') } | Sort-Object Name | ForEach-Object {
        $mMins = ($_.Group | Measure-Object Mins -Sum).Sum
        $span = [TimeSpan]::FromMinutes($mMins)
        Write-Host " > $($_.Name) : $([math]::Floor($span.TotalHours))h $($span.Minutes)m"
    }
    Write-Host "=--------------------------------------------------=" -ForegroundColor Cyan
}
