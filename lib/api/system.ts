import { getAuthHeaders } from "./config";

function normalizeAdminBase(raw?: string, fallback = 'usermanagementapi.techretainer.com') {
  const val = raw || fallback
  return val.startsWith('http://') || val.startsWith('https://') ? val : `https://${val}`
}

const API_BASE_URL = normalizeAdminBase(
  process.env.NEXT_PUBLIC_LOGIN_API_URL || process.env.NEXT_PUBLIC_ADMIN_API_URL
)

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
  const res = await fetch(`${API_BASE_URL}/api/System/farms`, {
    headers: {
      ...getAuthHeaders(),
    },
    cache: "no-store",
  });
  return json<FarmSummary[]>(res).catch(() => []);
}

export async function getFarmCount(): Promise<number> {
  const res = await fetch(`${API_BASE_URL}/api/System/farms/count`, {
    headers: {
      ...getAuthHeaders(),
    },
    cache: "no-store",
  });
  const data = await json<{ count: number }>(res).catch(() => ({ count: 0 }));
  return data?.count ?? 0;
}


