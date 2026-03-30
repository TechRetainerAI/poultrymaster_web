function normalizeApiBase(raw?: string, fallback = 'farmapi.techretainer.com') {
  const val = raw || fallback
  return val.startsWith('http://') || val.startsWith('https://') ? val : `https://${val}`
}

const API_BASE_URL = normalizeApiBase(process.env.NEXT_PUBLIC_API_BASE_URL)

export interface EggProduction {
  productionId: number;
  farmId: string;
  userId: string;
  flockId: number;
  flockName?: string;
  productionDate: string;
  eggCount: number;
  production9AM: number;
  production12PM: number;
  production4PM: number;
  totalProduction: number;
  brokenEggs: number;
  notes: string;
}

export interface ApiResponse<T = any> {
  success: boolean;
  data?: T;
  message?: string;
  errors?: string[];
}

export async function getEggProductions(userId?: string, farmId?: string): Promise<ApiResponse<EggProduction[]>> {
  try {
    const params = new URLSearchParams();
    if (userId) params.append('userId', userId);
    if (farmId) params.append('farmId', farmId);
    
    // Use proxy to avoid CORS issues
    const url = `/api/proxy/EggProduction?${params.toString()}`;
    console.log("[v0] Fetching egg productions:", url);

    const response = await fetch(url, {
      method: "GET",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
    });

    console.log("[v0] Egg productions response status:", response.status);

    if (!response.ok) {
      const errorText = await response.text();
      console.error("[v0] Egg productions fetch error:", errorText);
      return {
        success: false,
        message: "Failed to fetch egg productions",
        data: [],
      };
    }

    const data = await response.json();
    console.log("[v0] Egg productions data received:", data);

    return {
      success: true,
      message: "Egg productions fetched successfully",
      data: data as EggProduction[],
    };
    } catch (error) {
      console.error("[v0] Egg productions fetch error:", error);
      return {
        success: false,
        message: "Failed to fetch egg productions",
        data: [],
      };
    }
  }
  
  export async function deleteEggProduction(productionId: number, userId: string, farmId: string): Promise<ApiResponse> {
    try {
      const params = new URLSearchParams();
      params.append('userId', userId);
      params.append('farmId', farmId);
  
      // Use proxy to avoid CORS issues
      const url = `/api/proxy/EggProduction/${productionId}?${params.toString()}`;
      console.log("[v0] Deleting egg production:", url);
  
      const response = await fetch(url, {
        method: "DELETE",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
        },
      });
  
      console.log("[v0] Egg production delete response status:", response.status);
  
      if (!response.ok) {
        const errorText = await response.text();
        console.error("[v0] Egg production delete error:", errorText);
        return {
          success: false,
          message: "Failed to delete egg production",
        };
      }
  
      return {
        success: true,
        message: "Egg production deleted successfully",
      };
    } catch (error) {
      console.error("[v0] Egg production delete error:", error);
      return {
        success: false,
        message: "Failed to delete egg production",
      };
    }
  }

export interface EggProductionInput {
  farmId: string;
  userId: string;
  flockId: number;
  productionDate: string;
  eggCount: number;
  production9AM: number;
  production12PM: number;
  production4PM: number;
  totalProduction: number;
  brokenEggs: number;
  notes: string;
}

export async function createEggProduction(eggProduction: EggProductionInput): Promise<ApiResponse<EggProduction>> {
  try {
    // Use proxy to avoid CORS issues
    const url = `/api/proxy/EggProduction`;
    console.log("[v0] Creating egg production:", url, eggProduction);

    const response = await fetch(url, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(eggProduction),
    });

    console.log("[v0] Egg production creation response status:", response.status);

    if (!response.ok) {
      const errorText = await response.text();
      console.error("[v0] Egg production creation error:", errorText);
      return {
        success: false,
        message: "Failed to create egg production",
      };
    }

    const data = await response.json();
    console.log("[v0] Egg production created successfully:", data);

    return {
      success: true,
      message: "Egg production created successfully",
      data: data as EggProduction,
    };
  } catch (error) {
    console.error("[v0] Egg production creation error:", error);
        return {
          success: false,
          message: "Failed to create egg production",
        };
      }
    }
    
    export async function getEggProduction(id: number, userId: string, farmId: string): Promise<ApiResponse<EggProduction>> {
      try {
        const params = new URLSearchParams();
        params.append('userId', userId);
        params.append('farmId', farmId);
    
        // Use proxy to avoid CORS issues
        const url = `/api/proxy/EggProduction/${id}?${params.toString()}`;
        console.log("[v0] Fetching egg production:", url);
    
        const response = await fetch(url, {
          method: "GET",
          headers: {
            Accept: "application/json",
            "Content-Type": "application/json",
          },
        });
    
        console.log("[v0] Egg production fetch response status:", response.status);
    
        if (!response.ok) {
          const errorText = await response.text();
          console.error("[v0] Egg production fetch error:", errorText);
          return {
            success: false,
            message: "Failed to fetch egg production",
          };
        }
    
        const data = await response.json();
        console.log("[v0] Egg production data received:", data);
    
        return {
          success: true,
          message: "Egg production fetched successfully",
          data: data as EggProduction,
        };
      } catch (error) {
        console.error("[v0] Egg production fetch error:", error);
        return {
          success: false,
          message: "Failed to fetch egg production",
        };
      }
    }
    
    export async function updateEggProduction(id: number, eggProduction: Partial<EggProductionInput>): Promise<ApiResponse> {
      try {
        // Use proxy to avoid CORS issues
        const url = `/api/proxy/EggProduction/${id}`;
        console.log("[v0] Updating egg production:", url, eggProduction);
    
        const response = await fetch(url, {
          method: "PUT",
          headers: {
            Accept: "application/json",
            "Content-Type": "application/json",
          },
          body: JSON.stringify(eggProduction),
        });
    
        console.log("[v0] Egg production update response status:", response.status);
    
        if (!response.ok) {
          const errorText = await response.text();
          console.error("[v0] Egg production update error:", errorText);
          return {
            success: false,
            message: errorText || "Failed to update egg production",
          };
        }
    
        return {
          success: true,
          message: "Egg production updated successfully",
        };
      } catch (error) {
        console.error("[v0] Egg production update error:", error);
        return {
          success: false,
          message: "Failed to update egg production. Network error.",
        };
      }
    }