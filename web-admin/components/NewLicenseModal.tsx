"use client";

import { useState } from "react";
import { api } from "@/lib/api";
import type {
  EmitirLicenciaResponse,
  LicenciaGenerada,
  NuevaLicencia,
  Tier,
  TokenResponse,
} from "@/lib/types";

export default function NewLicenseModal({
  onClose,
  onGenerada,
}: {
  onClose: () => void;
  onGenerada: (r: LicenciaGenerada) => void;
}) {
  const [nombre, setNombre] = useState("");
  const [ruc, setRuc] = useState("");
  const [tier, setTier] = useState<Tier>("base");
  const [dias, setDias] = useState("");
  const [canal, setCanal] = useState("whatsapp");
  const [hwid, setHwid] = useState("");
  const [notas, setNotas] = useState("");
  const [error, setError] = useState("");
  const [ocupado, setOcupado] = useState(false);

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setOcupado(true);
    const h = hwid.trim();
    const body: NuevaLicencia = {
      nombreNegocio: nombre.trim() || null,
      ruc: ruc.trim() || null,
      tier,
      canalVenta: canal,
      hwid: h || null,
      notas: notas.trim() || null,
    };
    if (dias.trim()) body.diasVigencia = parseInt(dias, 10);
    try {
      // 1) Emitir la licencia (crea el registro y devuelve la clave).
      const r = await api<EmitirLicenciaResponse>("/licenses", {
        method: "POST",
        body: JSON.stringify(body),
      });

      // 2) Si tenemos el HWID del cliente, generamos el TOKEN firmado que
      //    él pega/importa en su PC (activación offline, sin internet).
      let token: string | null = null;
      let esPerpetua = tier === "base" && !dias.trim();
      if (h) {
        const t = await api<TokenResponse>("/activate", {
          method: "POST",
          body: JSON.stringify({ licenseKey: r.claveLicencia, hwid: h }),
        });
        token = t.token;
        esPerpetua = t.esPerpetua;
      }
      onGenerada({ clave: r.claveLicencia, token, nombre: nombre.trim(), esPerpetua });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Error inesperado");
    } finally {
      setOcupado(false);
    }
  }

  return (
    <div className="modal" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal-card">
        <div className="modal-head">
          <h3>Generar licencia</h3>
          <button className="btn-cerrar" onClick={onClose}>
            ✕
          </button>
        </div>
        <form onSubmit={enviar}>
          {/* HWID primero: es lo que el cliente te pasa para atar la licencia a su PC */}
          <label>Código de equipo del cliente (HWID)</label>
          <input
            value={hwid}
            onChange={(e) => setHwid(e.target.value)}
            placeholder="Pega aquí el HWID que te envió el cliente"
            style={{ fontFamily: "monospace" }}
          />
          <p className="muted" style={{ marginTop: 4, fontSize: 12.5 }}>
            Con el HWID se genera el <strong>token firmado</strong> que el cliente pega o importa en su PC
            (funciona sin internet y solo en ese equipo). Si lo dejas vacío, solo se crea la clave.
          </p>

          <div className="grid2">
            <div>
              <label>Plan</label>
              <select value={tier} onChange={(e) => setTier(e.target.value as Tier)}>
                <option value="base">Base — pago único (offline)</option>
                <option value="cloud">Cloud — S/ 25 / mes</option>
                <option value="facturador">Facturador Pro — S/ 50–70 / mes</option>
              </select>
            </div>
            <div>
              <label>
                Vigencia (días) <span className="muted">— solo suscripción</span>
              </label>
              <input
                type="number"
                min={1}
                value={dias}
                onChange={(e) => setDias(e.target.value)}
                placeholder="Base = sin vencimiento"
              />
            </div>
          </div>

          <div className="grid2">
            <div>
              <label>Nombre del cliente / negocio</label>
              <input value={nombre} onChange={(e) => setNombre(e.target.value)} placeholder="Bodega Doña Rosa" />
            </div>
            <div>
              <label>RUC (opcional)</label>
              <input value={ruc} onChange={(e) => setRuc(e.target.value)} placeholder="20512345678" />
            </div>
          </div>

          <div className="grid2">
            <div>
              <label>Canal de venta</label>
              <select value={canal} onChange={(e) => setCanal(e.target.value)}>
                <option value="whatsapp">WhatsApp</option>
                <option value="facebook">Facebook</option>
                <option value="otro">Otro</option>
              </select>
            </div>
            <div>
              <label>Notas internas (opcional)</label>
              <input value={notas} onChange={(e) => setNotas(e.target.value)} placeholder="Pago Yape confirmado" />
            </div>
          </div>

          {error && <p className="error-msg">{error}</p>}
          <div className="modal-acciones">
            <button type="button" className="btn btn-ghost" onClick={onClose}>
              Cancelar
            </button>
            <button type="submit" className="btn btn-primary" disabled={ocupado}>
              {ocupado ? "Generando…" : hwid.trim() ? "Generar token" : "Generar clave"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
