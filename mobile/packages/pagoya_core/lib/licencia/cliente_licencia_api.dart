/// ⚠ ARCHIVO OBSOLETO — **bórralo**.
///
/// El cliente HTTP de seats es `ServicioDispositivos` (`nube/contratos.dart`,
/// dueño `mobile-lead`), y lo implementa `flutter-sync` con
/// `crearServicioDispositivos`. Este archivo lo duplicaba con `dio` propio.
///
/// Los supuestos sobre `POST /devices` que aquí se documentaban se movieron a
/// `revalidador_licencia.dart`, que es quien los consume.
///
/// Se deja vacío en vez de eliminarlo porque el entorno donde se escribió no
/// tenía shell para borrar archivos. No declara nada: es inerte.
library;
