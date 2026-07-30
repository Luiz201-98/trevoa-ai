-- Caixa / Estoque — rode no SQL Editor do Supabase (depois do supabase-schema.sql)
-- Requer: funções _sessao_ok e _mercado_ativo já existentes

create extension if not exists pgcrypto with schema extensions;

-- ─── Tabelas ───────────────────────────────────────────
create table if not exists public.produtos (
  id uuid primary key default gen_random_uuid(),
  mercado_id uuid not null references public.mercados(id) on delete cascade,
  nome text not null,
  codigo_barras text,
  codigo_reduzido text,
  preco numeric(12,2) not null check (preco >= 0),
  estoque numeric(12,3) not null default 0,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index if not exists produtos_mercado_idx on public.produtos(mercado_id);
create unique index if not exists produtos_barras_uq
  on public.produtos(mercado_id, codigo_barras)
  where codigo_barras is not null and codigo_barras <> '';
create unique index if not exists produtos_reduzido_uq
  on public.produtos(mercado_id, codigo_reduzido)
  where codigo_reduzido is not null and codigo_reduzido <> '';

create table if not exists public.vendas (
  id uuid primary key default gen_random_uuid(),
  mercado_id uuid not null references public.mercados(id) on delete cascade,
  total numeric(12,2) not null check (total >= 0),
  forma text not null default 'dinheiro',
  cancelada boolean not null default false,
  criado_em timestamptz not null default now()
);

create index if not exists vendas_mercado_dia_idx
  on public.vendas(mercado_id, criado_em desc);

create table if not exists public.venda_itens (
  id uuid primary key default gen_random_uuid(),
  venda_id uuid not null references public.vendas(id) on delete cascade,
  produto_id uuid not null references public.produtos(id),
  qtd numeric(12,3) not null check (qtd > 0),
  preco_unit numeric(12,2) not null check (preco_unit >= 0),
  subtotal numeric(12,2) not null check (subtotal >= 0)
);

create index if not exists venda_itens_venda_idx on public.venda_itens(venda_id);

alter table public.produtos enable row level security;
alter table public.vendas enable row level security;
alter table public.venda_itens enable row level security;

-- ─── Listar produtos ───────────────────────────────────
create or replace function public.estoque_listar_produtos(p_token text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  s sessoes;
  mid uuid;
  result json;
begin
  s := _sessao_ok(p_token);
  mid := _mercado_ativo(s);
  if mid is null then
    raise exception 'Selecione um mercado';
  end if;

  select coalesce(json_agg(json_build_object(
    'id', p.id,
    'nome', p.nome,
    'codigoBarras', p.codigo_barras,
    'codigoReduzido', p.codigo_reduzido,
    'preco', p.preco,
    'estoque', p.estoque,
    'ativo', p.ativo
  ) order by p.nome), '[]'::json)
  into result
  from produtos p
  where p.mercado_id = mid and p.ativo = true;

  return json_build_object('ok', true, 'produtos', result);
end;
$$;

-- ─── Salvar produto (insert/update) ────────────────────
create or replace function public.estoque_salvar_produto(
  p_token text,
  p_id uuid default null,
  p_nome text default null,
  p_codigo_barras text default null,
  p_codigo_reduzido text default null,
  p_preco numeric default null,
  p_estoque numeric default null,
  p_ativo boolean default true
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  s sessoes;
  mid uuid;
  pid uuid;
  barras text := nullif(trim(coalesce(p_codigo_barras, '')), '');
  reduzido text := nullif(trim(coalesce(p_codigo_reduzido, '')), '');
  nome text := trim(coalesce(p_nome, ''));
begin
  s := _sessao_ok(p_token);
  mid := _mercado_ativo(s);
  if mid is null then
    raise exception 'Selecione um mercado';
  end if;
  if length(nome) < 1 then
    return json_build_object('ok', false, 'erro', 'Nome obrigatório');
  end if;
  if p_preco is null or p_preco < 0 then
    return json_build_object('ok', false, 'erro', 'Preço inválido');
  end if;
  if barras is null and reduzido is null then
    return json_build_object('ok', false, 'erro', 'Informe código de barras ou código reduzido');
  end if;

  if p_id is not null then
    update produtos set
      nome = nome,
      codigo_barras = barras,
      codigo_reduzido = reduzido,
      preco = p_preco,
      estoque = coalesce(p_estoque, estoque),
      ativo = coalesce(p_ativo, true),
      atualizado_em = now()
    where id = p_id and mercado_id = mid
    returning id into pid;
    if pid is null then
      return json_build_object('ok', false, 'erro', 'Produto não encontrado');
    end if;
  else
    insert into produtos(mercado_id, nome, codigo_barras, codigo_reduzido, preco, estoque, ativo)
    values (mid, nome, barras, reduzido, p_preco, coalesce(p_estoque, 0), coalesce(p_ativo, true))
    returning id into pid;
  end if;

  return json_build_object('ok', true, 'id', pid);
exception
  when unique_violation then
    return json_build_object('ok', false, 'erro', 'Já existe produto com esse código');
end;
$$;

-- ─── Buscar por código (barras ou reduzido) ────────────
create or replace function public.estoque_buscar_codigo(p_token text, p_codigo text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  s sessoes;
  mid uuid;
  cod text := trim(coalesce(p_codigo, ''));
  p produtos;
begin
  s := _sessao_ok(p_token);
  mid := _mercado_ativo(s);
  if mid is null then
    raise exception 'Selecione um mercado';
  end if;
  if cod = '' then
    return json_build_object('ok', false, 'erro', 'Código vazio');
  end if;

  select * into p from produtos
  where mercado_id = mid and ativo = true
    and (codigo_barras = cod or codigo_reduzido = cod)
  limit 1;

  if not found then
    return json_build_object('ok', false, 'erro', 'Produto não encontrado');
  end if;

  return json_build_object(
    'ok', true,
    'produto', json_build_object(
      'id', p.id,
      'nome', p.nome,
      'codigoBarras', p.codigo_barras,
      'codigoReduzido', p.codigo_reduzido,
      'preco', p.preco,
      'estoque', p.estoque
    )
  );
end;
$$;

-- ─── Registrar venda + baixa estoque ──────────────────
create or replace function public.estoque_registrar_venda(
  p_token text,
  p_itens json,
  p_forma text default 'dinheiro'
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  s sessoes;
  mid uuid;
  vid uuid;
  item json;
  pid uuid;
  qtd numeric;
  preco numeric;
  sub numeric;
  total numeric := 0;
  est_atual numeric;
  nome_prod text;
  forma text := lower(trim(coalesce(p_forma, 'dinheiro')));
begin
  s := _sessao_ok(p_token);
  mid := _mercado_ativo(s);
  if mid is null then
    raise exception 'Selecione um mercado';
  end if;
  if p_itens is null or json_typeof(p_itens) <> 'array' or json_array_length(p_itens) = 0 then
    return json_build_object('ok', false, 'erro', 'Carrinho vazio');
  end if;
  if forma not in ('dinheiro', 'pix', 'debito', 'credito') then
    forma := 'dinheiro';
  end if;

  -- valida estoque e calcula total
  for item in select * from json_array_elements(p_itens)
  loop
    pid := (item->>'produtoId')::uuid;
    qtd := coalesce((item->>'qtd')::numeric, 0);
    if qtd <= 0 then
      return json_build_object('ok', false, 'erro', 'Quantidade inválida');
    end if;
    select estoque, preco, nome into est_atual, preco, nome_prod
    from produtos where id = pid and mercado_id = mid and ativo = true;
    if not found then
      return json_build_object('ok', false, 'erro', 'Produto inválido na venda');
    end if;
    if est_atual < qtd then
      return json_build_object('ok', false, 'erro', 'Estoque insuficiente: ' || nome_prod);
    end if;
    -- usa preço atual do cadastro (ignora preço do client)
    total := total + round(preco * qtd, 2);
  end loop;

  insert into vendas(mercado_id, total, forma)
  values (mid, total, forma)
  returning id into vid;

  for item in select * from json_array_elements(p_itens)
  loop
    pid := (item->>'produtoId')::uuid;
    qtd := (item->>'qtd')::numeric;
    select preco into preco from produtos where id = pid;
    sub := round(preco * qtd, 2);
    insert into venda_itens(venda_id, produto_id, qtd, preco_unit, subtotal)
    values (vid, pid, qtd, preco, sub);
    update produtos set
      estoque = estoque - qtd,
      atualizado_em = now()
    where id = pid and mercado_id = mid;
  end loop;

  return json_build_object('ok', true, 'vendaId', vid, 'total', total);
end;
$$;

-- ─── Resumo do dia ─────────────────────────────────────
create or replace function public.estoque_resumo_dia(p_token text, p_data date default null)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  s sessoes;
  mid uuid;
  dia date := coalesce(p_data, (now() at time zone 'America/Sao_Paulo')::date);
  tot numeric;
  qtd int;
  por_forma json;
  lista json;
begin
  s := _sessao_ok(p_token);
  mid := _mercado_ativo(s);
  if mid is null then
    raise exception 'Selecione um mercado';
  end if;

  select coalesce(sum(total), 0), count(*)
  into tot, qtd
  from vendas
  where mercado_id = mid
    and cancelada = false
    and (criado_em at time zone 'America/Sao_Paulo')::date = dia;

  select coalesce(json_object_agg(forma, t), '{}'::json)
  into por_forma
  from (
    select forma, sum(total) as t
    from vendas
    where mercado_id = mid and cancelada = false
      and (criado_em at time zone 'America/Sao_Paulo')::date = dia
    group by forma
  ) x;

  select coalesce(json_agg(json_build_object(
    'id', v.id,
    'total', v.total,
    'forma', v.forma,
    'criadoEm', v.criado_em,
    'itens', (
      select coalesce(json_agg(json_build_object(
        'nome', p.nome,
        'qtd', i.qtd,
        'precoUnit', i.preco_unit,
        'subtotal', i.subtotal
      )), '[]'::json)
      from venda_itens i
      join produtos p on p.id = i.produto_id
      where i.venda_id = v.id
    )
  ) order by v.criado_em desc), '[]'::json)
  into lista
  from vendas v
  where v.mercado_id = mid and v.cancelada = false
    and (v.criado_em at time zone 'America/Sao_Paulo')::date = dia;

  return json_build_object(
    'ok', true,
    'data', dia,
    'total', tot,
    'qtdVendas', qtd,
    'porForma', por_forma,
    'vendas', lista
  );
end;
$$;

grant execute on function public.estoque_listar_produtos(text) to anon, authenticated;
grant execute on function public.estoque_salvar_produto(text, uuid, text, text, text, numeric, numeric, boolean) to anon, authenticated;
grant execute on function public.estoque_buscar_codigo(text, text) to anon, authenticated;
grant execute on function public.estoque_registrar_venda(text, json, text) to anon, authenticated;
grant execute on function public.estoque_resumo_dia(text, date) to anon, authenticated;
