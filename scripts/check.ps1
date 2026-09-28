[CmdletBinding()]
param(
    [ValidateSet("all", "frontend", "backend")]
    [string]$Target = "all"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    Write-Host "==> $Label"
    Push-Location -LiteralPath $WorkingDirectory
    try {
        & $Command @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "$Label failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

function Get-FrontendPackageManager {
    param([string]$FrontendDirectory)

    $candidates = @(
        @{ Lock = "pnpm-lock.yaml"; Command = "pnpm"; RunPrefix = @("run") },
        @{ Lock = "package-lock.json"; Command = "npm"; RunPrefix = @("run") },
        @{ Lock = "yarn.lock"; Command = "yarn"; RunPrefix = @("run") }
    )

    foreach ($candidate in $candidates) {
        $localLock = Join-Path $FrontendDirectory $candidate.Lock
        $rootLock = Join-Path $repositoryRoot $candidate.Lock
        if ((Test-Path -LiteralPath $localLock) -or (Test-Path -LiteralPath $rootLock)) {
            return $candidate
        }
    }

    throw "No supported frontend lockfile was found. Commit pnpm-lock.yaml, package-lock.json, or yarn.lock."
}

function Invoke-FrontendChecks {
    $frontendDirectory = Join-Path $repositoryRoot "apps/web"
    if (-not (Test-Path -LiteralPath $frontendDirectory -PathType Container)) {
        Write-Host "==> Frontend not scaffolded; skipping frontend checks."
        return
    }

    $packageJson = Join-Path $frontendDirectory "package.json"
    if (-not (Test-Path -LiteralPath $packageJson -PathType Leaf)) {
        throw "apps/web exists but package.json is missing."
    }

    $packageManager = Get-FrontendPackageManager -FrontendDirectory $frontendDirectory
    foreach ($scriptName in @("lint", "typecheck")) {
        $arguments = @($packageManager.RunPrefix) + @($scriptName)
        Invoke-CheckedCommand `
            -Command $packageManager.Command `
            -Arguments $arguments `
            -WorkingDirectory $frontendDirectory `
            -Label "Frontend $scriptName"
    }
}

function Get-BackendRunner {
    param([string]$BackendDirectory)

    if (
        (Test-Path -LiteralPath (Join-Path $BackendDirectory "uv.lock")) -or
        (Test-Path -LiteralPath (Join-Path $repositoryRoot "uv.lock"))
    ) {
        return @{ Command = "uv"; Prefix = @("run") }
    }

    if (
        (Test-Path -LiteralPath (Join-Path $BackendDirectory "poetry.lock")) -or
        (Test-Path -LiteralPath (Join-Path $repositoryRoot "poetry.lock"))
    ) {
        return @{ Command = "poetry"; Prefix = @("run") }
    }

    return @{ Command = "python"; Prefix = @("-m") }
}

function Invoke-BackendModule {
    param(
        [hashtable]$Runner,
        [string]$Module,
        [string[]]$ModuleArguments,
        [string]$WorkingDirectory,
        [string]$Label
    )

    $arguments = @($Runner.Prefix) + @($Module) + $ModuleArguments
    Invoke-CheckedCommand `
        -Command $Runner.Command `
        -Arguments $arguments `
        -WorkingDirectory $WorkingDirectory `
        -Label $Label
}

function Invoke-BackendChecks {
    $backendDirectory = Join-Path $repositoryRoot "apps/api"
    if (-not (Test-Path -LiteralPath $backendDirectory -PathType Container)) {
        Write-Host "==> Backend not scaffolded; skipping backend checks."
        return
    }

    $pyproject = Join-Path $backendDirectory "pyproject.toml"
    if (-not (Test-Path -LiteralPath $pyproject -PathType Leaf)) {
        throw "apps/api exists but pyproject.toml is missing."
    }

    $runner = Get-BackendRunner -BackendDirectory $backendDirectory
    Invoke-BackendModule -Runner $runner -Module "ruff" -ModuleArguments @("check", ".") -WorkingDirectory $backendDirectory -Label "Backend Ruff lint"
    Invoke-BackendModule -Runner $runner -Module "ruff" -ModuleArguments @("format", "--check", ".") -WorkingDirectory $backendDirectory -Label "Backend Ruff format check"
    Invoke-BackendModule -Runner $runner -Module "mypy" -ModuleArguments @("app", "tests") -WorkingDirectory $backendDirectory -Label "Backend mypy"
    Invoke-BackendModule -Runner $runner -Module "pytest" -ModuleArguments @() -WorkingDirectory $backendDirectory -Label "Backend pytest"
}

if ($Target -in @("all", "frontend")) {
    Invoke-FrontendChecks
}

if ($Target -in @("all", "backend")) {
    Invoke-BackendChecks
}

Write-Host "==> Requested quality checks completed successfully."
