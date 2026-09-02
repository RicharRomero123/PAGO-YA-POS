"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { api } from "@/lib/api";
import type { LicenciaGenerada, LicenciaResumen } from "@/lib/types";
import NewLicenseModal from "./NewLicenseModal";

const PLAN_NOMBRE: Record<string, string> = {
  base: "Base",
  cloud: "Cloud",
  facturador: "Facturador Pro",
};

export default function Dashboard({
  usuario,
  onLogout,
  notify,
}: {
  usuario: string;
  onLogout: () => void;
  notify: (msg: string) => void;
}) {
  const [licencias, setLicencias] = useState<LicenciaResumen[]>([]);
  const [estado, setEstado] = useState("");
  const [busqueda, setBusqueda] = useState("");
  const [modalNueva, setModalNueva] = useState(false);
  const [generada, setGenerada] = useState<LicenciaGenerada | null>(null);

  const cargar = useCallback(async () => {
    try {
      const q = estado ? `?estado=${encodeURIComponent(estado)}&limite=500` : "?limite=500";
      setLicencias(await api<LicenciaResumen[]>("/admin/licenses" + q));
    } catch (e) {
      if (e instanceof Error && "status" in e && (e as { status: number }).status === 401) onLogout();
      else notify(e instanceof Error ? e.message : "Error al cargar");
    }
  }, [estado, onLogout, notify]);

  useEffect(() => {
    cargar();
  }, [cargar]);

  const filtradas = useMemo(() => {
    const f = busqueda.trim().toLowerCase();
    if (!f) return licencias;
    return licencias.filter((l) =>
      [l.nombreNegocio, l.ruc, l.claveLicencia].some((v) => (v || "").toLowerCase().includes(f))
    );
  }, [licencias, busqueda]);

  async function cambiarEstado(l: LicenciaResumen, accion: "suspend" | "reactivate") {
    if (accion === "suspend" && !confirm(`¿Suspender la licencia de ${l.nombreNegocio || l.claveLicencia}?`))
      return;
    try {
      await api(`/admin/licenses/${l.id}/${accion}`, { method: "POST" });
      notify(accion === "suspend" ? "Licencia suspendida" : "Licencia reactivada");
      cargar();
    } catch (e) {
      notify(e instanceof Error ? e.message : "Error");
    }
  }

  function copiar(txt: string) {
    navigator.clipboard?.writeText(txt).then(() => notify("Clave copiada")).catch(() => {});
  }

  function copiarTexto(txt: string, label: string) {
    navigator.clipboard?.writeText(txt).then(() => notify(label)).catch(() => {});
  }

  function descargarLic(token: string, nombre: string) {
    const slug = (nombre || "pagoya").trim().replace(/\s+/g, "-").toLowerCase() || "pagoya";
    const blob = new Blob([token], { type: "text/plain" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `licencia-${slug}.lic`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }

  function fecha(iso: string) {
    try {
      return new Date(iso).toLocaleDateString("es-PE", { day: "2-digit", month: "short", year: "numeric" });
    } catch {
      return iso;
    }
  }

  const waTokenLink = (token: string, nombre: string) =>
    "https://wa.me/?text=" +
    encodeURIComponent(
      `¡Hola${nombre ? " " + nombre : ""}! Aquí está tu licencia de PagoYa. Ábrela en "Activar Licencia" y pega este token (o guárdalo como archivo .lic e impórtalo):\n\n${token}`
    );

  const waClaveLink = (clave: string, nombre: string) =>
    "https://wa.me/?text=" +
    encodeURIComponent(
      `¡Hola${nombre ? " " + nombre : ""}! Tu clave de licencia PagoYa es:\n\n${clave}\n\n(Envíame el código de equipo/HWID de tu PagoYa para generarte el token de activación.)`
    );

  return (
    <section className="panel">
      <header className="topbar">
        <div className="brand small">
          <span className="brand-dot">P</span>
          <strong>PagoYa · Licencias</strong>
        </div>
        <div className="topbar-right">
          <span className="muted">{usuario}</span>
          <button className="btn btn-ghost" onClick={onLogout}>
            Salir
          </button>
        </div>
      </header>

      <main className="contenido">
        <div className="toolbar">
          <button className="btn btn-primary" onClick={() => setModalNueva(true)}>
            + Nueva licencia
          </button>
          <div className="toolbar-filtros">
            <input
              type="search"
              placeholder="Buscar por cliente, RUC o clave…"
              value={busqueda}
              onChange={(e) => setBusqueda(e.target.value)}
            />
            <select value={estado} onChange={(e) => setEstado(e.target.value)}>
              <option value="">Todos los estados</option>
              <option value="Emitida">Emitida</option>
              <option value="Activa">Activa</option>
              <option value="Suspendida">Suspendida</option>
              <option value="Expirada">Expirada</option>
              <option value="Revocada">Revocada</option>
            </select>
            <button className="btn btn-ghost" onClick={cargar} title="Refrescar">
              ↻
            </button>
          </div>
        </div>

        <div className="tabla-wrap">
          <table className="tabla">
            <thead>
              <tr>
                <th>Cliente</th>
                <th>Plan</th>
                <th>Clave de licencia</th>
                <th>Estado</th>
                <th>Equipo (HWID)</th>
                <th>Creada</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {filtradas.map((l) => (
                <tr key={l.id}>
                  <td>
                    <div className="cliente-nombre">{l.nombreNegocio || "(sin nombre)"}</div>
                    <div className="cliente-ruc">
                      {l.ruc ? "RUC " + l.ruc : l.canalVenta || ""}
                    </div>
                  </td>
                  <td>
                    <span className="badge badge-plan">{PLAN_NOMBRE[l.tier] || l.tier}</span>
                  </td>
                  <td>
                    <button className="clave-code" title="Clic para copiar" onClick={() => copiar(l.claveLicencia)}>
                      {l.claveLicencia}
                    </button>
                  </td>
                  <td>
                    <span className={"badge badge-" + l.estado}>{l.estado}</span>
                  </td>
                  <td>
                    {l.hwidActual ? (
                      <span className="hwid-si" title={l.hwidActual}>
                        ● Vinculado
                      </span>
                    ) : (
                      <span className="hwid-no">— Libre</span>
                    )}
                  </td>
                  <td className="muted">{fecha(l.creadoUtc)}</td>
                  <td>
                    {l.estado === "Revocada" ? (
                      <span className="muted">—</span>
                    ) : l.estado === "Suspendida" ? (
                      <button className="btn btn-ghost btn-sm" onClick={() => cambiarEstado(l, "reactivate")}>
                        Reactivar
                      </button>
                    ) : (
                      <button className="btn btn-danger btn-sm" onClick={() => cambiarEstado(l, "suspend")}>
                        Suspender
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {licencias.length === 0 && (
            <p className="vacia">Aún no has emitido licencias. Crea la primera con “Nueva licencia”.</p>
          )}
        </div>
      </main>

      {modalNueva && (
        <NewLicenseModal
          onClose={() => setModalNueva(false)}
          onGenerada={(r) => {
            setModalNueva(false);
            setGenerada(r);
            cargar();
          }}
        />
      )}

      {generada && (
        <div className="modal" onClick={(e) => e.target === e.currentTarget && setGenerada(null)}>
          <div className="modal-card">
            <div className="modal-head">
              <h3>{generada.token ? "✅ Token generado" : "✅ Clave generada"}</h3>
              <button className="btn-cerrar" onClick={() => setGenerada(null)}>
                ✕
              </button>
            </div>

            {generada.token ? (
              <>
                <p className="muted">
                  Envía este <strong>token</strong> al cliente. En su PagoYa: <strong>Activar Licencia</strong> →
                  pega el token (o guárdalo como <code>.lic</code> e importa). Funciona sin internet y solo en el
                  equipo cuyo HWID usaste.
                  {generada.esPerpetua ? " Licencia perpetua (no vence)." : ""}
                </p>
                <textarea
                  readOnly
                  value={generada.token}
                  onFocus={(e) => e.currentTarget.select()}
                  style={{
                    width: "100%",
                    minHeight: 130,
                    fontFamily: "monospace",
                    fontSize: 12,
                    lineHeight: 1.5,
                    padding: 10,
                    borderRadius: 8,
                    border: "1px solid #d1d5db",
                    background: "#f8fafc",
                    resize: "vertical",
                    boxSizing: "border-box",
                  }}
                />
                <div className="modal-acciones" style={{ flexWrap: "wrap", gap: 8 }}>
                  <button
                    className="btn btn-primary"
                    onClick={() => copiarTexto(generada.token!, "Token copiado")}
                  >
                    Copiar token
                  </button>
                  <button
                    className="btn btn-ghost"
                    onClick={() => descargarLic(generada.token!, generada.nombre)}
                  >
                    Descargar .lic
                  </button>
                  <a
                    className="btn btn-ghost"
                    href={waTokenLink(generada.token, generada.nombre)}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    Enviar por WhatsApp
                  </a>
                  <button className="btn btn-ghost" onClick={() => setGenerada(null)}>
                    Cerrar
                  </button>
                </div>
              </>
            ) : (
              <>
                <p className="muted">
                  Se creó la <strong>clave</strong>, pero <strong>no ingresaste el HWID</strong>, así que aún no
                  hay token para activar sin internet. Pide al cliente su <strong>código de equipo (HWID)</strong> y
                  vuelve a “Nueva licencia” con ese HWID para generar el token.
                </p>
                <div className="clave-box">
                  <code>{generada.clave}</code>
                  <button className="btn btn-ghost" onClick={() => copiar(generada.clave)}>
                    Copiar
                  </button>
                </div>
                <div className="modal-acciones">
                  <a
                    className="btn btn-primary"
                    href={waClaveLink(generada.clave, generada.nombre)}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    Pedir HWID por WhatsApp
                  </a>
                  <button className="btn btn-ghost" onClick={() => setGenerada(null)}>
                    Cerrar
                  </button>
                </div>
              </>
            )}
          </div>
        </div>
      )}
    </section>
  );
}
