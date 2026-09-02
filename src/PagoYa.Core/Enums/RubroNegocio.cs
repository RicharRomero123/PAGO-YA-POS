namespace PagoYa.Core.Enums;

/// <summary>
/// Rubro/giro del negocio. Se elige al crear la cuenta y determina la plantilla
/// precargada (categorías + productos de ejemplo) y algunos textos del POS.
/// Pensado para el mercado peruano.
/// </summary>
public enum RubroNegocio
{
    /// <summary>Bodega / minimarket (abarrotes, bebidas, snacks).</summary>
    Bodega = 0,

    /// <summary>Restaurante / cevichería / menú (entradas, platos de fondo, bebidas).</summary>
    Restaurante = 1,

    /// <summary>Cafetería / juguería (cafés, postres, sándwiches).</summary>
    Cafeteria = 2,

    /// <summary>Pollería / parrilla.</summary>
    Polleria = 3,

    /// <summary>Farmacia / botica.</summary>
    Farmacia = 4,

    /// <summary>Ferretería.</summary>
    Ferreteria = 5,

    /// <summary>Licorería.</summary>
    Licoreria = 6,

    /// <summary>Hotel / hospedaje (habitaciones, consumos).</summary>
    Hotel = 7,

    /// <summary>Otro giro (arranca vacío, sin plantilla).</summary>
    Otro = 99
}
