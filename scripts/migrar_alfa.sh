#!/usr/bin/env bash
# Migración de datos de Alfa:
#   origen  = pgeyfvjmdzvwqdbdvbhn  (lo que usa hoy el chatbot)
#   destino = tuulhxyttqadxiamscfq  (Supabase oficial de Alfa)
#
# Uso (desde la raíz del repo, con .env completo):
#   ./scripts/migrar_alfa.sh conexion   # prueba ambas conexiones (solo lectura)
#   ./scripts/migrar_alfa.sh respaldo   # pg_dump completo de origen y destino a backups/
#   ./scripts/migrar_alfa.sh comparar   # compara esquema y conteos (solo lectura)
#   CONFIRMAR=si ./scripts/migrar_alfa.sh copiar   # REEMPLAZA los datos del destino con los del origen
#   ./scripts/migrar_alfa.sh conteos    # conteos lado a lado (solo lectura)
#
# Nada de backups/ ni .env se sube a git (ver .gitignore).
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "Falta .env (copia .env.example y complétalo)"; exit 1; }
set -a; . ./.env; set +a
: "${SOURCE_DB_URL:?Falta SOURCE_DB_URL en .env}"
: "${TARGET_DB_URL:?Falta TARGET_DB_URL en .env}"

# Evita invertir origen y destino por error.
[[ "$SOURCE_DB_URL" == *pgeyfvjmdzvwqdbdvbhn* ]] || { echo "SOURCE_DB_URL no es el proyecto pgeyfvjmdzvwqdbdvbhn"; exit 1; }
[[ "$TARGET_DB_URL" == *tuulhxyttqadxiamscfq* ]] || { echo "TARGET_DB_URL no es el proyecto oficial tuulhxyttqadxiamscfq"; exit 1; }

# Orden pensado para respetar dependencias entre tablas.
# conocimiento_alfa NO se copia: en el oficial sus vectores se regeneraron con OpenAI
# (scripts/reembeber_openai.sh) y los del origen (Ollama, 768 dims) ya no son compatibles.
TABLAS=(
  productos_alfa tipos_negocio negocio_familias
  recetas receta_ingredientes_alfa receta_ingredientes_externos
  ml_products ml_catalog_match ml_credentials
  documents n8n_chat_histories
)
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p backups

v=$(pg_dump --version | grep -oE '[0-9]+' | head -1)
[ "$v" -ge 17 ] || { echo "Necesitas pg_dump/psql 17 o superior (tienes $v)"; exit 1; }

PSQL=(psql -X -q -v ON_ERROR_STOP=1)
IN_LIST="'$(IFS="|"; echo "${TABLAS[*]}" | sed "s/|/','/g")'"

conteos_de() {
  local url=$1 q=""
  for t in "${TABLAS[@]}"; do
    q+="select '$t' as tabla, (select count(*) from public.$t) as filas union all "
  done
  "${PSQL[@]}" "$url" -At -F $'\t' -c "${q% union all } order by 1"
}

columnas_de() {
  "${PSQL[@]}" "$1" -At -c "
    select table_name||'.'||column_name||' '||data_type||coalesce('('||character_maximum_length||')','')
           ||case when is_generated='ALWAYS' then ' GENERATED' else '' end
    from information_schema.columns
    where table_schema='public' and table_name in ($IN_LIST)
    order by 1"
}

