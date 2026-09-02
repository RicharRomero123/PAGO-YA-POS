using System.Globalization;
using Dapper;
using PagoYa.Core.Contratos;
using PagoYa.Core.Entidades;
using PagoYa.Core.Enums;

namespace PagoYa.Data.Repositorios;

/// <summary>
/// Implementación SQLite (Dapper) de <see cref="IHotelRepository"/>: habitaciones,
/// estadías y consumos del rubro hotelero. Sigue las mismas convenciones que el
/// resto de repositorios (REAL para montos, TEXT ISO-8601 para fechas UTC, escritura
/// del outbox en la misma transacción para sync futura).
/// </summary>
public sealed class HotelRepository : IHotelRepository
{
    private readonly PagoYaDbContext _db;

    public HotelRepository(PagoYaDbContext db) => _db = db;

    private static readonly DateTimeStyles Iso = DateTimeStyles.RoundtripKind;

    // ==================== HABITACIONES ====================

    private const string SelectHab = """
        SELECT id, numero, piso, tipo, precio_noche, precio_hora, capacidad,
               estado, notas, imagen_ruta, comodidades, activa, origen_caja_id, created_utc, updated_utc
        FROM habitaciones
        """;

    public async Task<IReadOnlyList<Habitacion>> ListarHabitacionesAsync(bool soloActivas = true, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var sql = soloActivas ? $"{SelectHab} WHERE activa = 1" : SelectHab;
        sql += " ORDER BY piso, numero COLLATE NOCASE";
        var filas = await cx.QueryAsync<FilaHabitacion>(new CommandDefinition(sql, cancellationToken: ct));
        return filas.Select(f => f.AHabitacion()).ToList();
    }

    public async Task<Habitacion?> ObtenerHabitacionAsync(Guid id, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var fila = await cx.QuerySingleOrDefaultAsync<FilaHabitacion>(
            new CommandDefinition($"{SelectHab} WHERE id = @id", new { id = id.ToString() }, cancellationToken: ct));
        return fila?.AHabitacion();
    }

    public async Task GuardarHabitacionAsync(Habitacion h, CancellationToken ct = default)
    {
        h.ActualizadoUtc = DateTime.UtcNow;
        await using var cx = await _db.CrearConexionAsync(ct);
        await using var tx = await cx.BeginTransactionAsync(ct);

        const string upsert = """
            INSERT INTO habitaciones
                (id, numero, piso, tipo, precio_noche, precio_hora, capacidad,
                 estado, notas, imagen_ruta, comodidades, activa, origen_caja_id, created_utc, updated_utc)
            VALUES
                (@Id, @Numero, @Piso, @Tipo, @PrecioNoche, @PrecioHora, @Capacidad,
                 @Estado, @Notas, @ImagenRuta, @Comodidades, @Activa, @OrigenCajaId, @CreadoUtc, @ActualizadoUtc)
            ON CONFLICT(id) DO UPDATE SET
                numero = excluded.numero, piso = excluded.piso, tipo = excluded.tipo,
                precio_noche = excluded.precio_noche, precio_hora = excluded.precio_hora,
                capacidad = excluded.capacidad, estado = excluded.estado, notas = excluded.notas,
                imagen_ruta = excluded.imagen_ruta, comodidades = excluded.comodidades,
                activa = excluded.activa, updated_utc = excluded.updated_utc
            """;

        await cx.ExecuteAsync(new CommandDefinition(upsert, new
        {
            Id = h.Id.ToString(), h.Numero, h.Piso, Tipo = (int)h.Tipo,
            PrecioNoche = (double)h.PrecioNoche, PrecioHora = (double)h.PrecioHora,
            h.Capacidad, Estado = (int)h.Estado, h.Notas, h.ImagenRuta, h.Comodidades, Activa = h.Activa ? 1 : 0,
            h.OrigenCajaId, CreadoUtc = h.CreadoUtc.ToString("o"), ActualizadoUtc = h.ActualizadoUtc.ToString("o")
        }, tx, cancellationToken: ct));

        await OutboxHelper.RegistrarAsync(cx, tx, "habitacion", h.Id, "UPSERT", h, h.OrigenCajaId, ct);
        await tx.CommitAsync(ct);
    }

