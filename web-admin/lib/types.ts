// Tipos que reflejan los DTOs del backend (JSON camelCase).

export interface SetupEstado {
  necesitaSetup: boolean;
}

export interface Sesion {
  token: string;
  usuario: string;
  expiraUtc: string;
}

export type Tier = "base" | "cloud" | "facturador";

export interface LicenciaResumen {
  id: string;
  claveLicencia: string;
  tier: Tier;
  features: string[];
  estado: "Emitida" | "Activa" | "Suspendida" | "Expirada" | "Revocada";
  nombreNegocio?: string | null;
  ruc?: string | null;
  notas?: string | null;
  canalVenta?: string | null;
  hwidActual?: string | null;
  trasladosUsados: number;
  maxTraslados: number;
  expUnix: number;
  creadoUtc: string;
}

export interface EmitirLicenciaResponse {
  licenciaId: string;
  claveLicencia: string;
  tier: string;
  features: string[];
  expUnix: number;
  estado: string;
}

export interface NuevaLicencia {
  nombreNegocio?: string | null;
  ruc?: string | null;
  tier: Tier;
  canalVenta?: string;
  hwid?: string | null;
  notas?: string | null;
  diasVigencia?: number;
}

// Respuesta de POST /activate: el TOKEN firmado que el cliente pega en su PC (offline).
export interface TokenResponse {
  token: string;
  tier: string;
  features: string[];
  expUnix: number;
  esPerpetua: boolean;
}

// Resultado que el modal entrega al Dashboard tras generar.
export interface LicenciaGenerada {
  clave: string;
  token: string | null; // null si no se dio HWID (no se pudo firmar el token)
  nombre: string;
  esPerpetua: boolean;
}
