# Gera build/KelwinSouls.exe (Windows Desktop, release) a partir de game/.
#
# Pré-requisitos:
#   1. Godot 4.7.2 (o caminho pode ser passado em -Godot ou pela variável GODOT).
#   2. Export templates 4.7.2 instalados: Editor > Gerenciar Modelos de Exportação
#      (ou o arquivo .tpz baixado do site do Godot, em %APPDATA%\Godot\export_templates\4.7.2.stable).
#
# Uso:  powershell -ExecutionPolicy Bypass -File tools\build_exe.ps1 -Godot "C:\caminho\Godot_v4.7.2-stable_win64_console.exe"

param(
	[string]$Godot = $env:GODOT
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$proj = Join-Path $root "game"
$out = Join-Path $root "build"

if (-not $Godot -or -not (Test-Path $Godot)) {
	Write-Error "Informe o executável do Godot 4.7.2 com -Godot ou na variável GODOT."
}

New-Item -ItemType Directory -Force -Path $out | Out-Null

# 1) importa os recursos (gera o cache .godot/) e 2) exporta a versão de release
& $Godot --headless --path $proj --import
if ($LASTEXITCODE -ne 0) { throw "Falha na importação (código $LASTEXITCODE)." }

& $Godot --headless --path $proj --export-release "Windows Desktop" (Join-Path $out "KelwinSouls.exe")
if ($LASTEXITCODE -ne 0) { throw "Falha na exportação (código $LASTEXITCODE). Verifique se os export templates 4.7.2 estão instalados." }

Write-Host "Pronto: $(Join-Path $out 'KelwinSouls.exe')"
