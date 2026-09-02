/* PagoYa · Panel de licencias — lógica del cliente (vanilla JS). */
(() => {
    "use strict";

    const TOKEN_KEY = "pagoya_admin_token";
    let modoRegistro = false;      // true = crear cuenta admin (bootstrap)
    let licencias = [];            // cache de la última carga (para filtrar en cliente)

    const $ = (id) => document.getElementById(id);
    const token = () => localStorage.getItem(TOKEN_KEY);

    // -------- Helpers de red --------
    async function api(ruta, opciones = {}) {
        const headers = Object.assign({ "Content-Type": "application/json" }, opciones.headers || {});
        const t = token();
        if (t) headers["X-Admin-Token"] = t;
        const resp = await fetch(ruta, Object.assign({}, opciones, { headers }));
        let cuerpo = null;
        try { cuerpo = await resp.json(); } catch { /* sin cuerpo */ }
        if (!resp.ok) {
            const msg = (cuerpo && (cuerpo.error || cuerpo.Error)) || `Error ${resp.status}`;
            const err = new Error(msg);
            err.status = resp.status;
            throw err;
        }
        return cuerpo;
    }

    function toast(texto) {
        const el = $("toast");
        el.textContent = texto;
        el.classList.remove("hidden");
        clearTimeout(toast._t);
        toast._t = setTimeout(() => el.classList.add("hidden"), 2200);
    }

    // -------- Arranque --------
    async function iniciar() {
        // Si hay token guardado, intentamos entrar directo al panel.
        if (token()) {
            try {
                await cargarLicencias();
                mostrarPanel();
                return;
            } catch (e) {
                if (e.status === 401) localStorage.removeItem(TOKEN_KEY);
            }
        }
        // Sin sesión: decidir registro vs login según el bootstrap.
        try {
            const est = await api("/admin/auth/setup-estado");
            modoRegistro = est.necesitaSetup === true;
        } catch { modoRegistro = false; }
        pintarAuth();
        mostrarAuth();
    }

    function pintarAuth() {
        $("auth-titulo").textContent = modoRegistro ? "Crea tu cuenta de administrador" : "Iniciar sesión";
        $("auth-sub").textContent = modoRegistro
            ? "Es la primera vez. Define el usuario y contraseña con los que gestionarás las licencias."
            : "Ingresa con tu cuenta de administrador.";
        $("btn-auth").textContent = modoRegistro ? "Crear cuenta" : "Entrar";
    }

    // -------- Auth --------
    $("form-auth").addEventListener("submit", async (ev) => {
        ev.preventDefault();
        const usuario = $("in-usuario").value.trim();
        const password = $("in-password").value;
        const errBox = $("auth-error");
        errBox.classList.add("hidden");
        $("btn-auth").disabled = true;
        try {
            const ruta = modoRegistro ? "/admin/auth/registro" : "/admin/auth/login";
            const r = await api(ruta, { method: "POST", body: JSON.stringify({ usuario, password }) });
            localStorage.setItem(TOKEN_KEY, r.token);
            $("in-password").value = "";
            await cargarLicencias();
            mostrarPanel();
        } catch (e) {
            errBox.textContent = e.message;
            errBox.classList.remove("hidden");
        } finally {
            $("btn-auth").disabled = false;
        }
    });

    $("btn-logout").addEventListener("click", async () => {
        try { await api("/admin/auth/logout", { method: "POST" }); } catch { /* ignore */ }
        localStorage.removeItem(TOKEN_KEY);
        await iniciar();
    });

    // -------- Vistas --------
    function mostrarAuth() { $("vista-auth").classList.remove("hidden"); $("vista-panel").classList.add("hidden"); }
    function mostrarPanel() { $("vista-auth").classList.add("hidden"); $("vista-panel").classList.remove("hidden"); }

    // -------- Licencias --------
    async function cargarLicencias() {
        const estado = $("sel-estado").value;
        const q = estado ? `?estado=${encodeURIComponent(estado)}&limite=500` : "?limite=500";
        licencias = await api("/admin/licenses" + q);
        renderTabla();
    }

    function renderTabla() {
        const filtro = $("in-buscar").value.trim().toLowerCase();
        const filas = licencias.filter((l) => {
            if (!filtro) return true;
            return [l.nombreNegocio, l.ruc, l.claveLicencia].some(
                (v) => (v || "").toLowerCase().includes(filtro));
        });

        const tbody = $("tbody-licencias");
        tbody.innerHTML = "";
        $("tabla-vacia").classList.toggle("hidden", licencias.length !== 0);

        for (const l of filas) {
            const tr = document.createElement("tr");
            tr.innerHTML = `
                <td>
                    <div class="cliente-nombre">${esc(l.nombreNegocio || "(sin nombre)")}</div>
                    <div class="cliente-ruc">${l.ruc ? "RUC " + esc(l.ruc) : (l.canalVenta ? esc(l.canalVenta) : "")}</div>
                </td>
                <td><span class="badge badge-plan">${planNombre(l.tier)}</span></td>
                <td class="clave"><code title="Clic para copiar">${esc(l.claveLicencia)}</code></td>
                <td><span class="badge ${esc(l.estado)}">${esc(l.estado)}</span></td>
                <td>${l.hwidActual
                    ? `<span class="hwid-si" title="${esc(l.hwidActual)}">● Vinculado</span>`
                    : `<span class="hwid-no">— Libre</span>`}</td>
                <td class="muted">${fecha(l.creadoUtc)}</td>
                <td>${accionesHtml(l)}</td>`;

            tr.querySelector("code").addEventListener("click", () => {
                copiar(l.claveLicencia); toast("Clave copiada");
            });
            const btnAcc = tr.querySelector("[data-accion]");
            if (btnAcc) btnAcc.addEventListener("click", () => cambiarEstado(l, btnAcc.dataset.accion));
            tbody.appendChild(tr);
        }
    }

    function accionesHtml(l) {
        if (l.estado === "Revocada") return `<span class="muted">—</span>`;
        if (l.estado === "Suspendida")
            return `<button class="btn btn-ghost btn-sm" data-accion="reactivate">Reactivar</button>`;
        return `<button class="btn btn-danger btn-sm" data-accion="suspend">Suspender</button>`;
    }

    async function cambiarEstado(l, accion) {
        const verbo = accion === "suspend" ? "suspender" : "reactivar";
        if (accion === "suspend" && !confirm(`¿Suspender la licencia de ${l.nombreNegocio || l.claveLicencia}? El cliente no podrá revalidar.`))
            return;
        try {
            await api(`/admin/licenses/${l.id}/${accion}`, { method: "POST" });
            toast(`Licencia ${verbo === "suspender" ? "suspendida" : "reactivada"}`);
            await cargarLicencias();
        } catch (e) { toast(e.message); }
    }

    $("btn-refrescar").addEventListener("click", () => cargarLicencias().catch((e) => toast(e.message)));
    $("sel-estado").addEventListener("change", () => cargarLicencias().catch((e) => toast(e.message)));
    $("in-buscar").addEventListener("input", renderTabla);

    // -------- Nueva licencia --------
    $("btn-nueva").addEventListener("click", () => abrirModal("modal-nueva"));

    $("form-nueva").addEventListener("submit", async (ev) => {
        ev.preventDefault();
        const errBox = $("nueva-error");
        errBox.classList.add("hidden");
        const body = {
            nombreNegocio: valOrNull("n-nombre"),
            ruc: valOrNull("n-ruc"),
            tier: $("n-tier").value,
            canalVenta: $("n-canal").value,
            hwid: valOrNull("n-hwid"),
            notas: valOrNull("n-notas"),
        };
        const dias = $("n-dias").value.trim();
        if (dias) body.diasVigencia = parseInt(dias, 10);
        try {
            const r = await api("/licenses", { method: "POST", body: JSON.stringify(body) });
            cerrarModal("modal-nueva");
            $("form-nueva").reset();
            mostrarClave(r.claveLicencia, body.nombreNegocio);
            await cargarLicencias();
        } catch (e) {
            errBox.textContent = e.message;
            errBox.classList.remove("hidden");
        }
    });

    function mostrarClave(clave, nombre) {
        $("clave-generada").textContent = clave;
        const texto = `¡Hola${nombre ? " " + nombre : ""}! Aquí está tu licencia de PagoYa:\n\n${clave}\n\nActívala en Configuración → Activar licencia.`;
        $("btn-whatsapp").href = "https://wa.me/?text=" + encodeURIComponent(texto);
        $("btn-copiar-clave").onclick = () => { copiar(clave); toast("Clave copiada"); };
        abrirModal("modal-clave");
    }

    // -------- Modales --------
    function abrirModal(id) { $(id).classList.remove("hidden"); }
    function cerrarModal(id) { $(id).classList.add("hidden"); }
    document.querySelectorAll("[data-cerrar]").forEach((b) =>
        b.addEventListener("click", () => cerrarModal(b.dataset.cerrar)));
    document.querySelectorAll(".modal").forEach((m) =>
        m.addEventListener("click", (e) => { if (e.target === m) m.classList.add("hidden"); }));

    // -------- Utilidades --------
    function valOrNull(id) { const v = $(id).value.trim(); return v || null; }
    function esc(s) { return (s == null ? "" : String(s)).replace(/[&<>"']/g, (c) =>
        ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])); }
    function planNombre(t) { return t === "facturador" ? "Facturador Pro" : t === "cloud" ? "Cloud" : "Base"; }
    function fecha(iso) { try { return new Date(iso).toLocaleDateString("es-PE", { day: "2-digit", month: "short", year: "numeric" }); } catch { return iso; } }
    function copiar(txt) {
        if (navigator.clipboard) navigator.clipboard.writeText(txt).catch(() => {});
        else { const ta = document.createElement("textarea"); ta.value = txt; document.body.appendChild(ta); ta.select(); document.execCommand("copy"); ta.remove(); }
    }

    iniciar();
})();
