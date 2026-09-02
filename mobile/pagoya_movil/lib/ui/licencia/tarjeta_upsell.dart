/// ⚠ ARCHIVO OBSOLETO — **bórralo**.
///
/// Los visuales del upsell (`ContenidoUpsell`, `TarjetaFuncionBloqueada`,
/// `PanelUpsell`, `CandadoSobre`, `AvisoLicencia`) son de `mobile-ux` y viven en
/// `lib/ui/comun/funcion_bloqueada.dart`. Esta versión los duplicaba con textos
/// distintos, que es exactamente lo que `MOBILE-ARQUITECTURA.md` §3 evita.
///
/// La parte que sí es de `flutter-licencia` —decidir si el flag firmado está
/// habilitado— está en `gating_licencia.dart`, que consume aquellos widgets.
///
/// Se deja vacío en vez de eliminarlo porque el entorno donde se escribió no
/// tenía shell para borrar archivos. No declara nada: es inerte.
library;
