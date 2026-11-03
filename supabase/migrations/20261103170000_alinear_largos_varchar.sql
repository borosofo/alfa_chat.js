-- Alinea el proyecto oficial (tuulhxyttqadxiamscfq) con el origen (pgeyfvjmdzvwqdbdvbhn):
-- en el origen estas columnas tienen largo máximo; en el destino no.
-- Verificado 2026-11-03: los datos actuales del destino caben en todos los límites
-- y ninguna vista depende de estas columnas.
-- Se puede correr más de una vez sin efecto adicional.
--
-- Para revertir: mismo ALTER con "type varchar" (sin largo).

begin;

alter table public.ml_catalog_match
  alter column alfa_codigo  type varchar(20),
  alter column match_source type varchar(20),
  alter column ml_item_id   type varchar(50);

alter table public.ml_credentials
  alter column user_id type varchar(50);

alter table public.ml_products
  alter column category_id type varchar(50),
  alter column condition   type varchar(20),
  alter column item_id     type varchar(50),
  alter column status      type varchar(20);

alter table public.n8n_chat_histories
  alter column session_id type varchar(255);

alter table public.productos_alfa
  alter column codigo         type varchar(20),
  alter column empaque        type varchar(50),
  alter column especificacion type varchar(100),
  alter column familia        type varchar(50),
  alter column marca          type varchar(50),
  alter column presentacion   type varchar(50);

commit;
