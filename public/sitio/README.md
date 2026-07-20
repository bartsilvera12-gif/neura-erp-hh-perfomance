# Sitio público — pendiente de contenido

La funcionalidad de sitio público está **presente y operativa**:

- `src/middleware.ts` reescribe a `/sitio/*` cuando el host coincide con
  `SITIO_HOST_REGEX`.
- `src/app/api/sitio/*` expone categorías, productos y ofertas.

Lo que falta es el **contenido**: el HTML, los assets y las imágenes.

El repositorio de origen traía aquí el sitio web de Ferretería República
(incluido su manual de marca). Se retiró por ser material de otro cliente.

Para activarlo con contenido propio de HH Performance:

1. Colocar `index.html`, `catalogo.html` y assets en esta carpeta.
2. Definir `SITIO_HOST_REGEX` con el dominio público de HH Performance.

Sin contenido, el middleware nunca coincide con el host del ERP y la
aplicación funciona normalmente.
