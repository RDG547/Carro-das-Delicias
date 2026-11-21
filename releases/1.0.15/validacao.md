# Validação da versão 1.0.15

Pacote `com.rdtech.carrodasdelicias`, versão `1.0.15`, código `2026112104`. Flutter 3.50.1, Dart 3.14, AGP 9.3.1, Gradle 9.5.0. Verificações em 21/11/2026.

## Testes automatizados

- 59 testes Flutter aprovados, incluindo os fluxos existentes e 15 novos testes de regressão.
- 3 testes Node da página de compartilhamento aprovados.
- 3 testes Python do filtro de configuração pública do build aprovados.
- Análise Dart sem erros ou avisos; 77 mensagens informativas, principalmente depreciações da API Material desta versão do SDK.
- Após o ajuste final dos recuos, os testes de layout e de reordenação foram executados novamente e passaram.

Os casos novos cobrem objetos Mapbox v6 com metadados, prioridade entre bairro e cidade, pressão longa e rolagem sem alterar categorias, arraste pelo puxador, texto completo de salvar em larguras de 320/440 px e paisagem, barras do sistema de tamanhos diferentes, oferta individual de atualização, cancelamento, reinício sem internet, instalação concluída, oferta retirada, instalação externa e modal obrigatório em tela pequena e paisagem.

## Banco e tempo real

- Consulta pública confirmou a mesma sequência de nove categorias antes e depois de um evento real do Supabase Realtime.
- O cliente público recebeu o evento de atualização de categoria; `categorias`, `produtos` e `app_settings` estão na publicação de tempo real.
- A RPC `reorder_categories` foi executada como administrador autenticado, com sequência invertida e conferência da persistência dos campos `ordem` e `order`. A transação de teste foi revertida, preservando a ordem em produção.
- Não foi necessário alterar o esquema nesta entrega. As migrações anteriores permanecem no repositório.

## R8 e Android

Comparação do relatório local do R8 com o build anterior `2026112103`:

| Indicador | Anterior | 1.0.15 |
| --- | ---: | ---: |
| Otimização permitida | 66,89% | 93,56% |
| Ofuscação permitida | 67,27% | 71,10% |
| Redução permitida | 67,14% | 70,96% |
| Itens vivos | 99.157 | 96.826 |
| Código DEX descompactado | 5.321.160 bytes | 5.212.596 bytes |

O DEX diminuiu 2,04%, mesmo com a integração da biblioteca de atualização. O tamanho total do AAB passou de 110.972.442 para 111.083.727 bytes; a maior parte do pacote contém código Flutter e bibliotecas nativas. Essas métricas não equivalem a um benchmark de fluidez nem antecipam a porcentagem que a Play Console calculará.

As classes JSON referenciadas por JNI mantêm seus nomes no mapeamento final. As regras de Mapbox mantêm os membros da interface nativa, permitindo otimização dos corpos de métodos. As regras originais do Gson para reflexão e serialização continuam ativas.

O Android usa `EdgeToEdge.enable()` e o modo de ponta a ponta do Flutter. Os recuos inferiores do conteúdo e o cabeçalho customizado foram ajustados; a folha do rastreamento respeita a barra de status e a altura disponível.

Foi preparado um APK isolado para verificar mapa, endereço e recuos no aparelho Android 16, preservando a instalação da Play Store. O Android recusou a instalação com `INSTALL_FAILED_USER_RESTRICTED`. Portanto, o novo build não foi validado visualmente no aparelho; os testes de recuos e responsividade desta entrega são automatizados. A instalação existente e seus dados permaneceram intactos.

## Artefatos

- Build AAB e APK de produção concluído com a chave de upload configurada.
- `bundletool validate` aprovado; manifesto com minSdk 24, targetSdk 36 e depuração desabilitada.
- Certificado do AAB conferido com a chave de upload; APK com a mesma assinatura verificada.
- 21 bibliotecas ELF inspecionadas; todas as bibliotecas de 64 bits compatíveis com alinhamento de 16 KB.
- Quatro APKs derivados do bundle e o APK de teste arm64 aprovados no `zipalign -P 16`.
- Mapeamento R8 e nove arquivos de símbolos nativos extraídos do próprio AAB.
- Varredura do AAB sem os valores privados de pagamento e chaves privilegiadas presentes na configuração local.
- Certificado público SHA-256: `F2:0B:0B:5E:A2:AA:7A:44:C6:FE:17:5E:74:C4:E0:45:3D:6D:50:4B:D9:80:19:29:4F:10:2C:A6:85:31:9F:D9`.

A oferta e a instalação real de uma atualização pela Google Play exigem duas versões elegíveis na mesma faixa de teste. Os testes locais validam o comportamento do bloqueio, mas não substituem esse teste de distribuição. Consulte [o procedimento de publicação](README.md).
