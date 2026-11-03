-- La base de conocimiento tiene ~150 filas. El índice ivfflat con lists=100 reparte esas filas
-- en 100 grupos y por defecto solo revisa 1 grupo por búsqueda: match_documents(…, 10) devolvía
-- 2 resultados en vez de 10 (verificado 2026-11-03). HNSW no depende del tamaño de la tabla.
-- Se puede correr más de una vez sin efecto adicional.
--
-- Para revertir:
--   drop index if exists public.conocimiento_alfa_embedding_hnsw_idx;
--   create index conocimiento_alfa_embedding_idx on public.conocimiento_alfa
--     using ivfflat (embedding vector_cosine_ops) with (lists = 100);

drop index if exists public.conocimiento_alfa_embedding_idx;

create index if not exists conocimiento_alfa_embedding_hnsw_idx
  on public.conocimiento_alfa using hnsw (embedding vector_cosine_ops);
