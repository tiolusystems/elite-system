import "server-only";

import { navigationCapabilityPaths } from "@/lib/app-navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type NavigationAccess = Record<string, boolean>;

type RouteCapabilityAccess = {
  allowed: boolean;
};

export async function getNavigationAccess(): Promise<NavigationAccess> {
  const supabase = await createSupabaseServerClient();
  const results = await Promise.all(
    navigationCapabilityPaths.map(async (pathname) => {
      const result = await supabase.rpc("get_current_route_capability_access", {
        p_pathname: pathname
      });
      const access = Array.isArray(result.data)
        ? (result.data[0] as RouteCapabilityAccess | undefined)
        : undefined;
      return [pathname, !result.error && access?.allowed === true] as const;
    })
  );

  return Object.fromEntries(results);
}
