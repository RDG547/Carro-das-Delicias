# Validação da versão 1.0.14

Validada em 21/11/2026. Pacote `com.rdtech.carrodasdelicias`, versão `1.0.14`, código `2026112101`.

## Resultado

- 31 testes Flutter aprovados, incluindo busca, favoritos, exportação, autenticação e responsividade dos formulários.
- 3 testes Node aprovados para o compartilhamento e encaminhamento à Play Store.
- 3 testes Python aprovados para filtrar configurações públicas de release e rejeitar token privado do Mapbox.
- Analisador: **zero erros e zero avisos**. Permanecem 63 informações de análise, principalmente a depreciação de `material.dart` introduzida pelo Flutter 3.50. A verificação usa `flutter analyze --no-fatal-infos`; erros e avisos continuam bloqueando o CI.
- AAB validado com `bundletool 1.18.3`; pacote, versão, código, API de destino **36**, API mínima **24** e modo de produção conferidos no manifesto.
- AAB inclui `armeabi-v7a`, `arm64-v8a` e `x86_64`. Foram verificadas 21 bibliotecas ELF; todas as de 64 bits atendem ao alinhamento de 16 KB.
- Configuração do bundle: `PAGE_ALIGNMENT_16K`. Quatro APKs de teste foram gerados pelo bundletool a partir do AAB e passaram no `zipalign -c -P 16 4`. O APK de release também passou.
- Assinatura do AAB verificada com `jarsigner` e a do APK com `apksigner`. Ambos correspondem ao certificado da chave de upload local, válido até 15/06/2053. SHA-256: `F2:0B:0B:5E:A2:AA:7A:44:C6:FE:17:5E:74:C4:E0:45:3D:6D:50:4B:D9:80:19:29:4F:10:2C:A6:85:31:9F:D9`.
- AAB e APK conferidos para ausência dos valores privados locais de pagamento. A chave de assinatura, senhas e arquivos `.env` não entram no código enviado ao GitHub.
- Mapeamento R8 e nove arquivos de símbolos nativos incluídos no AAB, também disponíveis separadamente no pacote de entrega.
- `git diff --check` sem erros.

## Cobertura dos pedidos

| Item | Implementação e evidência |
| --- | --- |
| 1. Mapa | Inicialização do token público por Dart ou configuração nativa e geocodificação centralizada. Requisições reais de geocodificação e estilo responderam HTTP 200. Mensagens `lockHardwareCanvas` são logs do renderizador Android. |
| 2. Busca no admin | Campo ligado ao filtro de produtos, reutilizando a busca por relevância. |
| 3. Realtime | Produtos, categorias e configurações adicionados à publicação e com leitura sob RLS. Cliente público assinou as três tabelas com sucesso. |
| 4. Precisão da busca | Todos os termos relevantes precisam corresponder; prefixos e erros pequenos são aceitos. Testes excluem goiabada e mel ao buscar “bolo de cenou”. |
| 5. Editor de produtos | Navegação pela raiz, abertura protegida contra duplicação e dados atuais do produto. Menu fechado antes de abrir o editor. |
| 6. Fluidez | Consultas concorrentes coalescidas, canal de catálogo compartilhado, animações pausadas em abas inativas e imagens dos ícones reduzidas em cache. |
| 7. Relatórios | Seis seleções, texto para copiar, PDF e DOCX, paginação e totais de compras. Testes com 45 produtos verificam arquivos grandes. PDF e DOCX renderizado revisados visualmente. |
| 8. Responsividade | Formulários testados em larguras de 320, 440 e 900 pixels, também com teclado aberto. |
| 9. Favoritos | Animação no overlay da raiz antes da remoção. Teste garante continuidade após o card desaparecer. |
| 10. Catálogo ao vivo | Canal compartilhado, recarga com debounce e reconexão no retorno ao app; detalhes acompanham preço e variantes. |
| 11. Senhas e email | Recuperação por código/link, confirmação, reenvio e alteração com senha atual. Quatro testes com servidor simulado, incluindo código expirado. |
| 12. Formulários | Estrutura, cabeçalho, ações e controles de características padronizados. |
| 13. Filtro de pedidos | Menu ancorado às opções existentes, com mesmos nomes e ícones. |
| 14. Categorias | Proxy de arraste sem o Material adicional que gerava a borda/sombra. |
| 15. Compartilhamento | Página pública e associação Android publicadas; três testes do parser/intent/fallback e três testes Dart dos links. HTTP 200 no endpoint do produto e no assetlinks. |
| 16. Produtos sem fotos | Chave `catalog_visibility`, switch no admin e observação em tempo real. O item foi esclarecido como “sem fotos”. |
| 17. Ícones de sabores | Descoberta pelo manifesto moderno de assets e pré-carregamento local/remoto com cache de 128 pixels. |

No Supabase conectado, as duas migrações foram aplicadas e a configuração de visibilidade foi preservada. Um evento real de configuração foi recebido por um cliente público após atualizar apenas `updated_at`, sem alterar a visibilidade. A proteção dos perfis foi testada contra uma tentativa de promover um usuário comum a administrador; a alteração foi bloqueada e nenhum perfil foi promovido.

## Limites da validação

Não havia celular conectado ao ADB ao finalizar esta entrega. Os testes de interface foram executados pelo Flutter, sem medição de FPS em aparelho físico. Nenhum email real de recuperação foi enviado e nenhuma cobrança real foi criada para testes. A confirmação de email está habilitada no servidor; a entrega efetiva depende do provedor e dos templates configurados.

O certificado gerenciado pelo Google Play não foi acessado nesta sessão. Se ele for diferente do certificado de upload, siga a instrução sobre `assetlinks.json` no README da versão. O código já inclui a abertura por intent e a alternativa de encaminhamento à loja.

## Comandos de verificação

```sh
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
node --test test/product_link_page_test.cjs
python3 -m unittest discover -s tool -p 'test_*.py'
java -jar bundletool-all-1.18.3.jar validate --bundle app-release.aab
jarsigner -verify app-release.aab
apksigner verify --verbose app-release.apk
zipalign -c -P 16 4 app-release.apk
```
