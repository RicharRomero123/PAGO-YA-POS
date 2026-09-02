"use client";

import { useState } from "react";
import { api, setToken } from "@/lib/api";
import type { Sesion } from "@/lib/types";

export default function Login({
  modoSetup,
  onSuccess,
}: {
  modoSetup: boolean;
  onSuccess: () => void;
}) {
  const [usuario, setUsuario] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [ocupado, setOcupado] = useState(false);

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setOcupado(true);
    try {
      const ruta = modoSetup ? "/admin/auth/registro" : "/admin/auth/login";
      const r = await api<Sesion>(ruta, {
        method: "POST",
        body: JSON.stringify({ usuario, password }),
      });
      setToken(r.token);
      onSuccess();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Error inesperado");
    } finally {
      setOcupado(false);
    }
  }

  return (
    <section className="auth">
      <div className="auth-card">
        <div className="brand">
          <span className="brand-dot">P</span>
          <div>
            <h1>PagoYa</h1>
            <p>Panel de administración de licencias</p>
          </div>
        </div>

        <h2>{modoSetup ? "Crea tu cuenta de administrador" : "Iniciar sesión"}</h2>
        <p className="muted">
          {modoSetup
            ? "Es la primera vez. Define el usuario y contraseña con los que gestionarás las licencias."
            : "Ingresa con tu cuenta de administrador."}
        </p>

        <form onSubmit={enviar} autoComplete="off">
          <label>Usuario</label>
          <input
            value={usuario}
            onChange={(e) => setUsuario(e.target.value)}
            placeholder="admin"
            required
          />
          <label>Contraseña</label>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="••••••••"
            required
          />
          {error && <p className="error-msg">{error}</p>}
          <button className="btn btn-primary btn-block" disabled={ocupado}>
            {ocupado ? "…" : modoSetup ? "Crear cuenta" : "Entrar"}
          </button>
        </form>
      </div>
      <p className="pie">PagoYa POS · Perú</p>
    </section>
  );
}
