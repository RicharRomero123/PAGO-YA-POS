using System.Collections.ObjectModel;
using System.Linq;
using CommunityToolkit.Mvvm.ComponentModel;
using PagoYa.Core.Entidades;

namespace PagoYa.Desktop.ViewModels;

/// <summary>
/// VMs que respaldan el diálogo de personalización del <b>Cobro Rápido</b> (rubro
/// comida). Se construyen dinámicamente desde <see cref="PersonalizacionProducto"/>
/// del producto elegido: cada grupo se muestra como radios (elegir una) o checkboxes
/// (elegir varias), con el precio extra de cada opción. El VM padre (CobroRapido)
/// recalcula el precio unitario en vivo suscribiéndose a los cambios de selección.
/// </summary>
public partial class GrupoPersonalizacionVM : ObservableObject
{
    /// <summary>Callback al padre para recalcular precio/validación cuando cambia la selección.</summary>
    public Action? AlCambiarSeleccion { get; set; }

    public string Nombre { get; }

    /// <summary>true = checkboxes (varias); false = radios (una sola).</summary>
    public bool Multiple { get; }

    /// <summary>true = hay que elegir al menos una opción.</summary>
    public bool Obligatorio { get; }

    /// <summary>Nombre de grupo para el RadioButton.GroupName (único por instancia).</summary>
    public string GrupoRadio { get; } = "grp_" + Guid.NewGuid().ToString("N");

    public ObservableCollection<OpcionPersonalizacionVM> Opciones { get; } = new();

    public GrupoPersonalizacionVM(GrupoModificador grupo)
    {
        Nombre = grupo.Nombre;
        Multiple = grupo.Multiple;
        Obligatorio = grupo.Obligatorio;

        for (int i = 0; i < grupo.Opciones.Count; i++)
        {
            var op = grupo.Opciones[i];
            // En grupos obligatorios de una sola opción, preselecciona la primera.
            var sel = !Multiple && Obligatorio && i == 0;
            var vm = new OpcionPersonalizacionVM(op.Nombre, op.PrecioExtra, sel) { Padre = this };
            Opciones.Add(vm);
        }
    }

    /// <summary>Opciones actualmente elegidas por el cajero.</summary>
    public IEnumerable<OpcionPersonalizacionVM> Elegidas => Opciones.Where(o => o.Seleccionada);

    /// <summary>Suma de los precios extra de las opciones elegidas.</summary>
    public decimal ExtraElegido => Elegidas.Sum(o => o.PrecioExtra);

    /// <summary>True si el grupo es válido (obligatorio ⇒ al menos una elegida).</summary>
    public bool EsValido => !Obligatorio || Elegidas.Any();

    /// <summary>
    /// Marca una opción como elegida. En grupos de selección única deselecciona las
    /// demás (los RadioButton comparten GroupName, pero mantenemos el modelo coherente).
    /// </summary>
    internal void AlSeleccionar(OpcionPersonalizacionVM opcion)
    {
        if (!Multiple && opcion.Seleccionada)
            foreach (var o in Opciones)
                if (!ReferenceEquals(o, opcion) && o.Seleccionada)
                    o.SetSeleccionadaSilenciosa(false);

        AlCambiarSeleccion?.Invoke();
    }
}

/// <summary>Opción elegible dentro de un <see cref="GrupoPersonalizacionVM"/>.</summary>
public partial class OpcionPersonalizacionVM : ObservableObject
{
    internal GrupoPersonalizacionVM? Padre { get; set; }

    public string Nombre { get; }
    public decimal PrecioExtra { get; }

    /// <summary>True si la opción tiene costo adicional (para mostrar "+S/ x").</summary>
    public bool TieneExtra => PrecioExtra > 0;

    /// <summary>Etiqueta "+S/ 1.50" cuando hay costo; vacío si es gratis.</summary>
    public string ExtraTexto => TieneExtra ? $"+S/ {PrecioExtra:N2}" : "";

    /// <summary>Evita que la deselección en cascada (radios) reentre en la lógica del grupo.</summary>
    private bool _silencioso;

    [ObservableProperty] private bool _seleccionada;

    public OpcionPersonalizacionVM(string nombre, decimal precioExtra, bool seleccionada)
    {
        Nombre = nombre;
        PrecioExtra = precioExtra;
        Seleccionada = seleccionada;
    }

    partial void OnSeleccionadaChanged(bool value)
    {
        if (_silencioso) return;
        Padre?.AlSeleccionar(this);
    }

    /// <summary>Cambia la selección sin re-disparar la lógica del grupo (evita recursión).</summary>
    internal void SetSeleccionadaSilenciosa(bool value)
    {
        _silencioso = true;
        Seleccionada = value;
        _silencioso = false;
    }
}
