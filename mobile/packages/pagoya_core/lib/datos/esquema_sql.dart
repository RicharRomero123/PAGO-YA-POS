// PagoYa Móvil — datos/esquema_sql.dart
//
// Copia literal (sin comentarios) de `src/PagoYa.Data/Esquema/esquema.sql`.
// Vive en su propio archivo para que el diff contra el escritorio sea limpio:
// si alguien cambia el esquema de la PC, este archivo es el único que se toca.
//
// NO agregar tablas ni columnas propias del móvil aquí. Lo que el escritorio
// añade después con `AsegurarColumna` va en `Esquema.migracionesAditivas`.

library;

/// Script DDL del esquema local. Lo consume `Esquema.sentencias`.
const String scriptEsquemaSql = r'''
CREATE TABLE IF NOT EXISTS productos (
    id                  TEXT PRIMARY KEY,
    codigo              TEXT NOT NULL,
    nombre              TEXT NOT NULL,
    descripcion         TEXT NULL,
    precio_venta        REAL NOT NULL DEFAULT 0,
    costo_compra        REAL NULL,
    precio_incluye_igv  INTEGER NOT NULL DEFAULT 1,
    unidad_medida       TEXT NOT NULL DEFAULT 'NIU',
    stock_actual        REAL NOT NULL DEFAULT 0,
    controla_stock      INTEGER NOT NULL DEFAULT 1,
    activo              INTEGER NOT NULL DEFAULT 1,
    imagen_ruta         TEXT NULL,
    proveedor_id        TEXT NULL,
    stock_minimo        REAL NOT NULL DEFAULT 0,
    fecha_vencimiento   TEXT NULL,
    lote                TEXT NULL,
    registro_sanitario  TEXT NULL,
    principio_activo    TEXT NULL,
    requiere_receta     INTEGER NOT NULL DEFAULT 0,
    personalizacion_json TEXT NULL,
    origen_caja_id      TEXT NOT NULL DEFAULT '',
    created_utc         TEXT NOT NULL,
    updated_utc         TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS ix_productos_codigo ON productos(codigo);

CREATE TABLE IF NOT EXISTS proveedores (
    id              TEXT PRIMARY KEY,
    nombre          TEXT NOT NULL,
    ruc             TEXT NULL,
    contacto        TEXT NULL,
    telefono        TEXT NULL,
    direccion       TEXT NULL,
    notas           TEXT NULL,
    activo          INTEGER NOT NULL DEFAULT 1,
    origen_caja_id  TEXT NOT NULL DEFAULT '',
    created_utc     TEXT NOT NULL,
    updated_utc     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_proveedores_nombre ON proveedores(nombre);
CREATE INDEX IF NOT EXISTS ix_productos_nombre ON productos(nombre);

CREATE TABLE IF NOT EXISTS caja (
    id              TEXT PRIMARY KEY,
    nombre          TEXT NOT NULL DEFAULT 'Caja 1',
    cajero          TEXT NOT NULL DEFAULT '',
    estado          INTEGER NOT NULL DEFAULT 0,
    monto_apertura  REAL NOT NULL DEFAULT 0,
    fecha_apertura  TEXT NOT NULL,
    fecha_cierre    TEXT NULL,
    monto_cierre    REAL NULL,
    diferencia      REAL NULL,
    origen_caja_id  TEXT NOT NULL DEFAULT '',
    created_utc     TEXT NOT NULL,
    updated_utc     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_caja_estado ON caja(estado);

CREATE TABLE IF NOT EXISTS movimientos_caja (
    id              TEXT PRIMARY KEY,
    caja_id         TEXT NOT NULL,
    tipo            INTEGER NOT NULL,
    monto           REAL NOT NULL DEFAULT 0,
    concepto        TEXT NOT NULL DEFAULT '',
    fecha_hora      TEXT NOT NULL,
    origen_caja_id  TEXT NOT NULL DEFAULT '',
    created_utc     TEXT NOT NULL,
    updated_utc     TEXT NOT NULL,
    FOREIGN KEY (caja_id) REFERENCES caja(id)
);
CREATE INDEX IF NOT EXISTS ix_movcaja_caja ON movimientos_caja(caja_id);

CREATE TABLE IF NOT EXISTS ventas (
    id              TEXT PRIMARY KEY,
    numero          TEXT NOT NULL,
    caja_id         TEXT NOT NULL,
    fecha_hora      TEXT NOT NULL,
    metodo_pago     INTEGER NOT NULL DEFAULT 0,
    estado          INTEGER NOT NULL DEFAULT 0,
    sub_total       REAL NOT NULL DEFAULT 0,
    igv             REAL NOT NULL DEFAULT 0,
    total           REAL NOT NULL DEFAULT 0,
    monto_recibido  REAL NULL,
    comprobante_id  TEXT NULL,
    origen_caja_id  TEXT NOT NULL DEFAULT '',
    created_utc     TEXT NOT NULL,
    updated_utc     TEXT NOT NULL,
    FOREIGN KEY (caja_id) REFERENCES caja(id)
);
CREATE INDEX IF NOT EXISTS ix_ventas_caja ON ventas(caja_id);
CREATE INDEX IF NOT EXISTS ix_ventas_fecha ON ventas(fecha_hora);

CREATE TABLE IF NOT EXISTS detalle_ventas (
    id                    TEXT PRIMARY KEY,
    venta_id              TEXT NOT NULL,
    producto_id           TEXT NOT NULL,
    descripcion_producto  TEXT NOT NULL DEFAULT '',
    cantidad              REAL NOT NULL DEFAULT 0,
    precio_unitario       REAL NOT NULL DEFAULT 0,
    descuento             REAL NOT NULL DEFAULT 0,
    importe               REAL NOT NULL DEFAULT 0,
    origen_caja_id        TEXT NOT NULL DEFAULT '',
    created_utc           TEXT NOT NULL,
    updated_utc           TEXT NOT NULL,
    FOREIGN KEY (venta_id) REFERENCES ventas(id),
    FOREIGN KEY (producto_id) REFERENCES productos(id)
);
CREATE INDEX IF NOT EXISTS ix_detventas_venta ON detalle_ventas(venta_id);

CREATE TABLE IF NOT EXISTS inventario (
    id                TEXT PRIMARY KEY,
    producto_id       TEXT NOT NULL,
    cantidad          REAL NOT NULL DEFAULT 0,
    stock_resultante  REAL NOT NULL DEFAULT 0,
    motivo            TEXT NOT NULL DEFAULT '',
    referencia_id     TEXT NULL,
    fecha_hora        TEXT NOT NULL,
    origen_caja_id    TEXT NOT NULL DEFAULT '',
    created_utc       TEXT NOT NULL,
    updated_utc       TEXT NOT NULL,
    FOREIGN KEY (producto_id) REFERENCES productos(id)
);
CREATE INDEX IF NOT EXISTS ix_inventario_producto ON inventario(producto_id);

CREATE TABLE IF NOT EXISTS comprobantes (
    id                 TEXT PRIMARY KEY,
    venta_id           TEXT NOT NULL,
    tipo               INTEGER NOT NULL DEFAULT 0,
    serie              TEXT NOT NULL DEFAULT '',
    correlativo        INTEGER NOT NULL DEFAULT 0,
    documento_cliente  TEXT NULL,
    nombre_cliente     TEXT NULL,
    total              REAL NOT NULL DEFAULT 0,
    hash_xml           TEXT NULL,
    estado_sunat       TEXT NULL,
    codigo_cdr         TEXT NULL,
    ruta_xml           TEXT NULL,
    ruta_pdf           TEXT NULL,
    origen_caja_id     TEXT NOT NULL DEFAULT '',
    created_utc        TEXT NOT NULL,
    updated_utc        TEXT NOT NULL,
    FOREIGN KEY (venta_id) REFERENCES ventas(id)
);
CREATE INDEX IF NOT EXISTS ix_comprobantes_venta ON comprobantes(venta_id);
CREATE INDEX IF NOT EXISTS ix_comprobantes_serie ON comprobantes(serie, correlativo);

CREATE TABLE IF NOT EXISTS habitaciones (
    id              TEXT PRIMARY KEY,
    numero          TEXT NOT NULL,
    piso            INTEGER NOT NULL DEFAULT 0,
    tipo            INTEGER NOT NULL DEFAULT 0,
    precio_noche    REAL NOT NULL DEFAULT 0,
    precio_hora     REAL NOT NULL DEFAULT 0,
    capacidad       INTEGER NOT NULL DEFAULT 1,
    estado          INTEGER NOT NULL DEFAULT 0,
    notas           TEXT NULL,
    imagen_ruta     TEXT NULL,
    comodidades     TEXT NULL,
    activa          INTEGER NOT NULL DEFAULT 1,
    origen_caja_id  TEXT NOT NULL DEFAULT '',
    created_utc     TEXT NOT NULL,
    updated_utc     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_habitaciones_estado ON habitaciones(estado);

CREATE TABLE IF NOT EXISTS estadias_habitacion (
    id                 TEXT PRIMARY KEY,
    habitacion_id      TEXT NOT NULL,
    numero_habitacion  TEXT NOT NULL DEFAULT '',
    huesped_nombre     TEXT NOT NULL DEFAULT '',
    huesped_documento  TEXT NOT NULL DEFAULT '',
    huesped_telefono   TEXT NULL,
    personas           INTEGER NOT NULL DEFAULT 1,
    tipo_cobro         INTEGER NOT NULL DEFAULT 0,
    precio_unitario    REAL NOT NULL DEFAULT 0,
    check_in_utc       TEXT NOT NULL,
    check_out_utc      TEXT NULL,
    unidades           REAL NOT NULL DEFAULT 1,
    monto_hospedaje    REAL NOT NULL DEFAULT 0,
    monto_consumos     REAL NOT NULL DEFAULT 0,
    total              REAL NOT NULL DEFAULT 0,
    metodo_pago        INTEGER NOT NULL DEFAULT 0,
    estado             INTEGER NOT NULL DEFAULT 0,
    notas              TEXT NULL,
    origen_caja_id     TEXT NOT NULL DEFAULT '',
    created_utc        TEXT NOT NULL,
    updated_utc        TEXT NOT NULL,
    FOREIGN KEY (habitacion_id) REFERENCES habitaciones(id)
);
CREATE INDEX IF NOT EXISTS ix_estadias_habitacion ON estadias_habitacion(habitacion_id);
CREATE INDEX IF NOT EXISTS ix_estadias_estado ON estadias_habitacion(estado);

CREATE TABLE IF NOT EXISTS consumos_habitacion (
    id              TEXT PRIMARY KEY,
    estadia_id      TEXT NOT NULL,
    producto_id     TEXT NULL,
    descripcion     TEXT NOT NULL DEFAULT '',
    cantidad        REAL NOT NULL DEFAULT 1,
    precio_unitario REAL NOT NULL DEFAULT 0,
    fecha_hora_utc  TEXT NOT NULL,
    origen_caja_id  TEXT NOT NULL DEFAULT '',
    created_utc     TEXT NOT NULL,
    updated_utc     TEXT NOT NULL,
    FOREIGN KEY (estadia_id) REFERENCES estadias_habitacion(id)
);
CREATE INDEX IF NOT EXISTS ix_consumos_estadia ON consumos_habitacion(estadia_id);

CREATE TABLE IF NOT EXISTS mesas (
    id              TEXT PRIMARY KEY,
    numero          TEXT NOT NULL,
    zona            TEXT NULL,
    capacidad       INTEGER NOT NULL DEFAULT 4,
    estado          INTEGER NOT NULL DEFAULT 0,
    notas           TEXT NULL,
    activa          INTEGER NOT NULL DEFAULT 1,
    origen_caja_id  TEXT NOT NULL DEFAULT '',
    created_utc     TEXT NOT NULL,
    updated_utc     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_mesas_estado ON mesas(estado);

CREATE TABLE IF NOT EXISTS pedidos (
    id              TEXT PRIMARY KEY,
    mesa_id         TEXT NOT NULL,
    numero_mesa     TEXT NOT NULL DEFAULT '',
    numero          TEXT NOT NULL,
    estado          INTEGER NOT NULL DEFAULT 0,
    mozo            TEXT NOT NULL DEFAULT '',
    comensales      INTEGER NOT NULL DEFAULT 1,
    fecha_apertura  TEXT NOT NULL,
    fecha_cierre    TEXT NULL,
    total           REAL NOT NULL DEFAULT 0,
    notas           TEXT NULL,
    venta_id        TEXT NULL,
    origen_caja_id  TEXT NOT NULL DEFAULT '',
    created_utc     TEXT NOT NULL,
    updated_utc     TEXT NOT NULL,
    FOREIGN KEY (mesa_id) REFERENCES mesas(id)
);
CREATE INDEX IF NOT EXISTS ix_pedidos_mesa ON pedidos(mesa_id);
CREATE INDEX IF NOT EXISTS ix_pedidos_estado ON pedidos(estado);

CREATE TABLE IF NOT EXISTS pedido_lineas (
    id              TEXT PRIMARY KEY,
    pedido_id       TEXT NOT NULL,
    producto_id     TEXT NULL,
    descripcion     TEXT NOT NULL DEFAULT '',
    nota            TEXT NULL,
    cantidad        REAL NOT NULL DEFAULT 1,
    precio_unitario REAL NOT NULL DEFAULT 0,
    importe         REAL NOT NULL DEFAULT 0,
    enviado_cocina  INTEGER NOT NULL DEFAULT 0,
    origen_caja_id  TEXT NOT NULL DEFAULT '',
    created_utc     TEXT NOT NULL,
    updated_utc     TEXT NOT NULL,
    FOREIGN KEY (pedido_id) REFERENCES pedidos(id)
);
CREATE INDEX IF NOT EXISTS ix_pedidolineas_pedido ON pedido_lineas(pedido_id);

CREATE TABLE IF NOT EXISTS outbox_sync (
    id             TEXT PRIMARY KEY,
    entidad        TEXT NOT NULL,
    entidad_id     TEXT NOT NULL,
    operacion      TEXT NOT NULL,
    payload_json   TEXT NOT NULL,
    estado         INTEGER NOT NULL DEFAULT 0,
    intentos       INTEGER NOT NULL DEFAULT 0,
    origen_caja_id TEXT NOT NULL DEFAULT '',
    created_utc    TEXT NOT NULL,
    enviado_utc    TEXT NULL
);
CREATE INDEX IF NOT EXISTS ix_outbox_estado ON outbox_sync(estado, created_utc);

CREATE TABLE IF NOT EXISTS usuarios (
    id                TEXT PRIMARY KEY,
    nombre_usuario    TEXT NOT NULL,
    nombre_completo   TEXT NOT NULL DEFAULT '',
    password_hash     TEXT NOT NULL,
    password_salt     TEXT NOT NULL,
    rol               INTEGER NOT NULL DEFAULT 1,
    activo            INTEGER NOT NULL DEFAULT 1,
    ultimo_acceso_utc TEXT NULL,
    origen_caja_id    TEXT NOT NULL DEFAULT '',
    created_utc       TEXT NOT NULL,
    updated_utc       TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS ix_usuarios_nombre ON usuarios(nombre_usuario);

CREATE TABLE IF NOT EXISTS meta (
    clave  TEXT PRIMARY KEY,
    valor  TEXT NOT NULL
);
INSERT OR IGNORE INTO meta(clave, valor) VALUES ('schema_version', '1');
''';