    public async Task DesactivarHabitacionAsync(Guid id, CancellationToken ct = default)
    {
        var ahora = DateTime.UtcNow.ToString("o");
        await using var cx = await _db.CrearConexionAsync(ct);
        await cx.ExecuteAsync(new CommandDefinition(
            "UPDATE habitaciones SET activa = 0, updated_utc = @ahora WHERE id = @id",
            new { id = id.ToString(), ahora }, cancellationToken: ct));
    }

    public async Task CambiarEstadoHabitacionAsync(Guid id, EstadoHabitacion estado, CancellationToken ct = default)
    {
        var ahora = DateTime.UtcNow.ToString("o");
        await using var cx = await _db.CrearConexionAsync(ct);
        await cx.ExecuteAsync(new CommandDefinition(
            "UPDATE habitaciones SET estado = @estado, updated_utc = @ahora WHERE id = @id",
            new { id = id.ToString(), estado = (int)estado, ahora }, cancellationToken: ct));
    }

    // ==================== ESTADÍAS ====================

    private const string SelectEst = """
        SELECT id, habitacion_id, numero_habitacion, huesped_nombre, huesped_documento,
               huesped_telefono, personas, tipo_cobro, precio_unitario, check_in_utc,
               check_out_utc, unidades, monto_hospedaje, monto_consumos, total,
               metodo_pago, estado, notas, origen_caja_id, created_utc, updated_utc
        FROM estadias_habitacion
        """;

    public async Task<EstadiaHabitacion?> ObtenerEstadiaActivaAsync(Guid habitacionId, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var fila = await cx.QuerySingleOrDefaultAsync<FilaEstadia>(new CommandDefinition(
            $"{SelectEst} WHERE habitacion_id = @h AND estado = 0 ORDER BY check_in_utc DESC LIMIT 1",
            new { h = habitacionId.ToString() }, cancellationToken: ct));
        return fila?.AEstadia();
    }

    public async Task<EstadiaHabitacion?> ObtenerEstadiaAsync(Guid estadiaId, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var fila = await cx.QuerySingleOrDefaultAsync<FilaEstadia>(new CommandDefinition(
            $"{SelectEst} WHERE id = @id", new { id = estadiaId.ToString() }, cancellationToken: ct));
        return fila?.AEstadia();
    }

    public async Task GuardarEstadiaAsync(EstadiaHabitacion e, CancellationToken ct = default)
    {
        e.ActualizadoUtc = DateTime.UtcNow;
        await using var cx = await _db.CrearConexionAsync(ct);
        await using var tx = await cx.BeginTransactionAsync(ct);

        const string upsert = """
            INSERT INTO estadias_habitacion
                (id, habitacion_id, numero_habitacion, huesped_nombre, huesped_documento,
                 huesped_telefono, personas, tipo_cobro, precio_unitario, check_in_utc,
                 check_out_utc, unidades, monto_hospedaje, monto_consumos, total,
                 metodo_pago, estado, notas, origen_caja_id, created_utc, updated_utc)
            VALUES
                (@Id, @HabitacionId, @NumeroHabitacion, @HuespedNombre, @HuespedDocumento,
                 @HuespedTelefono, @Personas, @TipoCobro, @PrecioUnitario, @CheckInUtc,
                 @CheckOutUtc, @Unidades, @MontoHospedaje, @MontoConsumos, @Total,
                 @MetodoPago, @Estado, @Notas, @OrigenCajaId, @CreadoUtc, @ActualizadoUtc)
            ON CONFLICT(id) DO UPDATE SET
                huesped_nombre = excluded.huesped_nombre, huesped_documento = excluded.huesped_documento,
                huesped_telefono = excluded.huesped_telefono, personas = excluded.personas,
                tipo_cobro = excluded.tipo_cobro, precio_unitario = excluded.precio_unitario,
                check_out_utc = excluded.check_out_utc, unidades = excluded.unidades,
                monto_hospedaje = excluded.monto_hospedaje, monto_consumos = excluded.monto_consumos,
                total = excluded.total, metodo_pago = excluded.metodo_pago, estado = excluded.estado,
                notas = excluded.notas, updated_utc = excluded.updated_utc
            """;

        await cx.ExecuteAsync(new CommandDefinition(upsert, new
        {
            Id = e.Id.ToString(), HabitacionId = e.HabitacionId.ToString(), e.NumeroHabitacion,
            e.HuespedNombre, e.HuespedDocumento, e.HuespedTelefono, e.Personas,
            TipoCobro = (int)e.TipoCobro, PrecioUnitario = (double)e.PrecioUnitario,
            CheckInUtc = e.CheckInUtc.ToString("o"),
            CheckOutUtc = e.CheckOutUtc?.ToString("o"),
            Unidades = (double)e.Unidades, MontoHospedaje = (double)e.MontoHospedaje,
            MontoConsumos = (double)e.MontoConsumos, Total = (double)e.Total,
            e.MetodoPago, Estado = (int)e.Estado, e.Notas, e.OrigenCajaId,
            CreadoUtc = e.CreadoUtc.ToString("o"), ActualizadoUtc = e.ActualizadoUtc.ToString("o")
        }, tx, cancellationToken: ct));

        await OutboxHelper.RegistrarAsync(cx, tx, "estadia_habitacion", e.Id, "UPSERT", e, e.OrigenCajaId, ct);
        await tx.CommitAsync(ct);
    }

