import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

const PUBLIC_ROUTES = new Set(["/login", "/health", "/api/health"]);
const TEMP_PASSWORD_CHANGE_ROUTE = "/login/trocar-senha";
const MODULE_GUARD_RECOVERY_ROUTE = "/modulo-indisponivel";

type RouteModuleAccess = {
  module_key: string | null;
  available: boolean;
  reason: string;
};

export async function proxy(request: NextRequest) {
  const pathname = request.nextUrl.pathname;

  if (isPublicPath(pathname)) {
    return NextResponse.next();
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  if (!supabaseUrl || !supabaseKey || supabaseUrl.includes("example-project")) {
    return redirectToLogin(request, "not_configured");
  }

  let response = NextResponse.next({
    request: {
      headers: request.headers
    }
  });

  const supabase = createServerClient(supabaseUrl, supabaseKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({
          request: {
            headers: request.headers
          }
        });
        cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      }
    }
  });

  const {
    data: { user },
    error: userError
  } = await supabase.auth.getUser();

  if (userError || !user) {
    return redirectToLogin(request, "auth_required");
  }

  const profileResult = await supabase
    .from("user_profiles")
    .select("id,status")
    .eq("id", user.id)
    .maybeSingle();

  if (profileResult.error || !profileResult.data || profileResult.data.status !== "active") {
    return redirectToLogin(request, "profile_required");
  }

  if (user.user_metadata?.temporary_password_bootstrap === true && pathname !== TEMP_PASSWORD_CHANGE_ROUTE) {
    const changeUrl = request.nextUrl.clone();
    changeUrl.pathname = TEMP_PASSWORD_CHANGE_ROUTE;
    changeUrl.search = "";
    changeUrl.searchParams.set("next", `${request.nextUrl.pathname}${request.nextUrl.search}`);
    return NextResponse.redirect(changeUrl);
  }

  if (pathname === MODULE_GUARD_RECOVERY_ROUTE || pathname.startsWith(`${MODULE_GUARD_RECOVERY_ROUTE}/`)) {
    return response;
  }

  const moduleAccessResult = await supabase.rpc("get_current_route_module_access", {
    p_pathname: pathname
  });
  const moduleAccess = Array.isArray(moduleAccessResult.data)
    ? (moduleAccessResult.data[0] as RouteModuleAccess | undefined)
    : undefined;

  if (moduleAccessResult.error || !moduleAccess) {
    return redirectToModuleUnavailable(request, null, "runtime_contract_unavailable");
  }
  if (!moduleAccess.available) {
    return redirectToModuleUnavailable(request, moduleAccess.module_key, moduleAccess.reason);
  }

  return response;
}

function isPublicPath(pathname: string): boolean {
  if (PUBLIC_ROUTES.has(pathname)) {
    return true;
  }
  if (pathname.startsWith("/_next/") || pathname.startsWith("/favicon")) {
    return true;
  }
  return /\.[a-zA-Z0-9]+$/.test(pathname);
}

function redirectToLogin(request: NextRequest, result: string): NextResponse {
  const loginUrl = request.nextUrl.clone();
  loginUrl.pathname = "/login";
  loginUrl.search = "";
  loginUrl.searchParams.set("result", result);
  loginUrl.searchParams.set("next", `${request.nextUrl.pathname}${request.nextUrl.search}`);
  return NextResponse.redirect(loginUrl);
}

function redirectToModuleUnavailable(
  request: NextRequest,
  moduleKey: string | null,
  reason: string
): NextResponse {
  const unavailableUrl = request.nextUrl.clone();
  unavailableUrl.pathname = MODULE_GUARD_RECOVERY_ROUTE;
  unavailableUrl.search = "";
  unavailableUrl.searchParams.set("module", moduleKey ?? "rota");
  unavailableUrl.searchParams.set("reason", reason);
  unavailableUrl.searchParams.set("next", `${request.nextUrl.pathname}${request.nextUrl.search}`);
  return NextResponse.redirect(unavailableUrl);
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"]
};
