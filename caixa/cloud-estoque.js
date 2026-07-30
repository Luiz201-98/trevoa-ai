/**
 * API de estoque/PDV — só o app Caixa carrega este arquivo.
 * Depende de ../fiado/config.js e ../fiado/cloud.js (login/token).
 */
(function (global) {
  const cfg = global.FIADO_CLOUD || { enabled: false };
  const C = global.FiadoCloud;
  if (!C) return;

  async function rpc(fn, args) {
    const res = await fetch(`${String(cfg.url || "").replace(/\/$/, "")}/rest/v1/rpc/${fn}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: cfg.anonKey,
        Authorization: `Bearer ${cfg.anonKey}`,
      },
      body: JSON.stringify(args || {}),
    });
    const text = await res.text();
    let data;
    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      throw new Error(text || "Erro na nuvem");
    }
    if (!res.ok) {
      throw new Error((data && (data.message || data.error)) || text || `Erro HTTP ${res.status}`);
    }
    return data;
  }

  C.listarProdutos = async function listarProdutos() {
    const data = await rpc("estoque_listar_produtos", { p_token: C.getToken() });
    if (!data || !data.ok) throw new Error((data && data.erro) || "Não listou produtos");
    return data.produtos || [];
  };

  C.salvarProduto = async function salvarProduto(p) {
    const data = await rpc("estoque_salvar_produto", {
      p_token: C.getToken(),
      p_id: p.id || null,
      p_nome: p.nome,
      p_codigo_barras: p.codigoBarras || null,
      p_codigo_reduzido: p.codigoReduzido || null,
      p_preco: p.preco,
      p_estoque: p.estoque,
      p_ativo: p.ativo !== false,
    });
    if (!data || !data.ok) throw new Error((data && data.erro) || "Não salvou produto");
    return data;
  };

  C.buscarCodigo = async function buscarCodigo(codigo) {
    return rpc("estoque_buscar_codigo", {
      p_token: C.getToken(),
      p_codigo: codigo,
    });
  };

  C.registrarVenda = async function registrarVenda(itens, forma) {
    const payload = (itens || []).map((i) => ({
      produtoId: i.produtoId,
      qtd: i.qtd,
    }));
    const data = await rpc("estoque_registrar_venda", {
      p_token: C.getToken(),
      p_itens: payload,
      p_forma: forma || "dinheiro",
    });
    if (!data || !data.ok) throw new Error((data && data.erro) || "Não registrou venda");
    return data;
  };

  C.resumoDia = async function resumoDia(dataIso) {
    const args = { p_token: C.getToken() };
    if (dataIso) args.p_data = dataIso;
    const data = await rpc("estoque_resumo_dia", args);
    if (!data || !data.ok) throw new Error((data && data.erro) || "Não carregou o dia");
    return data;
  };
})(window);
