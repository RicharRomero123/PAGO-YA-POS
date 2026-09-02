// Cliente HTTP tipado contra el backend de licencias (ASP.NET Core).
// Auth por token de sesión admin en cabecera X-Admin-Token (guardado en localStorage).

export const API_BASE =
  process.env.NEXT_PUBLIC_API_BASE || "http://localhost:5080";

const TOKEN_KEY = "pagoya_admin_token";

export const getToken = (): string | null =>
  typeof window !== "undefined" ? localStorage.getItem(TOKEN_KEY) : null;
export const setToken = (t: string) => localStorage.setItem(TOKEN_KEY, t);
export const clearToken = () => localStorage.removeItem(TOKEN_KEY);

export class ApiError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

export async function api<T = unknown>(
  path: string,
  opts: RequestInit = {}
): Promise<T> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...((opts.headers as Record<string, string>) || {}),
  };
  const token = getToken();
  if (token) headers["X-Admin-Token"] = token;

  const res = await fetch(API_BASE + path, { ...opts, headers });
  let body: unknown = null;
  try {
    body = await res.json();
  } catch {
    /* respuesta sin cuerpo */
  }
  if (!res.ok) {
    const b = body as { error?: string; Error?: string } | null;
    throw new ApiError(b?.error || b?.Error || `Error ${res.status}`, res.status);
  }
  return body as T;
}
