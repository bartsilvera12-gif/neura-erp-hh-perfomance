import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

/**
 * Middleware del ERP: refresca la sesión de Supabase en cada request.
 *
 * El repositorio de origen servía además un sitio web público estático desde
 * `public/sitio/`, reescribiendo las peticiones según el hostname. Esa
 * funcionalidad se retiró por completo en esta instancia: HH Performance es
 * únicamente el ERP.
 */
export async function middleware(request: NextRequest) {
  // Para assets estáticos no hace falta refrescar la sesión; ahorra latencia.
  if (/\.(?:svg|png|jpg|jpeg|gif|webp|ico|css|js|woff2?|ttf)$/i.test(request.nextUrl.pathname)) {
    return NextResponse.next({ request });
  }

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
