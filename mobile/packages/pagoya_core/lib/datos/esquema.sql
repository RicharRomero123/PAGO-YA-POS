-- =============================================================================
--  PagoYa — Esquema de base de datos local (SQLite)
--
--  COPIA LITERAL de src/PagoYa.Data/Esquema/esquema.sql (POS de escritorio).
--  NO se modifica la forma: mismos nombres de tabla y columna, PK TEXT con
--  UUID, fechas UTC ISO-8601 en TEXT, montos REAL, origen_caja_id en cada
--  tabla. Divergir aquí rompe la sincronización con la PC.
--
--  Este archivo es la referencia para diffear contra el escritorio. El que
--  se EJECUTA es la constante de `esquema.dart`, porque `pagoya_core` es Dart
--  puro y no puede cargar assets de Flutter.
--
--  Las columnas `tipo_descuento` y `descuento_valor` de `productos` NO están
--  aquí (igual que en el escritorio): las agrega la migración aditiva de
--  `PagoYaDbContext.InicializarEsquema` / `Esquema.migracionesAditivas`.
-- =============================================================================

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;   -- mejor concurrencia lectura/escritura en el POS

-- -----------------------------------------------------------------------------
--  PRODUCTOS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS productos (
    id                  TEXT PRIMARY KEY,              -- UUID
    codigo              TEXT NOT NULL,                 -- código de barras / SKU
    nombre              TEXT NOT NULL,
    descripcion         TEXT NULL,
    precio_venta        REAL NOT NULL DEFAULT 0,
    costo_compra        REAL NULL,
    precio_incluye_igv  INTEGER NOT NULL DEFAULT 1,    -- boolean 0/1
    unidad_medida       TEXT NOT NULL DEFAULT 'NIU',
    stock_actual        REAL NOT NULL DEFAULT 0,       -- cache; verdad en 'inventario'
    controla_stock      INTEGER NOT NULL DEFAULT 1,
    activo              INTEGER NOT NULL DEFAULT 1,
    imagen_ruta         TEXT NULL,                     -- foto local del producto (opcional)
    proveedor_id        TEXT NULL,                     -- proveedor asignado (opcional)
    stock_minimo        REAL NOT NULL DEFAULT 0,       -- umbral de reposición (0 = sin aviso)
    -- Campos farmacéuticos (rubro farmacia/botica; NULL en otros rubros):
    fecha_vencimiento   TEXT NULL,                     -- 'yyyy-MM-dd' del lote vigente
    lote                TEXT NULL,                     -- número de lote (trazabilidad)
    registro_sanitario  TEXT NULL,                     -- Registro Sanitario DIGEMID
    principio_activo    TEXT NULL,                     -- DCI (para búsqueda de genéricos)
    requiere_receta     INTEGER NOT NULL DEFAULT 0,    -- boolean 0/1 (venta con receta)
    personalizacion_json TEXT NULL,                    -- modificadores JSON (rubro restaurante)
    origen_caja_id      TEXT NOT NULL DEFAULT '',
    created_utc         TEXT NOT NULL,
    updated_utc         TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS ix_productos_codigo ON productos(codigo);

-- -----------------------------------------------------------------------------
--  PROVEEDORES (distribuidores/mayoristas; enlazados a productos)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS proveedores (
    id              TEXT PRIMARY KEY,                  -- UUID
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

-- -----------------------------------------------------------------------------
--  CAJA (sesiones / arqueo)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS caja (
    id              TEXT PRIMARY KEY,                  -- UUID
    nombre          TEXT NOT NULL DEFAULT 'Caja 1',
    cajero          TEXT NOT NULL DEFAULT '',
    estado          INTEGER NOT NULL DEFAULT 0,        -- 0=Abierta, 1=Cerrada
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

-- -----------------------------------------------------------------------------
--  MOVIMIENTOS DE CAJA (ingresos/egresos/retiros distintos a ventas)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS movimientos_caja (
    id              TEXT PRIMARY KEY,                  -- UUID
    caja_id         TEXT NOT NULL,
    tipo            INTEGER NOT NULL,                  -- TipoMovimientoCaja
    monto           REAL NOT NULL DEFAULT 0,
    concepto        TEXT NOT NULL DEFAULT '',
    fecha_hora      TEXT NOT NULL,
    origen_caja_id  TEXT NOT NULL DEFAULT '',
    created_utc     TEXT NOT NULL,
    updated_utc     TEXT NOT NULL,
    FOREIGN KEY (caja_id) REFERENCES caja(id)
);
CREATE INDEX IF NOT EXISTS ix_movcaja_caja ON movimientos_caja(caja_id);

-- -----------------------------------------------------------------------------
--  VENTAS (cabecera)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ventas (
    id              TEXT PRIMARY KEY,                  -- UUID
    numero          TEXT NOT NULL,                     -- correlativo legible por caja
    caja_id         TEXT NOT NULL,
    fecha_hora      TEXT NOT NULL,
    metodo_pago     INTEGER NOT NULL DEFAULT 0,        -- MetodoPago
    estado          INTEGER NOT NULL DEFAULT 0,        -- EstadoVenta
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

-- -----------------------------------------------------------------------------
--  DETALLE DE VENTAS (líneas)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS detalle_ventas (
    id                    TEXT PRIMARY KEY,            -- UUID
    venta_id              TEXT NOT NULL,
    producto_id           TEXT NOT NULL,
    descripcion_producto  TEXT NOT NULL DEFAULT '',    -- congelada al momento de venta
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

-- -----------------------------------------------------------------------------
--  INVENTARIO (kardex: fuente de verdad del stock)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS inventario (
    id                TEXT PRIMARY KEY,                -- UUID
    producto_id       TEXT NOT NULL,
    cantidad          REAL NOT NULL DEFAULT 0,         -- +entrada / -salida
    stock_resultante  REAL NOT NULL DEFAULT 0,
    motivo            TEXT NOT NULL DEFAULT '',
    referencia_id     TEXT NULL,                       -- ej. id de venta
    fecha_hora        TEXT NOT NULL,
    origen_caja_id    TEXT NOT NULL DEFAULT '',
    created_utc       TEXT NOT NULL,
    updated_utc       TEXT NOT NULL,
    FOREIGN KEY (producto_id) REFERENCES productos(id)
);
CREATE INDEX IF NOT EXISTS ix_inventario_producto ON inventario(producto_id);

-- -----------------------------------------------------------------------------
--  COMPROBANTES (nota de venta / boleta / factura)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS comprobantes (
    id                 TEXT PRIMARY KEY,               -- UUID
    venta_id           TEXT NOT NULL,
    tipo               INTEGER NOT NULL DEFAULT 0,     -- TipoComprobante
    serie              TEXT NOT NULL DEFAULT '',
    correlativo        INTEGER NOT NULL DEFAULT 0,
    documento_cliente  TEXT NULL,
    nombre_cliente     TEXT NULL,
    total              REAL NOT NULL DEFAULT 0,
    -- Campos de facturación electrónica (solo con flag "invoicing"):
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

-- -----------------------------------------------------------------------------
--  HOTEL — HABITACIONES (rubro hotel/hostal): maestro de cuartos + mapa
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS habitaciones (
    id              TEXT PRIMARY KEY,                  -- UUID
    numero          TEXT NOT NULL,                     -- "101", "Suite A"
    piso            INTEGER NOT NULL DEFAULT 0,
    tipo            INTEGER NOT NULL DEFAULT 0,         -- TipoHabitacion
    precio_noche    REAL NOT NULL DEFAULT 0,
    precio_hora     REAL NOT NULL DEFAULT 0,           -- hostal del paso; 0 = no ofrece
    capacidad       INTEGER NOT NULL DEFAULT 1,
    estado          INTEGER NOT NULL DEFAULT 0,        -- EstadoHabitacion
    notas           TEXT NULL,
    imagen_ruta     TEXT NULL,                         -- foto local de la habitación
    comodidades     TEXT NULL,                         -- adicionales (TV, jacuzzi…) unidos por '|'
    activa          INTEGER NOT NULL DEFAULT 1,
    origen_caja_id  TEXT NOT NULL DEFAULT '',
    created_utc     TEXT NOT NULL,
    updated_utc     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_habitaciones_estado ON habitaciones(estado);

-- -----------------------------------------------------------------------------
--  HOTEL — ESTADÍAS (check-in / check-out de una habitación)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS estadias_habitacion (
    id                 TEXT PRIMARY KEY,               -- UUID
    habitacion_id      TEXT NOT NULL,
    numero_habitacion  TEXT NOT NULL DEFAULT '',       -- congelado
    huesped_nombre     TEXT NOT NULL DEFAULT '',
    huesped_documento  TEXT NOT NULL DEFAULT '',
    huesped_telefono   TEXT NULL,
    personas           INTEGER NOT NULL DEFAULT 1,
    tipo_cobro         INTEGER NOT NULL DEFAULT 0,      -- TipoCobroHospedaje (0 noche/1 hora)
    precio_unitario    REAL NOT NULL DEFAULT 0,
    check_in_utc       TEXT NOT NULL,
    check_out_utc      TEXT NULL,
    unidades           REAL NOT NULL DEFAULT 1,
    monto_hospedaje    REAL NOT NULL DEFAULT 0,
    monto_consumos     REAL NOT NULL DEFAULT 0,
    total              REAL NOT NULL DEFAULT 0,
    metodo_pago        INTEGER NOT NULL DEFAULT 0,      -- MetodoPago
    estado             INTEGER NOT NULL DEFAULT 0,      -- EstadoEstadia
    notas              TEXT NULL,
    origen_caja_id     TEXT NOT NULL DEFAULT '',
    created_utc        TEXT NOT NULL,
    updated_utc        TEXT NOT NULL,
    FOREIGN KEY (habitacion_id) REFERENCES habitaciones(id)
);
CREATE INDEX IF NOT EXISTS ix_estadias_habitacion ON estadias_habitacion(habitacion_id);
CREATE INDEX IF NOT EXISTS ix_estadias_estado ON estadias_habitacion(estado);

-- -----------------------------------------------------------------------------
--  HOTEL — CONSUMOS cargados a una estadía (minibar, lavandería, restaurante)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS consumos_habitacion (
    id              TEXT PRIMARY KEY,                  -- UUID
    estadia_id      TEXT NOT NULL,
    producto_id     TEXT NULL,                         -- ref. inventario (opcional)
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

-- -----------------------------------------------------------------------------
--  RESTAURANTE — MESAS (rubro restaurante): maestro del salón + mapa
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS mesas (
    id              TEXT PRIMARY KEY,                  -- UUID
    numero          TEXT NOT NULL,                     -- "1", "Terraza 2"
    zona            TEXT NULL,                          -- "Salón", "Terraza"
    capacidad       INTEGER NOT NULL DEFAULT 4,
    estado          INTEGER NOT NULL DEFAULT 0,         -- EstadoMesa (0 Libre…)
    notas           TEXT NULL,
    activa          INTEGER NOT NULL DEFAULT 1,
    origen_caja_id  TEXT NOT NULL DEFAULT '',
    created_utc     TEXT NOT NULL,
    updated_utc     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_mesas_estado ON mesas(estado);

-- -----------------------------------------------------------------------------
--  RESTAURANTE — PEDIDOS (comanda / cuenta abierta de una mesa)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pedidos (
    id              TEXT PRIMARY KEY,                  -- UUID
    mesa_id         TEXT NOT NULL,
    numero_mesa     TEXT NOT NULL DEFAULT '',          -- congelado
    numero          TEXT NOT NULL,                     -- correlativo legible
    estado          INTEGER NOT NULL DEFAULT 0,        -- EstadoPedido (0 Abierta…)
    mozo            TEXT NOT NULL DEFAULT '',
    comensales      INTEGER NOT NULL DEFAULT 1,
    fecha_apertura  TEXT NOT NULL,
    fecha_cierre    TEXT NULL,
    total           REAL NOT NULL DEFAULT 0,
    notas           TEXT NULL,
    venta_id        TEXT NULL,                          -- venta generada al cobrar
    origen_caja_id  TEXT NOT NULL DEFAULT '',
    created_utc     TEXT NOT NULL,
    updated_utc     TEXT NOT NULL,
    FOREIGN KEY (mesa_id) REFERENCES mesas(id)
);
CREATE INDEX IF NOT EXISTS ix_pedidos_mesa ON pedidos(mesa_id);
CREATE INDEX IF NOT EXISTS ix_pedidos_estado ON pedidos(estado);

-- -----------------------------------------------------------------------------
--  RESTAURANTE — LÍNEAS de la comanda (platos/bebidas con su personalización)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pedido_lineas (
    id              TEXT PRIMARY KEY,                  -- UUID
    pedido_id       TEXT NOT NULL,
    producto_id     TEXT NULL,                          -- ref. catálogo (opcional)
    descripcion     TEXT NOT NULL DEFAULT '',           -- nombre + modificadores
    nota            TEXT NULL,                           -- nota de cocina
    cantidad        REAL NOT NULL DEFAULT 1,
    precio_unitario REAL NOT NULL DEFAULT 0,
    importe         REAL NOT NULL DEFAULT 0,
    enviado_cocina  INTEGER NOT NULL DEFAULT 0,          -- boolean 0/1
    origen_caja_id  TEXT NOT NULL DEFAULT '',
    created_utc     TEXT NOT NULL,
    updated_utc     TEXT NOT NULL,
    FOREIGN KEY (pedido_id) REFERENCES pedidos(id)
);
CREATE INDEX IF NOT EXISTS ix_pedidolineas_pedido ON pedido_lineas(pedido_id);

-- =============================================================================
--  OUTBOX PATTERN (sincronización eventual con la nube — tier Cloud)
--
--  Cada escritura de negocio registra aquí una fila con el snapshot
--  (payload_json) de la entidad, EN LA MISMA TRANSACCIÓN que la escritura.
--  Resolución de conflictos: last-write-wins por updated_utc + UUID.
--  En el tier Base la tabla existe pero permanece vacía/ignorada.
-- =============================================================================
CREATE TABLE IF NOT EXISTS outbox_sync (
    id             TEXT PRIMARY KEY,                   -- UUID del evento outbox
    entidad        TEXT NOT NULL,                      -- 'producto','venta',...
    entidad_id     TEXT NOT NULL,                      -- UUID de la fila afectada
    operacion      TEXT NOT NULL,                      -- 'INSERT'|'UPDATE'|'DELETE'
    payload_json   TEXT NOT NULL,                      -- snapshot serializado
    estado         INTEGER NOT NULL DEFAULT 0,         -- 0=Pendiente,1=Enviado,2=Error
    intentos       INTEGER NOT NULL DEFAULT 0,
    origen_caja_id TEXT NOT NULL DEFAULT '',
    created_utc    TEXT NOT NULL,
    enviado_utc    TEXT NULL
);
CREATE INDEX IF NOT EXISTS ix_outbox_estado ON outbox_sync(estado, created_utc);

-- -----------------------------------------------------------------------------
--  USUARIOS (login local del POS: administrador + cajeros)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS usuarios (
    id                TEXT PRIMARY KEY,                -- UUID
    nombre_usuario    TEXT NOT NULL,                   -- login (minúsculas)
    nombre_completo   TEXT NOT NULL DEFAULT '',
    password_hash     TEXT NOT NULL,
    password_salt     TEXT NOT NULL,
    rol               INTEGER NOT NULL DEFAULT 1,      -- RolUsuario (0=Admin,1=Cajero)
    activo            INTEGER NOT NULL DEFAULT 1,
    ultimo_acceso_utc TEXT NULL,
    origen_caja_id    TEXT NOT NULL DEFAULT '',
    created_utc       TEXT NOT NULL,
    updated_utc       TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS ix_usuarios_nombre ON usuarios(nombre_usuario);

-- -----------------------------------------------------------------------------
--  META / configuración local (versión de esquema, id de dispositivo, cursor…)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS meta (
    clave  TEXT PRIMARY KEY,
    valor  TEXT NOT NULL
);
INSERT OR IGNORE INTO meta(clave, valor) VALUES ('schema_version', '1');
