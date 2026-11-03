# Migración de Alfa al Supabase oficial

Estado: **inventario del destino hecho; falta correr respaldo y comparación contra el origen**.
Todavía no se ha escrito nada en ninguna base de datos ni en n8n.

## Objetivo

Que todo lo que usa hoy Alfa (chatbot AVA, base de conocimiento, memoria del chat,
catálogo/recetas, datos de Mercado Libre) quede en el **proyecto Supabase oficial de Alfa**
(cuenta de la empresa), actualizado con los datos de producción actuales.

El destino ya **no** es el Supabase autoalojado del VPS: no se toca el VPS ni nada de Miga.

## Mapa de proyectos

| Proyecto | Credencial(es) en n8n | Rol |
|---|---|---|
| `pgeyfvjmdzvwqdbdvbhn` (cuenta personal) | "Supabase Alfa" (supabaseApi), "Memoria de chatbot de Alfa demo" (postgres, pooler `aws-1-us-west-2`) | **Origen**: lo que usa hoy el chatbot en producción |
| `tuulhxyttqadxiamscfq` oficial (cuenta empresa, us-west-1) | "Memoria chat Alfa oficial" (postgres) | **Destino**. Ya tiene las tablas del chatbot, con datos desactualizados |
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

### Estado del destino (`tuulhxyttqadxiamscfq`, revisado 2026-11-03)

| Tabla | Filas | Nota |
|---|---|---|
| conocimiento_alfa | **0** | Base de conocimiento vacía: el chatbot no respondería bien hoy |
| documents | 0 | |
| ml_products | 255 | Última actualización 2026-05-11 |
| ml_catalog_match | 255 | |
| ml_credentials | 1 | Token de ML viejo |
| n8n_chat_histories | 104 | Se reemplaza por el historial del origen |
| productos_alfa | 304 | Trigger `trg_productos_alfa_search` |
| recetas / receta_ingredientes_alfa / receta_ingredientes_externos | 35 / 236 / 150 | |
| tipos_negocio / negocio_familias | 7 / 35 | |

- Extensiones: `vector` 0.8.0 (en `public`), `unaccent`, `pg_trgm` (en `extensions`).
- Funciones: `f_unaccent`, `match_documents(vector,int,jsonb)`, `update_productos_alfa_search`.
- RLS activo en todas las tablas y **sin políticas**: anon/authenticated no pueden leer ni
  escribir (los grants existen, pero RLS los bloquea). Es el estado deseado: n8n entra con el
  usuario `postgres`/service_role, que no pasa por RLS.
- El índice ivfflat de `conocimiento_alfa` se creó con la tabla vacía; el script lo reconstruye
  después de copiar.

## Otros workflows

| Workflow | Base | Acción en el corte |
|---|---|---|
| **ML - sync** (`nsA4A6bnfypPnDzIHx0TI`, cada 2 h) | Postgres: `ml_credentials`, `ml_products`, `ml_catalog_match`, `productos_alfa`, `extensions.unaccent`, `pg_trgm` | Cambiar credencial al oficial |
| **ML - Refresh Token** (`8FTMhepnONqz_wnRbOKkA`, cada 5 h) | Postgres: `ml_credentials` (user 2095714489) | Cambiar credencial al oficial |
| Registro Proveedores - Comestibles Alfa | Google Drive + Sheets + Telegram, **sin base de datos** | Nada |
| Sistema de cotizaciones Beta | Según el dueño, no es de Alfa | Nada |

**Ojo con el token de Mercado Libre:** el refresh token de ML se puede usar una sola vez. Si
"ML - Refresh Token" corre contra el origen después de copiar `ml_credentials`, el token copiado
al destino queda inválido. Por eso, en el corte final hay que pausar ese workflow (y ML - sync)
antes de copiar y reactivarlos ya apuntando al oficial.

## Paso a paso

Herramienta: `scripts/migrar_alfa.sh` (probado contra Postgres local: respaldo, comparación,
copia en una sola transacción, ajuste de secuencias, rechazo si cambian las columnas y
reversión completa si algo falla). Se puede correr más de una vez: cada copia reemplaza los
datos del destino con los del origen.

### 1. Preparación (en tu Linux)

Ver comandos en la sección "Comandos" abajo. Resultado esperado: `conexion` muestra ambas bases.

### 2. Respaldo y comparación (solo lectura sobre el origen)

`respaldo` y `comparar`. Compartir con Claude la salida de `comparar` y
`backups/esquema_diff.txt` (solo esquema, sin datos ni claves).

### 3. Ajuste de esquema

Si hay diferencias, Claude escribe migraciones en `supabase/migrations/` y, con tu OK, las aplica
en el destino.

### 4. Primera copia (ensayo)

`CONFIRMAR=si ./scripts/migrar_alfa.sh copiar`. Duplicar el chatbot en n8n apuntando al oficial
y probarlo por su webhook de prueba. Producción sigue en el origen.

### 5. Corte final (~10 min)

1. Pausar en n8n "ML - Refresh Token" y "ML - sync".
2. Copiar de nuevo (`copiar`) para traer lo último.
3. Crear en n8n la credencial supabaseApi "Supabase Alfa oficial"
   (`https://tuulhxyttqadxiamscfq.supabase.co` + service_role key).
4. Cambiar credenciales:
   - Chatbot: "BASE DE CONOCIMIENTO Y CONTEXTO" → "Supabase Alfa oficial"; los 6 nodos Postgres y
     "Postgres Chat Memory" → "Memoria chat Alfa oficial".
   - ML - sync y ML - Refresh Token: nodos Postgres → "Memoria chat Alfa oficial".
5. Reactivar ML - Refresh Token y ML - sync. Probar el widget.
6. El origen `pgeyfvjmdzvwqdbdvbhn` queda intacto unos días como plan de regreso
   (volver a poner las credenciales anteriores).

## Comandos

```bash
# Cliente de Postgres 17 (Ubuntu/Debian, repositorio oficial PGDG)
sudo apt install -y postgresql-common
sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
sudo apt install -y postgresql-client-17

git clone -b claude/alfa-supabase-migration-2p4r2z https://github.com/borosofo/alfa_chat.js.git
cd alfa_chat.js
cp .env.example .env   # completar las dos URLs (ver comentarios)

./scripts/migrar_alfa.sh conexion
./scripts/migrar_alfa.sh respaldo
./scripts/migrar_alfa.sh comparar
```

## Reglas

- Ningún secreto en git: usar `.env` (ver `.env.example`). Los respaldos van en `backups/` (ignorado).
- No editar ni borrar la credencial "Supabase MIGA". No tocar el VPS ni proyectos de Miga.
