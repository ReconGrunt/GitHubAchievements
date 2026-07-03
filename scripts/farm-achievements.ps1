<#
  Opens, then squash-merges, a batch of trivial pull requests against this repo's
  main branch. Each merged commit carries a Co-authored-by trailer so the same
  run counts toward both the Pull Shark and Pair Extraordinaire achievements.

  Requires: gh CLI on PATH or at $GhPath, authenticated with `repo` scope,
  run from inside a clone of this repo with `main` checked out.
#>
param(
    [int]$Count = 128,
    [string]$GhPath = "C:\Program Files\GitHub CLI\gh.exe",
    [string]$CoAuthorTrailer = "Co-authored-by: Claude Sonnet 5 <noreply@anthropic.com>"
)

$ErrorActionPreference = "Stop"
$gh = if (Get-Command $GhPath -ErrorAction SilentlyContinue) { $GhPath } else { "gh" }

$success = 0
$failures = 0
$consecutiveFailures = 0

for ($i = 1; $i -le $Count; $i++) {
    try {
        git checkout -q main
        git pull -q --ff-only origin main

        $branch = "farm/$i"
        git checkout -q -b $branch

        Add-Content -Path progress.log -Value "run $i"
        git add progress.log
        git commit -q -m "chore: progress entry $i" -m $CoAuthorTrailer

        git push -q -u origin $branch

        $prUrl = & $gh pr create --title "chore: progress entry $i" --body $CoAuthorTrailer --head $branch --base main
        $prNumber = ($prUrl -split "/")[-1]

        & $gh pr merge $prNumber --squash --delete-branch --body $CoAuthorTrailer --yes | Out-Null

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
        if ($consecutiveFailures -ge 5) {
            Write-Output "Aborting after 5 consecutive failures."
            break
        }
    }

    if ($i % 10 -eq 0) {
        Write-Output "Progress: $i / $Count (success=$success, failures=$failures)"
    }
}

Write-Output "Done. success=$success failures=$failures"
