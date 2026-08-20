# Arknights: Endfield Playtime & Stats Checker

A lightweight, optimized PowerShell script to analyze your Arknights: Endfield local game logs and calculate your total playtime, session history, and activity streaks.

## Why this script?

- **Optimized Performance:** Uses .NET StreamReaders to parse massive log files instantly without hogging your RAM (unlike basic `Get-Content` scripts).
- **Privacy First:** The script runs entirely locally. It doesn't send your data anywhere, doesn't require internet access, and you can audit every line of code yourself.

## How to use

1. Open **PowerShell** (press `Win + X` and select **Terminal** or **PowerShell**).
2. Copy the entire script code and paste it directly into the PowerShell window, then press **Enter**.
3. View your stats in the console.

*(Note: If you're on Linux/Proton, feel free to adjust the `$logPath` variable in the script to point to your specific Wine prefix.)*
