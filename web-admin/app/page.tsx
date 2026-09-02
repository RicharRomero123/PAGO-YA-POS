"use client";

import { useCallback, useEffect, useState } from "react";
import { api, clearToken, getToken } from "@/lib/api";
import type { SetupEstado } from "@/lib/types";
import Login from "@/components/Login";
import Dashboard from "@/components/Dashboard";

type Vista = "cargando" | "auth" | "panel";

export default function Home() {
  const [vista, setVista] = useState<Vista>("cargando");
  const [modoSetup, setModoSetup] = useState(false);
  const [toast, setToast] = useState<string | null>(null);

  const notify = useCallback((msg: string) => {
    setToast(msg);
    window.setTimeout(() => setToast(null), 2200);
  }, []);

  const iniciar = useCallback(async () => {
    // Con token guardado, intentamos entrar directo (validando contra el backend).
    if (getToken()) {
      try {
        await api("/admin/licenses?limite=1");
        setVista("panel");
        return;
      } catch {
        clearToken();
      }
    }
    try {
      const est = await api<SetupEstado>("/admin/auth/setup-estado");
      setModoSetup(est.necesitaSetup === true);
    } catch {
      setModoSetup(false);
    }
    setVista("auth");
  }, []);

  useEffect(() => {
    iniciar();
  }, [iniciar]);

  async function logout() {
    try {
      await api("/admin/auth/logout", { method: "POST" });
    } catch {
      /* ignore */
    }
    clearToken();
    setVista("cargando");
    iniciar();
  }

  return (
    <>
      {vista === "cargando" && (
        <div style={{ display: "grid", placeItems: "center", minHeight: "100vh", color: "#6b7280" }}>
          Cargando…
        </div>
      )}
      {vista === "auth" && <Login modoSetup={modoSetup} onSuccess={() => setVista("panel")} />}
      {vista === "panel" && <Dashboard usuario="Administrador" onLogout={logout} notify={notify} />}
      {toast && <div className="toast">{toast}</div>}
    </>
  );
}
