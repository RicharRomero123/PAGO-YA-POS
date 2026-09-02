<#
  publica.ps1 — Publica el CLIENTE PagoYa en Release y lo OFUSCA.

  Pipeline:
    1. Limpia artifacts/
    2. dotnet publish del Desktop en Release, self-contained win-x64 (sin .pdb, ver .csproj)
    3. Obfuscar cifra strings + renombra miembros privados de los PagoYa.*.dll
    4. Copia los ensamblados ofuscados de vuelta sobre la carpeta de publicación

  Resultado: artifacts\publish  = carpeta lista para empaquetar/instalar (ofuscada).

  Requisitos:
    - .NET SDK (con roll-forward por global.json; en esta máquina el runtime es preview,
      por eso se fija DOTNET_ROLL_FORWARD=LatestMajor).
    - Obfuscar:  dotnet tool install -g Obfuscar.GlobalTool

  Uso:  pwsh build\publica.ps1   (ejecutar desde la raíz del repo)
#>

$ErrorActionPreference = 'Stop'
$env:DOTNET_ROLL_FORWARD = 'LatestMajor'   # runtime preview -> permite ejecutar net8.0

$repo     = Split-Path -Parent $PSScriptRoot
$publish  = Join-Path $repo 'artifacts\publish'
$obf      = Join-Path $repo 'artifacts\publish-obfuscated'
$desktop  = Join-Path $repo 'src\PagoYa.Desktop\PagoYa.Desktop.csproj'

Write-Host '==> Limpiando artifacts/' -ForegroundColor Cyan
if (Test-Path (Join-Path $repo 'artifacts')) { Remove-Item (Join-Path $repo 'artifacts') -Recurse -Force }

Write-Host '==> Publicando PagoYa.Desktop (Release, win-x64, self-contained)' -ForegroundColor Cyan
dotnet publish $desktop -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=false -p:DebugType=none -p:DebugSymbols=false `
    -o $publish
if ($LASTEXITCODE -ne 0) { throw 'dotnet publish falló' }

# ¿Está instalado Obfuscar?
$obfuscarOk = $null -ne (Get-Command obfuscar -ErrorAction SilentlyContinue) `
           -or $null -ne (Get-Command obfuscar.console -ErrorAction SilentlyContinue)

if (-not $obfuscarOk) {
    Write-Warning 'Obfuscar no está instalado. Ejecuta:  dotnet tool install -g Obfuscar.GlobalTool'
    Write-Warning 'Se publicó SIN ofuscar. Los binarios están en artifacts\publish (ya sin .pdb).'
    exit 0
}

Write-Host '==> Ofuscando (Obfuscar): cifrado de strings + renombrado privado' -ForegroundColor Cyan
$obfuscarCmd = (Get-Command obfuscar -ErrorAction SilentlyContinue) ?? (Get-Command obfuscar.console)
& $obfuscarCmd.Source (Join-Path $repo 'build\Obfuscar.xml')
if ($LASTEXITCODE -ne 0) { throw 'Obfuscar falló' }

Write-Host '==> Copiando ensamblados ofuscados sobre la publicación' -ForegroundColor Cyan
Get-ChildItem (Join-Path $obf 'PagoYa.*.dll') | ForEach-Object {
    Copy-Item $_.FullName -Destination $publish -Force
    Write-Host ("    reemplazado: " + $_.Name)
}

Write-Host ''
Write-Host '✔ Listo. Cliente ofuscado en: artifacts\publish' -ForegroundColor Green
Write-Host '  (empaqueta esa carpeta con tu instalador — Inno Setup / MSIX)' -ForegroundColor Green
