# =============================================================================
#  PagoYa Movil - copia de iconos a assets/
#
#  Fuente primaria: iconos-app-mobil/ (raiz del repo) - 46 PNG del set movil.
#  Huecos (candado, impresora, nube, sincronizar, inventario, proveedores,
#  facturacion): se toman de src/PagoYa.Desktop/Assets/Iconos y de Iconos-POS.
#
#  Los nombres destino son ASCII sin espacios ni tildes: los nombres con acento
#  o parentesis dan problemas en Gradle y en el bundle de assets de Flutter.
#
#  Uso, desde la RAIZ del repo:
#      .\mobile\copiar-iconos.ps1
# =============================================================================

$ErrorActionPreference = 'Stop'

# Resuelve la raiz del repo a partir de la ubicacion del script (mobile/..).
$raiz = Split-Path -Parent $PSScriptRoot
$dst  = Join-Path $raiz 'mobile\pagoya_movil\assets\iconos'

New-Item -ItemType Directory -Force -Path $dst | Out-Null

$mapa = [ordered]@{
    # --- Navegacion y acciones generales ---
    'iconos-app-mobil\icons8-página-principal-96.png'                   = 'ico-inicio.png'
    'iconos-app-mobil\icons8-atrás-96.png'                              = 'ico-atras.png'
    'iconos-app-mobil\icons8-forward-96.png'                            = 'ico-adelante.png'
    'iconos-app-mobil\icons8-search-96.png'                             = 'ico-buscar.png'
    'iconos-app-mobil\icons8-slider-96.png'                             = 'ico-filtros.png'
    'iconos-app-mobil\icons8-ajustes-96.png'                            = 'ico-configuracion.png'
    'iconos-app-mobil\icons8-apoyo-96.png'                              = 'ico-soporte.png'

    # --- Cobro y medios de pago ---
    'iconos-app-mobil\icons8-calculator-96.png'                         = 'ico-cobrar.png'
    'iconos-app-mobil\icons8-banknotes-96.png'                          = 'ico-caja.png'
    'iconos-app-mobil\icons8-dinero-96.png'                             = 'ico-efectivo.png'
    'iconos-app-mobil\icons8-tarjeta-de-fidelidad-96.png'               = 'ico-tarjeta.png'

    # --- Escaneo y camara ---
    'iconos-app-mobil\icons8-código-de-barras-96.png'                   = 'ico-codigo-barras.png'
    'iconos-app-mobil\icons8-código-qr-96.png'                          = 'ico-codigo-qr.png'
    'iconos-app-mobil\icons8-slr-camera-96.png'                         = 'ico-escaner.png'

    # --- Reportes y negocio ---
    'iconos-app-mobil\icons8-carta-de-área-96.png'                      = 'ico-reportes.png'
    'iconos-app-mobil\icons8-en-alza-96.png'                            = 'ico-tendencia.png'
    'iconos-app-mobil\icons8-company-96.png'                            = 'ico-multisede.png'
    'iconos-app-mobil\icons8-pin-96.png'                                = 'ico-sede.png'

    # --- Usuarios ---
    'iconos-app-mobil\icons8-usuario-96.png'                            = 'ico-usuario.png'
    'iconos-app-mobil\icons8-cuenta-96.png'                             = 'ico-cuenta.png'
    'iconos-app-mobil\icons8-grupo-de-usuarios-hombre-hombre-96.png'    = 'ico-usuarios.png'

    # --- CRUD ---
    'iconos-app-mobil\icons8-plus-math-96.png'                          = 'ico-mas.png'
    'iconos-app-mobil\icons8-subtract-96.png'                           = 'ico-menos.png'
    'iconos-app-mobil\icons8-edit-pencil-96.png'                        = 'ico-editar.png'
    'iconos-app-mobil\icons8-eliminar-96.png'                           = 'ico-eliminar.png'   # papelera
    'iconos-app-mobil\icons8-eliminar-96 (1).png'                       = 'ico-cerrar.png'     # aspa roja
    'iconos-app-mobil\icons8-eliminar-archivo-96.png'                   = 'ico-anular.png'
    'iconos-app-mobil\icons8-folder-96.png'                             = 'ico-categoria.png'
    'iconos-app-mobil\icons8-imagen-96.png'                             = 'ico-imagen.png'
    'iconos-app-mobil\icons8-añadir-imagen-96.png'                      = 'ico-anadir-imagen.png'

    # --- Estados y controles ---
    'iconos-app-mobil\icons8-done-96.png'                               = 'ico-listo.png'
    'iconos-app-mobil\icons8-check-mark-96.png'                         = 'ico-check.png'
    'iconos-app-mobil\icons8-error-96.png'                              = 'ico-error.png'
    'iconos-app-mobil\icons8-spinner-para-iphone-96.png'                = 'ico-cargando.png'
    'iconos-app-mobil\icons8-toggle-on-96.png'                          = 'ico-toggle-on.png'
    'iconos-app-mobil\icons8-toggle-off-96.png'                         = 'ico-toggle-off.png'
    'iconos-app-mobil\icons8-notification-96.png'                       = 'ico-notificacion.png'
    'iconos-app-mobil\icons8-heart-96.png'                              = 'ico-favorito.png'
    'iconos-app-mobil\icons8-refresh-96.png'                            = 'ico-actualizar.png'
    'iconos-app-mobil\icons8-globe-96.png'                              = 'ico-internet.png'
    'iconos-app-mobil\icons8-share-96.png'                              = 'ico-compartir.png'

    # --- Rubros (onboarding: elegir tipo de negocio) ---
    'iconos-app-mobil\icons8-tienda-96.png'                             = 'ico-tienda.png'        # bodega
    'iconos-app-mobil\icons8-cubiertos-96.png'                          = 'ico-restaurante.png'   # restaurante/cafeteria/polleria
    'iconos-app-mobil\icons8-píldora-96.png'                            = 'ico-farmacia.png'
    'iconos-app-mobil\icons8-mantenimiento-96.png'                      = 'ico-ferreteria.png'
    'iconos-app-mobil\icons8-cama-96.png'                               = 'ico-cama.png'          # hotel

    # --- Huecos que el set movil no cubre: del POS de escritorio ---
    'src\PagoYa.Desktop\Assets\Iconos\ico-candado.png'                  = 'ico-candado.png'
    'src\PagoYa.Desktop\Assets\Iconos\ico-nube.png'                     = 'ico-nube.png'
    'src\PagoYa.Desktop\Assets\Iconos\ico-inventario.png'               = 'ico-inventario.png'
    'src\PagoYa.Desktop\Assets\Iconos\ico-proveedores.png'              = 'ico-proveedores.png'
    'src\PagoYa.Desktop\Assets\Iconos\ico-facturacion.png'              = 'ico-facturacion.png'

    # --- Huecos: del set crudo Iconos-POS ---
    'Iconos-POS\icons8-print-96.png'                                    = 'ico-imprimir.png'
    'Iconos-POS\icons8-synchronize-96.png'                              = 'ico-sincronizar.png'
    'Iconos-POS\icons8-error-cloud-96.png'                              = 'ico-nube-error.png'
}

$copiados = 0
$faltantes = @()

foreach ($origen in $mapa.Keys) {
    $rutaOrigen = Join-Path $raiz $origen
    if (Test-Path -LiteralPath $rutaOrigen) {
        Copy-Item -LiteralPath $rutaOrigen -Destination (Join-Path $dst $mapa[$origen]) -Force
        $copiados++
    }
    else {
        $faltantes += $origen
    }
}

Write-Host ""
Write-Host "Copiados: $copiados de $($mapa.Count) a $dst"

if ($faltantes.Count -gt 0) {
    Write-Host ""
    Write-Host "FALTAN estos archivos de origen:" -ForegroundColor Yellow
    $faltantes | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "Revisa el nombre exacto (varios llevan tilde o enie) antes de dar por buena la copia." -ForegroundColor Yellow
}
else {
    Write-Host "Todos los iconos se copiaron correctamente." -ForegroundColor Green
}
