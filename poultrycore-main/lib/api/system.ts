import { getAuthHeaders, loginApiUrl } from "./config"

export type FarmSummary = {
  farmId: string;
  farmName?: string | null;
  totalUsers: number;
  staffCount: number;
  /** True if at least one user on the farm has a paid subscription flag (Login API / Identity). */
  hasPaidSubscription?: boolean;
};

async function json<T>(res: Response): Promise<T> {
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(text || `Request failed with ${res.status}`);
  }
  if (res.status === 204) return undefined as unknown as T;
  const txt = await res.text();
  if (!txt) return undefined as unknown as T;
  return JSON.parse(txt) as T;
}

export async function getFarms(): Promise<FarmSummary[]> {
  const res = await fetch(loginApiUrl("System/farms"), {
    headers: {
      ...getAuthHeaders(),
    },
    cache: "no-store",
  });
  return json<FarmSummary[]>(res).catch(() => []);
}

export async function getFarmCount(): Promise<number> {
  const res = await fetch(loginApiUrl("System/farms/count"), {
    headers: {
      ...getAuthHeaders(),
    },
    cache: "no-store",
  });
  const data = await json<{ count: number }>(res).catch(() => ({ count: 0 }));
  return data?.count ?? 0;
}