    // ==================== CONSUMOS ====================

    private const string SelectCon = """
        SELECT id, estadia_id, producto_id, descripcion, cantidad, precio_unitario,
               fecha_hora_utc, origen_caja_id, created_utc, updated_utc
        FROM consumos_habitacion
        """;

    public async Task<IReadOnlyList<ConsumoHabitacion>> ListarConsumosAsync(Guid estadiaId, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var filas = await cx.QueryAsync<FilaConsumo>(new CommandDefinition(
            $"{SelectCon} WHERE estadia_id = @e ORDER BY fecha_hora_utc DESC",
            new { e = estadiaId.ToString() }, cancellationToken: ct));
        return filas.Select(f => f.AConsumo()).ToList();
    }

    public async Task AgregarConsumoAsync(ConsumoHabitacion c, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        const string insert = """
            INSERT INTO consumos_habitacion
                (id, estadia_id, producto_id, descripcion, cantidad, precio_unitario,
                 fecha_hora_utc, origen_caja_id, created_utc, updated_utc)
            VALUES
                (@Id, @EstadiaId, @ProductoId, @Descripcion, @Cantidad, @PrecioUnitario,
                 @FechaHoraUtc, @OrigenCajaId, @CreadoUtc, @ActualizadoUtc)
            """;
        await cx.ExecuteAsync(new CommandDefinition(insert, new
        {
            Id = c.Id.ToString(), EstadiaId = c.EstadiaId.ToString(), ProductoId = c.ProductoId?.ToString(),
            c.Descripcion, Cantidad = (double)c.Cantidad, PrecioUnitario = (double)c.PrecioUnitario,
            FechaHoraUtc = c.FechaHoraUtc.ToString("o"), c.OrigenCajaId,
            CreadoUtc = c.CreadoUtc.ToString("o"), ActualizadoUtc = c.ActualizadoUtc.ToString("o")
        }, cancellationToken: ct));
    }

    public async Task QuitarConsumoAsync(Guid consumoId, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        await cx.ExecuteAsync(new CommandDefinition(
            "DELETE FROM consumos_habitacion WHERE id = @id", new { id = consumoId.ToString() }, cancellationToken: ct));
    }

    public async Task<decimal> TotalConsumosAsync(Guid estadiaId, CancellationToken ct = default)
    {
        await using var cx = await _db.CrearConexionAsync(ct);
        var total = await cx.ExecuteScalarAsync<double?>(new CommandDefinition(
            "SELECT COALESCE(SUM(cantidad * precio_unitario), 0) FROM consumos_habitacion WHERE estadia_id = @e",
            new { e = estadiaId.ToString() }, cancellationToken: ct));
        return (decimal)(total ?? 0);
    }

    // ==================== FILAS (mapeo snake_case) ====================

    private sealed class FilaHabitacion
    {
        public string id { get; set; } = "";
        public string numero { get; set; } = "";
        public long piso { get; set; }
        public long tipo { get; set; }
        public double precio_noche { get; set; }
        public double precio_hora { get; set; }
        public long capacidad { get; set; }
        public long estado { get; set; }
        public string? notas { get; set; }
        public string? imagen_ruta { get; set; }
        public string? comodidades { get; set; }
        public long activa { get; set; }
        public string origen_caja_id { get; set; } = "";
        public string created_utc { get; set; } = "";
        public string updated_utc { get; set; } = "";

