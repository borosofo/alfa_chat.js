# Migración de Alfa al Supabase oficial

Estado: **fase 0 (inventario)**. Todavía no se ha escrito nada en ninguna base de datos ni en n8n.

## Objetivo

Que todo lo que usa hoy Alfa (chatbot AVA, base de conocimiento, memoria del chat,
catálogo/recetas, datos de Mercado Libre) quede en el **proyecto Supabase oficial de Alfa**
(cuenta de la empresa), actualizado con los datos de producción actuales.

El destino ya **no** es el Supabase autoalojado del VPS: no se toca el VPS ni nada de Miga.

## Mapa de proyectos

| Proyecto | Credencial(es) en n8n | Rol |
|---|---|---|
| `pgeyfvjmdzvwqdbdvbhn` (cuenta personal) | "Supabase Alfa" (supabaseApi), "Memoria de chatbot de Alfa demo" (postgres, pooler `aws-1-us-west-2`) | **Origen**: lo que usa hoy el chatbot en producción |
| Oficial de Alfa (cuenta empresa, ref pendiente) | "Memoria chat Alfa oficial" (postgres) | **Destino**. Ya tiene las tablas del chatbot, con datos desactualizados |
| `whxonevevculhcxhmcgy` (cuenta personal) | "Supabase MIGA" | Supabase cloud antiguo de Miga. **No se edita ni se borra la credencial.** |

## Qué usa el chatbot hoy

Workflow n8n **"Chatbot Alfa - Formato Mejorado"** (`87Jy57D6PgHrWeWOcfMmD`), webhook
`022cc084-42dd-4619-a802-7ddc3cf6daca` (el que llama `alfa-chat.js`).

| Nodo | Credencial | Objetos de BD |
|---|---|---|
| BASE DE CONOCIMIENTO Y CONTEXTO (vector store) | Supabase Alfa | `conocimiento_alfa`, `match_documents()` (por defecto) |
| Postgres Chat Memory | Memoria de chatbot de Alfa demo | `n8n_chat_histories` |
| Tabla de productos | Memoria de chatbot de Alfa demo | `productos_alfa`, `f_unaccent()` |
| Stock Mercado Libre | Memoria de chatbot de Alfa demo | `ml_products`, `ml_catalog_match` |
| Stock ML Múltiple | Memoria de chatbot de Alfa demo | `ml_products`, `ml_catalog_match`, `productos_alfa` |
| Catálogo Mercado Libre | Memoria de chatbot de Alfa demo | `ml_products`, `ml_catalog_match`, `productos_alfa` |
| Recetas Alfa | Memoria de chatbot de Alfa demo | `recetas`, `receta_ingredientes_alfa`, `receta_ingredientes_externos`, `productos_alfa`, `f_unaccent()` |
| Recomendador por Tipo de Negocio | Memoria de chatbot de Alfa demo | `tipos_negocio`, `negocio_familias`, `productos_alfa`, `unaccent()` |

Tablas que ya existen en el proyecto oficial: `conocimiento_alfa`, `documents`,
`ml_catalog_match`, `ml_credentials`, `ml_products`, `n8n_chat_histories`, `negocio_familias`,
`productos_alfa`, `receta_ingredientes_alfa`, `receta_ingredientes_externos`, `recetas`,
`tipos_negocio`.

## Pendiente de revisar (workflows sin acceso MCP)

Hay que saber a qué base escriben, porque después del corte deben apuntar al oficial:

- **Registro Proveedores - Comestibles Alfa** (`to04FDcosAGyW7RJ1FkRo`): lo llama el widget.
- **ML - sync** (`nsA4A6bnfypPnDzIHx0TI`): probablemente llena `ml_products`/`ml_catalog_match`.
- **ML - Refresh Token** (`8FTMhepnONqz_wnRbOKkA`): probablemente usa `ml_credentials`.
- **Chatbot Alfa para la demo** (`HH5EsX3xFPS0MRpp`).
- **Sistema de cotizaciones Beta** (`MW77WG7BQfXWqeB9`).
- **Errores en los workflows de Alfa** (`_HWuotoTt1KpZI3LGJA18`): también es el workflow de error de
  "ML - Refresh Token Miga" y "MIGA - Cotización Personalizada".

## Fases

Cada fase que escriba en el proyecto oficial o en n8n requiere confirmación explícita del dueño.

1. **Inventario (solo lectura):** tablas, columnas, filas, índices, funciones, extensiones, RLS y
   grants de origen y destino, comparados.
2. **Respaldo:** `pg_dump` completo del proyecto oficial antes de cualquier cambio (fuera de git).
3. **Esquema:** migraciones SQL idempotentes en `supabase/migrations/` que llevan el destino al
   esquema del origen (extensiones `vector`/`unaccent`, `f_unaccent()`, `match_documents()`,
   columnas e índices que falten).
4. **Datos:** copia de los datos actuales del origen al destino, tabla por tabla, verificando
   número de filas y dimensión de los embeddings.
5. **Seguridad:** el widget solo habla con n8n, así que Alfa no necesita acceso anon. RLS activo
   en todas las tablas sin políticas para anon/authenticated.
6. **Prueba:** nueva credencial "Supabase Alfa oficial" en n8n y copia del chatbot apuntando al
   oficial, probada antes de tocar el de producción.
7. **Corte:** cambiar credenciales del chatbot real (y de ML - sync / Refresh Token si aplica).
   El proyecto `pgeyfvjmdzvwqdbdvbhn` queda intacto unos días como plan de regreso.

## Reglas

- Ningún secreto en git: usar `.env` (ver `.env.example`). Los respaldos van en `backups/` (ignorado).
- No editar ni borrar la credencial "Supabase MIGA". No tocar el VPS ni proyectos de Miga.
