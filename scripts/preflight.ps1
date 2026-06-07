# scripts/preflight.ps1
#
# Valida que o projeto atual esta pronto pra blindar.
# Exit 0 se todos checks passaram, exit 1 caso contrario.
#
# Uso (na pasta do projeto-alvo):
#   & "$env:USERPROFILE\.claude\skills\blindar\scripts\preflight.ps1"
#
# Ou linkando no PATH:
#   blindar-preflight

[CmdletBinding()]
param(
    [switch]$Quiet,
    [switch]$Fix    # tenta corrigir checks que da pra automatizar
)

$ErrorActionPreference = 'Continue'
$results = @()

function Add-Check {
    param(
        [string]$Name,
        [bool]$Ok,
        [string]$Fix,
        [string]$Detail
    )
    $script:results += [PSCustomObject]@{
        name = $Name; ok = $Ok; fix = $Fix; detail = $Detail
    }
}

# 1. Repo Git?
$isGit = Test-Path .git
Add-Check -Name "Pasta atual e repo Git" -Ok $isGit `
    -Fix "Rode: git init"

# 2. Branch atual nao vazia?
if ($isGit) {
    $branch = git branch --show-current 2>$null
    $hasBranch = -not [string]::IsNullOrWhiteSpace($branch)
    Add-Check -Name "Em branch nomeada" -Ok $hasBranch `
        -Fix "Checkout em branch: git checkout -b feature/blindar" `
        -Detail "atual: $branch"
}

# 3. Working tree limpo?
if ($isGit) {
    $status = git status --porcelain 2>$null
    $clean = [string]::IsNullOrWhiteSpace($status)
    Add-Check -Name "Working tree limpo" -Ok $clean `
        -Fix "Commit ou stash mudancas: git status / git stash"
}

# 4. CI configurada?
$hasCI = (Test-Path .github/workflows) -or `
         (Test-Path .gitlab-ci.yml) -or `
         (Test-Path Jenkinsfile) -or `
         (Test-Path .circleci/config.yml) -or `
         (Test-Path .travis.yml) -or `
         (Test-Path azure-pipelines.yml)
Add-Check -Name "CI configurada" -Ok $hasCI `
    -Fix "Adicione .github/workflows/ci.yml minima rodando seus testes"

# 5. Stack detectavel?
$stackFiles = @(
    @{ file = "package.json"; stack = "Node" },
    @{ file = "requirements.txt"; stack = "Python (pip)" },
    @{ file = "pyproject.toml"; stack = "Python (modern)" },
    @{ file = "Cargo.toml"; stack = "Rust" },
    @{ file = "go.mod"; stack = "Go" },
    @{ file = "pom.xml"; stack = "Java (Maven)" },
    @{ file = "build.gradle"; stack = "JVM (Gradle)" },
    @{ file = "Gemfile"; stack = "Ruby" },
    @{ file = "composer.json"; stack = "PHP" }
)
$detected = $stackFiles | Where-Object { Test-Path $_.file }
$hasStack = $detected.Count -gt 0
$stackName = if ($detected) { ($detected | ForEach-Object { $_.stack }) -join ", " } else { "nenhuma" }
Add-Check -Name "Stack detectavel" -Ok $hasStack `
    -Fix "Adicione package.json / requirements.txt / etc." `
    -Detail "detectada: $stackName"

# 6. gh CLI instalado e autenticado?
$ghExists = $null -ne (Get-Command gh -ErrorAction SilentlyContinue)
if ($ghExists) {
    $null = gh auth status 2>&1
    $ghAuth = $LASTEXITCODE -eq 0
    Add-Check -Name "gh CLI autenticado" -Ok $ghAuth `
        -Fix "Rode: gh auth login"
} else {
    Add-Check -Name "gh CLI instalado" -Ok $false `
        -Fix "Instale: winget install GitHub.cli (Windows) ou ver cli.github.com"
}

# 7. .blindar dir presente?
$hasBlindar = Test-Path .blindar
if ($Fix -and -not $hasBlindar) {
    New-Item -ItemType Directory -Path .blindar -Force | Out-Null
    $hasBlindar = $true
}
Add-Check -Name ".blindar dir presente" -Ok $hasBlindar `
    -Fix "Sera criado automaticamente na 1a invocacao (ou rode com -Fix)"

# 8. accept-risk.md migrado pra .blindar/?
if (Test-Path "accept-risk.md" -PathType Leaf) {
    $migrated = Test-Path ".blindar/accept-risk.md"
    if ($Fix -and -not $migrated -and (Test-Path .blindar)) {
        Move-Item "accept-risk.md" ".blindar/accept-risk.md"
        $migrated = $true
    }
    Add-Check -Name "accept-risk.md em .blindar/ (nao raiz)" -Ok $migrated `
        -Fix "Mova: Move-Item accept-risk.md .blindar/accept-risk.md (ou rode com -Fix)"
}

# Imprime
Write-Host ""
Write-Host "blindar preflight" -ForegroundColor Cyan
Write-Host "================="
foreach ($r in $results) {
    $sym = if ($r.ok) { "OK " } else { "!! " }
    $color = if ($r.ok) { "Green" } else { "Yellow" }
    Write-Host ("  {0} {1}" -f $sym, $r.name) -ForegroundColor $color
    if ($r.detail) {
        Write-Host ("      " + $r.detail) -ForegroundColor DarkGray
    }
    if (-not $r.ok -and $r.fix) {
        Write-Host ("      fix: " + $r.fix) -ForegroundColor DarkGray
    }
}

$failed = ($results | Where-Object { -not $_.ok }).Count
Write-Host ""

if ($failed -eq 0) {
    Write-Host "OK - todos os checks passaram." -ForegroundColor Green
    Write-Host "Proximo passo: invocar 'blindar' no Claude Code."
    Write-Host "  Ou em outras AIs: cole AI-ENTRYPOINT.md + SKILL.md no chat."
    exit 0
} else {
    Write-Host "$failed check(s) falharam. Resolva antes de invocar blindar." -ForegroundColor Yellow
    if (-not $Fix) {
        Write-Host "Dica: rode com -Fix pra corrigir o que da pra automatizar."
    }
    exit 1
}
