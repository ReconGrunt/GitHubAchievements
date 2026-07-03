<#
  Opens, then squash-merges, a batch of trivial pull requests against this repo's
  main branch. Each merged commit carries a Co-authored-by trailer so the same
  run counts toward both the Pull Shark and Pair Extraordinaire achievements.

  Requires: gh CLI on PATH or at $GhPath, authenticated with `repo` scope,
  run from inside a clone of this repo with `main` checked out.
#>
param(
    [int]$Count = 128,
    [int]$StartAt = 1,
    [string]$GhPath = "C:\Program Files\GitHub CLI\gh.exe",
    [string]$CoAuthorTrailer = "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
)

$ErrorActionPreference = "Stop"
$gh = if (Get-Command $GhPath -ErrorAction SilentlyContinue) { $GhPath } else { "gh" }

$success = 0
$failures = 0
$consecutiveFailures = 0

for ($i = $StartAt; $i -le $Count; $i++) {
    try {
        git checkout -q main
        git pull -q --ff-only origin main

        $branch = "farm/$i"
        git checkout -q -b $branch

        New-Item -ItemType Directory -Path progress -Force | Out-Null
        Set-Content -Path "progress/run-$i.txt" -Value "run $i"
        git add "progress/run-$i.txt"
        git commit -q -m "chore: progress entry $i" -m $CoAuthorTrailer

        git push -q -u origin $branch
        if ($LASTEXITCODE -ne 0) { throw "git push failed with exit code $LASTEXITCODE" }

        $prUrl = & $gh pr create --title "chore: progress entry $i" --body $CoAuthorTrailer --head $branch --base main
        if ($LASTEXITCODE -ne 0) { throw "gh pr create failed with exit code $LASTEXITCODE" }
        $prNumber = ($prUrl -split "/")[-1]

        & $gh pr merge $prNumber --squash --delete-branch --body $CoAuthorTrailer
        if ($LASTEXITCODE -ne 0) { throw "gh pr merge failed with exit code $LASTEXITCODE" }

        git checkout -q main
        git branch -D $branch 2>$null | Out-Null

        $success++
        $consecutiveFailures = 0
    }
    catch {
        $failures++
        $consecutiveFailures++
        Write-Output "Iteration $i failed: $($_.Exception.Message)"
        git checkout -q main -f 2>$null
        git fetch -q origin main 2>$null
        git reset -q --hard origin/main 2>$null
        # Back off harder on likely rate-limit errors so the run can outlast a reset window.
        $backoff = if ($_.Exception.Message -match "rate limit|secondary rate|abuse") { 90 } else { 3 }
        Start-Sleep -Seconds $backoff
        if ($consecutiveFailures -ge 25) {
            Write-Output "Aborting after 25 consecutive failures."
            break
        }
    }

    Start-Sleep -Milliseconds 300

    if ($i % 10 -eq 0) {
        Write-Output "Progress: $i / $Count (success=$success, failures=$failures)"
    }
}

Write-Output "Done. success=$success failures=$failures"