        public Habitacion AHabitacion() => new()
        {
            Id = Guid.Parse(id), Numero = numero, Piso = (int)piso, Tipo = (TipoHabitacion)tipo,
            PrecioNoche = (decimal)precio_noche, PrecioHora = (decimal)precio_hora, Capacidad = (int)capacidad,
            Estado = (EstadoHabitacion)estado, Notas = notas, ImagenRuta = imagen_ruta,
            Comodidades = comodidades, Activa = activa != 0,
            OrigenCajaId = origen_caja_id,
            CreadoUtc = DateTime.Parse(created_utc, null, Iso),
            ActualizadoUtc = DateTime.Parse(updated_utc, null, Iso)
        };
    }

    private sealed class FilaEstadia
    {
        public string id { get; set; } = "";
        public string habitacion_id { get; set; } = "";
        public string numero_habitacion { get; set; } = "";
        public string huesped_nombre { get; set; } = "";
        public string huesped_documento { get; set; } = "";
        public string? huesped_telefono { get; set; }
        public long personas { get; set; }
        public long tipo_cobro { get; set; }
        public double precio_unitario { get; set; }
        public string check_in_utc { get; set; } = "";
        public string? check_out_utc { get; set; }
        public double unidades { get; set; }
        public double monto_hospedaje { get; set; }
        public double monto_consumos { get; set; }
        public double total { get; set; }
        public long metodo_pago { get; set; }
        public long estado { get; set; }
        public string? notas { get; set; }
        public string origen_caja_id { get; set; } = "";
        public string created_utc { get; set; } = "";
        public string updated_utc { get; set; } = "";

        public EstadiaHabitacion AEstadia() => new()
        {
            Id = Guid.Parse(id), HabitacionId = Guid.Parse(habitacion_id), NumeroHabitacion = numero_habitacion,
            HuespedNombre = huesped_nombre, HuespedDocumento = huesped_documento, HuespedTelefono = huesped_telefono,
            Personas = (int)personas, TipoCobro = (TipoCobroHospedaje)tipo_cobro, PrecioUnitario = (decimal)precio_unitario,
            CheckInUtc = DateTime.Parse(check_in_utc, null, Iso),
            CheckOutUtc = string.IsNullOrEmpty(check_out_utc) ? null : DateTime.Parse(check_out_utc, null, Iso),
            Unidades = (decimal)unidades, MontoHospedaje = (decimal)monto_hospedaje,
            MontoConsumos = (decimal)monto_consumos, Total = (decimal)total, MetodoPago = (int)metodo_pago,
            Estado = (EstadoEstadia)estado, Notas = notas, OrigenCajaId = origen_caja_id,
            CreadoUtc = DateTime.Parse(created_utc, null, Iso),
            ActualizadoUtc = DateTime.Parse(updated_utc, null, Iso)
        };
    }

    private sealed class FilaConsumo
    {
        public string id { get; set; } = "";
        public string estadia_id { get; set; } = "";
        public string? producto_id { get; set; }
        public string descripcion { get; set; } = "";
        public double cantidad { get; set; }
        public double precio_unitario { get; set; }
        public string fecha_hora_utc { get; set; } = "";
        public string origen_caja_id { get; set; } = "";
        public string created_utc { get; set; } = "";
        public string updated_utc { get; set; } = "";

        public ConsumoHabitacion AConsumo() => new()
        {
            Id = Guid.Parse(id), EstadiaId = Guid.Parse(estadia_id),
            ProductoId = string.IsNullOrEmpty(producto_id) ? null : Guid.Parse(producto_id),
            Descripcion = descripcion, Cantidad = (decimal)cantidad, PrecioUnitario = (decimal)precio_unitario,
            FechaHoraUtc = DateTime.Parse(fecha_hora_utc, null, Iso), OrigenCajaId = origen_caja_id,
            CreadoUtc = DateTime.Parse(created_utc, null, Iso),
            ActualizadoUtc = DateTime.Parse(updated_utc, null, Iso)
        };
    }
}
