using System.Runtime.InteropServices;

namespace PagoYa.Desktop.Servicios.Impresion;

/// <summary>
/// Envía bytes CRUDOS (raw) a una impresora por el spooler de Windows, saltando
/// el driver GDI. Necesario para impresoras térmicas ESC/POS: los comandos
/// (cortar papel, negrita, alineación) son bytes de control que el driver
/// gráfico destrozaría.
///
/// Basado en el patrón oficial de Microsoft (KB322091) vía winspool.drv.
///
/// Compatibilidad: Windows 10/11. La impresora debe estar instalada como
/// impresora de Windows (driver del fabricante o "Generic / Text Only"). No
/// requiere admin. Para impresoras conectadas por USB/serie sin cola de
/// Windows, usar una variante por puerto (no incluida aquí).
/// </summary>
public static class RawPrinterHelper
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DOCINFOA
    {
        [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPWStr)] public string? pOutputFile;
        [MarshalAs(UnmanagedType.LPWStr)] public string pDataType;
    }

    [DllImport("winspool.drv", EntryPoint = "OpenPrinterW", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool OpenPrinter(string src, out IntPtr hPrinter, IntPtr pd);

    [DllImport("winspool.drv", EntryPoint = "ClosePrinter", SetLastError = true)]
    private static extern bool ClosePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", EntryPoint = "StartDocPrinterW", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool StartDocPrinter(IntPtr hPrinter, int level, ref DOCINFOA di);

    [DllImport("winspool.drv", EntryPoint = "EndDocPrinter", SetLastError = true)]
    private static extern bool EndDocPrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", EntryPoint = "StartPagePrinter", SetLastError = true)]
    private static extern bool StartPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", EntryPoint = "EndPagePrinter", SetLastError = true)]
    private static extern bool EndPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", EntryPoint = "WritePrinter", SetLastError = true)]
    private static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);

    /// <summary>
    /// Envía un buffer de bytes crudos a la impresora indicada por nombre.
    /// </summary>
    /// <param name="nombreImpresora">Nombre exacto de la impresora en Windows.</param>
    /// <param name="datos">Bytes ESC/POS a imprimir.</param>
    /// <returns>true si el spooler aceptó todos los bytes.</returns>
    public static bool EnviarBytes(string nombreImpresora, byte[] datos)
    {
        if (string.IsNullOrWhiteSpace(nombreImpresora))
            throw new ArgumentException("Nombre de impresora vacío.", nameof(nombreImpresora));

        var pUnmanagedBytes = Marshal.AllocCoTaskMem(datos.Length);
        Marshal.Copy(datos, 0, pUnmanagedBytes, datos.Length);
        try
        {
            return EnviarPunteroNoAdministrado(nombreImpresora, pUnmanagedBytes, datos.Length);
        }
        finally
        {
            Marshal.FreeCoTaskMem(pUnmanagedBytes);
        }
    }

    private static bool EnviarPunteroNoAdministrado(string nombreImpresora, IntPtr pBytes, int cuenta)
    {
        if (!OpenPrinter(nombreImpresora, out var hPrinter, IntPtr.Zero))
            return false;

        try
        {
            var di = new DOCINFOA
            {
                pDocName = "PagoYa Ticket",
                pOutputFile = null,
                pDataType = "RAW"
            };

            if (!StartDocPrinter(hPrinter, 1, ref di)) return false;
            try
            {
                if (!StartPagePrinter(hPrinter)) return false;
                try
                {
                    return WritePrinter(hPrinter, pBytes, cuenta, out var escritos) && escritos == cuenta;
                }
                finally { EndPagePrinter(hPrinter); }
            }
            finally { EndDocPrinter(hPrinter); }
        }
        finally { ClosePrinter(hPrinter); }
    }
}
