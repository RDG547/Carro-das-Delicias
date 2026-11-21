# Changelog

## 1.0.14 (2026112101) — 21/11/2026

### Catálogo e pesquisa

- Busca de produtos funcionando no painel administrativo e resultados ordenados por relevância no início. Pesquisas como “bolo de cenou” priorizam bolos de cenoura e descartam produtos sem relação.
- Atualizações de produtos, categorias, disponibilidade, destaques, mais vendidos, novidades e descontos propagadas em tempo real, com reconexão ao voltar para o aplicativo.
- Configuração administrativa para mostrar ou ocultar produtos sem fotos, aplicada às listas dos usuários em tempo real.
- Detalhes do produto acompanham alterações de preço, tamanhos, sabores e disponibilidade.
- Pré-carregamento dos ícones dos sabores e redução de trabalho e animações em abas que não estão visíveis.

### Administração

- Correção da abertura do editor de produtos após pesquisa e ao retornar do segundo plano.
- Aparência dos formulários de adição e edição padronizada, com ações adaptadas a telas pequenas e ao teclado.
- Filtro de pedidos convertido em menu ancorado, preservando nomes, ícones e opções.
- Remoção da borda/sombra indesejada ao arrastar categorias.
- Relatórios com texto para copiar, PDF e DOCX: todos os produtos, com foto, sem foto, mais vendidos, usuários e maiores compradores. Incluem produtos comprados, quantidades e total gasto, com paginação. Pedidos de teste, cancelados e não pagos não entram nos totais de vendas.

### Conta, favoritos e compartilhamento

- Recuperação de senha por email, validação de código/link, reenvio, confirmação de cadastro e alteração de senha pelo perfil.
- Animação de coração partido continua visível quando o produto é removido da lista de favoritos.
- Links de compartilhamento em `https://carrodasdelicias.vercel.app/produto/ID`, com abertura do aplicativo Android e encaminhamento à Play Store.

### Mapa, Android e proteção de dados

- Token público do Mapbox disponível também pela configuração nativa do Android; geocodificação centralizada e consultas repetidas reduzidas.
- Mapbox atualizado para 2.31.3 e integração Android ajustada para Kotlin integrado ao AGP 9, sem o aviso de uso do KGP legado.
- Seleção de fotos pelo seletor do sistema; permissão da câmera solicitada ao escolher tirar uma foto.
- Proteção dos campos administrativos dos perfis contra alterações por usuários comuns.
- Builds de produção usam apenas configuração pública; segredos de pagamento permanecem no servidor e não são encaminhados ao compilador pelo script de release.
- Produção exige a chave de assinatura de upload configurada, sem substituição automática pela chave de depuração.

As alterações do banco estão registradas em `supabase/migrations/` e foram aplicadas ao projeto conectado. Detalhes de validação e publicação: `releases/1.0.14/README.md`.
