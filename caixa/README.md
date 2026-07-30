# Caixa PDV

Sistema de **caixa e estoque** — produto separado do Fiado (caderno de vale).

## Links

- App: `…/caixa/` (tem login próprio)
- Mesma nuvem/conta do mercado, mas interface e marca distintas
- SQL: rode `estoque-schema.sql` no Supabase **depois** de `fiado/supabase-schema.sql`

## Pasta

| Arquivo | Função |
|---------|--------|
| `index.html` | Telas Venda, Produtos, Hoje |
| `estoque-schema.sql` | Tabelas e RPCs de estoque |
| `manifest.webmanifest` | PWA do Caixa |

Config e API de nuvem ficam em `fiado/config.js` e `fiado/cloud.js` (compartilhados).
