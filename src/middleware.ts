import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { errorResponse } from "@/lib/api/response";
import { BLOQUEO_PAGO_MENSAJE, BLOQUEO_PAGO_PATH, leerBloqueoPago } from "@/lib/bloqueo-pago";

/**
 * Middleware del ERP:
 *  1) Portón de "acceso suspendido por falta de pago" (DB-driven, ver bloqueo-pago.ts).
 *  2) Refresca la sesión de Supabase en cada request.
 */
export async function middleware(request: NextRequest) {
  // Para assets estáticos no hace falta ni portón ni refresh; ahorra latencia.
  if (/\.(?:svg|png|jpg|jpeg|gif|webp|ico|css|js|woff2?|ttf)$/i.test(request.nextUrl.pathname)) {
    return NextResponse.next({ request });
  }

  const { pathname } = request.nextUrl;
  const suspendido = await leerBloqueoPago();

  if (suspendido) {
    // Bloqueado: todo va a /bloqueado; las APIs responden 402. (Webhooks quedan fuera del matcher.)
    if (pathname.startsWith("/api/")) {
      return NextResponse.json(errorResponse(BLOQUEO_PAGO_MENSAJE), { status: 402 });
    }
    if (pathname !== BLOQUEO_PAGO_PATH) {
      const bloqueoUrl = request.nextUrl.clone();
      bloqueoUrl.pathname = BLOQUEO_PAGO_PATH;
      bloqueoUrl.search = "";
      return NextResponse.redirect(bloqueoUrl, 307);
    }
    return NextResponse.next({ request });
  }

  // Habilitado: si quedó parado en /bloqueado, al recargar lo mandamos al inicio.
  if (pathname === BLOQUEO_PAGO_PATH) {
    const inicio = request.nextUrl.clone();
    inicio.pathname = "/";
    inicio.search = "";
    return NextResponse.redirect(inicio, 307);
  }

  // ===== Refresh de sesión Supabase (comportamiento normal) =====
  let supabaseResponse = NextResponse.next({ request });

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anonKey) {
    return supabaseResponse;
  }

  const supabase = createServerClient(url, anonKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        supabaseResponse = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) =>
          supabaseResponse.cookies.set(name, value, options)
        );
      },
    },
  });

  await supabase.auth.getUser();

  return supabaseResponse;
}

/**
 * Excluir `/api/webhooks/*`: Meta hace GET sin cookies para verificar el webhook;
 * no debe pasar por refresh de sesión Supabase.
 */
export const config = {
  matcher: ["/((?!api/webhooks|_next/static|_next/image).*)"],
};
