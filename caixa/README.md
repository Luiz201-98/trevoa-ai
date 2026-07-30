# Caixa / Estoque

PDV simples (venda + estoque), separado do módulo Fiado.

## Links

- App: `…/caixa/` (GitHub Pages)
- Login: usa a mesma conta do Fiado (`../fiado/`)
- SQL: rode `estoque-schema.sql` no Supabase **depois** de `fiado/supabase-schema.sql`

## Pasta

| Arquivo | Função |
|---------|--------|
| `index.html` | Telas Venda, Produtos, Hoje |
| `estoque-schema.sql` | Tabelas e RPCs de estoque |
| `manifest.webmanifest` | PWA do Caixa |

Config e API de nuvem ficam em `fiado/config.js` e `fiado/cloud.js` (compartilhados).
