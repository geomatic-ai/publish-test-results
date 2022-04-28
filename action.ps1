#!/usr/bin/env pwsh

## You interface with the Actions/Workflow system by interacting
## with the environment.  The `GitHubActions` module makes this
## easier and more natural by wrapping up access to the Workflow
## environment in PowerShell-friendly constructions and idioms
if (-not (Get-Module -ListAvailable GitHubActions)) {
    ## Make sure the GH Actions module is installed from the Gallery
    Install-Module GitHubActions -Force
}

## Load up some common functionality for interacting
## with the GitHub Actions/Workflow environment
Import-Module GitHubActions

$inputs = @{
    report_file                         = Get-ActionInput report_file -Required
    report_name                         = Get-ActionInput report_name
    report_title                        = Get-ActionInput report_title
    github_token                        = Get-ActionInput github_token -Required
}

function Publish-ToCheckRun {
    param(
        [string]$reportData
    )

    Write-ActionInfo "Publishing Report to GH Workflow"

    $ghToken = $inputs.github_token
    $ctx = Get-ActionContext
    $repo = Get-ActionRepo
    $repoFullName = "$($repo.Owner)/$($repo.Repo)"

    Write-ActionInfo "Resolving REF"
    $ref = $ctx.Sha
    if ($ctx.EventName -eq 'pull_request') {
        Write-ActionInfo "Resolving PR REF"
        $ref = $ctx.Payload.pull_request.head.sha
        if (-not $ref) {
            Write-ActionInfo "Resolving PR REF as AFTER"
            $ref = $ctx.Payload.after
        }
    }

    if (-not $ref) {
        Write-ActionError "Failed to resolve REF"
        exit 1
    }

    Write-ActionInfo "Resolved REF as $ref"
    Write-ActionInfo "Resolve Repo Full Name as $repoFullName"

    Write-ActionInfo "Adding Check Run"
    $conclusion = 'neutral'

    $url = "https://api.github.com/repos/$repoFullName/check-runs"
    $hdr = @{
        Accept = 'application/vnd.github.antiope-preview+json'
        Authorization = "token $ghToken"
    }
    $bdy = @{
        name       = $report_name
        head_sha   = $ref
        status     = 'completed'
        conclusion = $conclusion
        output     = @{
            title   = $report_title
            summary = "This run completed at ``$([datetime]::Now)``"
            text    = $reportData
        }
    }

    Invoke-WebRequest -Headers $hdr $url -Method Post -Body ($bdy | ConvertTo-Json)
}

if (-not $inputs.report_name) {
    $inputs.report_name = "TEST_RESULTS_$([datetime]::Now.ToString('yyyyMMdd_hhmmss'))"
}

if (-not $inputs.report_title) {
    $inputs.report_title = $inputs.report_name
}

if (Test-Path $inputs.report_file) {
    Write-ActionInfo "Found report file at $inputs.report_file"
    $reportData = Get-Content -Path $inputs.report_file -Raw
    if ($reportData) {
        Write-ActionInfo "Report data found"
        Publish-ToCheckRun $reportData
    }
    else {
        Write-ActionError "Failed to read report data"
        exit 1
    }
}
else {
    Write-ActionError "Failed to find report file at $($inputs.report_file)"
    exit 1
}