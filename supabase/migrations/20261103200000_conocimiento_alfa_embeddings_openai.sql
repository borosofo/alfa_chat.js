-- La base de conocimiento pasa de Ollama (nomic-embed-text-v2-moe, 768 dimensiones)
-- a OpenAI text-embedding-3-small (1536 dimensiones).
-- Los vectores viejos no sirven con el modelo nuevo: se vacían y se regeneran con
-- scripts/reembeber_openai.sh. El texto (content) y metadata no cambian.
-- El índice HNSW se reconstruye solo al cambiar el tipo de la columna.
--
-- Para revertir: alter ... type vector(768) using null; y volver a copiar
-- conocimiento_alfa desde el origen.

alter table public.conocimiento_alfa
  alter column embedding type vector(1536) using null;
