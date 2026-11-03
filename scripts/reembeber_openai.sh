#!/usr/bin/env bash
# Regenera los embeddings de public.conocimiento_alfa en el proyecto OFICIAL
# (tuulhxyttqadxiamscfq) con OpenAI text-embedding-3-small (1536 dimensiones),
# el mismo modelo que usa el nodo "Embeddings OpenAI" del chatbot en n8n.
#
# Requisitos: psql, curl, jq; en .env: TARGET_DB_URL y OPENAI_API_KEY.
# Uso: ./scripts/reembeber_openai.sh
# Solo procesa filas con embedding vacío, así que se puede volver a correr si se corta.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "Falta .env"; exit 1; }
set -a; . ./.env; set +a
: "${TARGET_DB_URL:?Falta TARGET_DB_URL en .env}"
: "${OPENAI_API_KEY:?Falta OPENAI_API_KEY en .env}"
[[ "$TARGET_DB_URL" == *tuulhxyttqadxiamscfq* ]] || { echo "TARGET_DB_URL no es el proyecto oficial"; exit 1; }
command -v jq >/dev/null || { echo "Instala jq: sudo dnf install -y jq"; exit 1; }

MODELO="text-embedding-3-small"
PSQL=(psql -X -q -v ON_ERROR_STOP=1 "$TARGET_DB_URL")

tipo=$("${PSQL[@]}" -At -c "select format_type(atttypid, atttypmod) from pg_attribute
  where attrelid = 'public.conocimiento_alfa'::regclass and attname = 'embedding'")
[ "$tipo" = "vector(1536)" ] || {
  echo "La columna embedding es '$tipo'. Primero aplica la migración 20261103200000."; exit 1; }

ultimo=0; total=0
while :; do
  # Saltos de línea a espacios: igual que hace n8n (stripNewLines) al generar el vector de la pregunta.
  lote=$("${PSQL[@]}" -At -c "select coalesce(json_agg(t order by id), '[]') from (
      select id, replace(content, E'\n', ' ') as content
      from public.conocimiento_alfa
      where id > $ultimo and embedding is null and coalesce(trim(content), '') <> ''
      order by id limit 50) t")
  n=$(jq length <<<"$lote")
  [ "$n" -eq 0 ] && break

  resp=$(jq -c --arg m "$MODELO" '{model: $m, input: [.[].content]}' <<<"$lote" \
    | curl -sS --fail-with-body https://api.openai.com/v1/embeddings \
        -H "Authorization: Bearer $OPENAI_API_KEY" -H "Content-Type: application/json" -d @-)

  jq -r --argjson lote "$lote" --arg q "'" '
    "update public.conocimiento_alfa c set embedding = v.e::vector from (values "
    + ([.data[] | "(\($lote[.index].id), \($q)\(.embedding | tojson)\($q))"] | join(", "))
    + ") as v(id, e) where c.id = v.id;"' <<<"$resp" | "${PSQL[@]}"

  ultimo=$(jq '.[-1].id' <<<"$lote")
  total=$((total + n))
  echo "Vectores generados: $total"
done

"${PSQL[@]}" -At -c "select count(*) filter (where embedding is not null) || ' de ' || count(*)
  || ' filas tienen vector' from public.conocimiento_alfa"