case "${1:-}" in
  conexion)
    for n in SOURCE TARGET; do
      url_var="${n}_DB_URL"
      echo "== $n"
      "${PSQL[@]}" "${!url_var}" -At -c "select current_user, version()"
    done
    ;;

  respaldo)
    echo "Respaldando destino (antes de cualquier cambio)..."
    # Se escribe a .tmp y solo se renombra si pg_dump termina bien, para que un
    # respaldo fallido nunca cuente como válido.
    trap 'rm -f backups/*.tmp' EXIT
    pg_dump "$TARGET_DB_URL" -Fc --no-owner --no-privileges -n public -f "backups/destino_antes_$TS.dump.tmp"
    mv "backups/destino_antes_$TS.dump.tmp" "backups/destino_antes_$TS.dump"
    echo "Respaldando origen..."
    pg_dump "$SOURCE_DB_URL" -Fc --no-owner --no-privileges -n public -f "backups/origen_$TS.dump.tmp"
    mv "backups/origen_$TS.dump.tmp" "backups/origen_$TS.dump"
    ls -lh backups/*_"$TS".dump
    ;;

  comparar)
    pg_dump "$SOURCE_DB_URL" -s --no-owner --no-privileges -n public -f backups/esquema_origen.sql
    pg_dump "$TARGET_DB_URL" -s --no-owner --no-privileges -n public -f backups/esquema_destino.sql
    diff -u backups/esquema_origen.sql backups/esquema_destino.sql > backups/esquema_diff.txt || true
    echo "== Diferencias de columnas en las tablas de Alfa (- origen / + destino)"
    diff <(columnas_de "$SOURCE_DB_URL") <(columnas_de "$TARGET_DB_URL") && echo "(sin diferencias)"
    echo "== Tablas del origen que no están en la lista de migración"
    "${PSQL[@]}" "$SOURCE_DB_URL" -At -c "
      select table_name from information_schema.tables
      where table_schema='public' and table_name not in ($IN_LIST) order by 1"
    echo "== Conteos (origen | destino)"
    join -t $'\t' <(conteos_de "$SOURCE_DB_URL") <(conteos_de "$TARGET_DB_URL")
    echo "Diff completo del esquema: backups/esquema_diff.txt"
    ;;

  copiar)
    [ "${CONFIRMAR:-}" = "si" ] || { echo "Para copiar ejecuta: CONFIRMAR=si $0 copiar"; exit 1; }
    ls backups/destino_antes_*.dump >/dev/null 2>&1 || { echo "Primero corre: $0 respaldo"; exit 1; }
    COLS_ORIGEN=$(columnas_de "$SOURCE_DB_URL")
    COLS_DESTINO=$(columnas_de "$TARGET_DB_URL")
    [ -n "$COLS_ORIGEN" ] || { echo "No se pudieron leer las columnas del origen"; exit 1; }
    if [ "$COLS_ORIGEN" != "$COLS_DESTINO" ]; then
      echo "Las columnas no coinciden entre origen y destino. Corre '$0 comparar' y ajusta el esquema primero."
      exit 1
    fi
    T_ARGS=(); for t in "${TABLAS[@]}"; do T_ARGS+=(-t "public.$t"); done
    SQL="backups/copia_$TS.sql"
    # Contiene datos (tokens de ML, historiales): se borra pase lo que pase.
    trap 'rm -f "$SQL"' EXIT
    {
      echo "BEGIN;"
      echo "TRUNCATE $(IFS=,; echo "${TABLAS[*]/#/public.}") RESTART IDENTITY;"
      pg_dump "$SOURCE_DB_URL" -a --no-owner --no-privileges "${T_ARGS[@]}"
      cat <<EOF
-- Ajustar secuencias al máximo id copiado
DO \$\$ DECLARE r record; BEGIN
  FOR r IN
    SELECT c.table_name, c.column_name,
           pg_get_serial_sequence('public.'||quote_ident(c.table_name), c.column_name) AS seq
    FROM information_schema.columns c
    WHERE c.table_schema='public' AND c.table_name IN ($IN_LIST)
      AND pg_get_serial_sequence('public.'||quote_ident(c.table_name), c.column_name) IS NOT NULL
  LOOP
    EXECUTE format('SELECT setval(%L, COALESCE((SELECT max(%I) FROM public.%I), 0) + 1, false)',
                   r.seq, r.column_name, r.table_name);
  END LOOP;
END \$\$;
COMMIT;
EOF
      for t in "${TABLAS[@]}"; do echo "ANALYZE public.$t;"; done
    } > "$SQL"
    echo "Aplicando en el destino (una sola transacción; si algo falla no se aplica nada)..."
    "${PSQL[@]}" "$TARGET_DB_URL" -f "$SQL" >/dev/null

    echo "== Conteos (origen | destino)"
    join -t $'\t' <(conteos_de "$SOURCE_DB_URL") <(conteos_de "$TARGET_DB_URL")
    ;;

  conteos)
    join -t $'\t' <(conteos_de "$SOURCE_DB_URL") <(conteos_de "$TARGET_DB_URL")
    ;;

  *)
    sed -n '2,13p' "$0"; exit 1;;
esac
