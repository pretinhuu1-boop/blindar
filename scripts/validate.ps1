# scripts/validate.ps1
#
# Valida um arquivo JSON contra um schema do blindar.
# Wrapper minimo (sem deps) — checa estrutura basica.
# Pra validacao completa, instale ajv-cli ou jsonschema.
#
# Uso:
#   .\validate.ps1 -Schema inventory -File output.json
#   .\validate.ps1 -Schema state -File .blindar/state.json
#
# Schemas disponiveis (em schemas/):
#   inventory, threat, arch, findings, verdict, state, config

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Schema,
    [Parameter(Mandatory)][string]$File
)

$ErrorActionPreference = 'Stop'

$SkillRoot = Split-Path -Parent $PSScriptRoot
$SchemaFile = Join-Path $SkillRoot "schemas\$Schema.schema.json"

if (-not (Test-Path $SchemaFile)) {
    Write-Host "Schema nao encontrado: $SchemaFile" -ForegroundColor Red
    Write-Host "Disponiveis:"
    Get-ChildItem "$SkillRoot\schemas\*.schema.json" | ForEach-Object {
        Write-Host "  - $($_.BaseName -replace '\.schema$','')"
    }
    exit 1
}

if (-not (Test-Path $File)) {
    Write-Host "Arquivo nao encontrado: $File" -ForegroundColor Red
    exit 1
}

# Parse basico (json valido?)
try {
    $data = Get-Content $File -Raw | ConvertFrom-Json -ErrorAction Stop
    Write-Host "[OK] JSON parsea sem erro" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] JSON invalido: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Carrega schema
try {
    $schema = Get-Content $SchemaFile -Raw | ConvertFrom-Json -ErrorAction Stop
    Write-Host "[OK] Schema $Schema carregado" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Schema invalido: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Check required top-level
$missing = @()
if ($schema.required) {
    foreach ($req in $schema.required) {
        if ($null -eq $data.$req) {
            $missing += $req
        }
    }
}

if ($missing.Count -gt 0) {
    Write-Host "[FAIL] Campos required ausentes:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "       - $_" }
    exit 1
}

Write-Host "[OK] Todos os campos required presentes" -ForegroundColor Green

Write-Host ""
Write-Host "Validacao basica OK. Para validacao completa de tipos/enums:" -ForegroundColor Cyan
Write-Host "  npm i -g ajv-cli ajv-formats"
Write-Host "  ajv validate -s $SchemaFile -d $File"
exit 0
