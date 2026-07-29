-- Rode no SQL Editor: login e criar mercado sem diferenciar maiúscula/minúscula no usuário

create or replace function public.fiado_login(p_usuario text, p_senha text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  a admin_conta;
  m mercados;
  tok text;
  u text := lower(trim(coalesce(p_usuario, '')));
begin
  select * into a from admin_conta where id = 1;
  if lower(a.usuario) = u and a.senha_hash = crypt(p_senha, a.senha_hash) then
    tok := _nova_sessao('admin', null, null);
    return json_build_object(
      'ok', true,
      'role', 'admin',
      'token', tok,
      'usuario', a.usuario,
      'nome', 'Administrador',
      'trialDias', a.trial_dias,
      'codigoLiberacao', a.codigo_liberacao,
      'seuWhatsapp', a.seu_whatsapp
    );
  end if;

  select * into m from mercados where lower(usuario) = u;
  if not found or m.senha_hash <> crypt(p_senha, m.senha_hash) then
    return json_build_object('ok', false, 'erro', 'Usuário ou senha incorretos.');
  end if;
  if m.bloqueado then
    return json_build_object('ok', false, 'erro', 'Mercado bloqueado.');
  end if;

  if m.trial_inicio is null then
    update mercados set trial_inicio = now() where id = m.id;
    m.trial_inicio := now();
  end if;

  tok := _nova_sessao('user', m.id, null);
  return json_build_object(
    'ok', true,
    'role', 'user',
    'token', tok,
    'usuario', m.usuario,
    'mercadoId', m.id,
    'nome', m.nome,
    'pago', m.pago,
    'bloqueado', m.bloqueado,
    'trialInicio', m.trial_inicio,
    'valorLicenca', m.valor_licenca,
    'chavePix', m.chave_pix,
    'trialDias', a.trial_dias,
    'codigoLiberacao', a.codigo_liberacao,
    'seuWhatsapp', a.seu_whatsapp
  );
end;
$$;

create or replace function public.fiado_admin_criar_mercado(
  p_token text,
  p_usuario text,
  p_senha text,
  p_nome text default 'Fiado'
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  s sessoes;
  mid uuid;
  u text := lower(trim(coalesce(p_usuario, '')));
begin
  s := _sessao_ok(p_token);
  if s.role <> 'admin' then
    raise exception 'Só admin';
  end if;
  if length(u) < 2 or length(p_senha) < 4 then
    raise exception 'Usuário/senha inválidos';
  end if;
  if exists (select 1 from mercados where lower(usuario) = u) then
    return json_build_object('ok', false, 'erro', 'Já existe um mercado com esse usuário.');
  end if;

  insert into mercados(usuario, senha_hash, nome, trial_inicio)
  values (u, crypt(p_senha, gen_salt('bf')), coalesce(nullif(trim(p_nome), ''), 'Fiado'), now())
  returning id into mid;

  return json_build_object('ok', true, 'id', mid, 'usuario', u);
exception
  when unique_violation then
    return json_build_object('ok', false, 'erro', 'Já existe um mercado com esse usuário.');
end;
$$;

-- Normaliza usuários já cadastrados pra minúsculo
update public.mercados set usuario = lower(usuario) where usuario <> lower(usuario);
update public.admin_conta set usuario = lower(usuario) where id = 1 and usuario <> lower(usuario);
