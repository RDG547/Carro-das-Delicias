# Validação da versão 1.0.16

Verificações em 22/11/2026. Pacote `com.rdtech.carrodasdelicias`, versão `1.0.16`, código `2026112201`. Flutter 3.50.1, Dart 3.14, AGP 9.3.1 e Gradle 9.5.0.

## Funcionalidade

- 70 testes Flutter aprovados, incluindo os fluxos existentes e os casos desta entrega.
- 3 testes Node da página de compartilhamento e 3 testes Python do filtro de configuração de produção aprovados.
- Quatro arquivos WAV conferidos quanto a formato, duração inferior a um segundo e amplitude sem saturação.
- Análise Dart sem erros ou avisos; mensagens informativas de depreciação e estilo permanecem no projeto.

Os casos novos verificam o destinatário e a codificação do email, espaços e acentos, preenchimento básico sem valores nulos, abertura da foto sem acionar o card, ausência de visualizador em produtos sem foto, zoom e fechamento da galeria, igualdade de tamanho dos três botões de exportação em larguras de 260/320/600 px, ações da entrega em fonte normal e ampliada e expansão/recolhimento da barra do rastreamento.

As categorias têm testes de atualizações consecutivas sem escrita de ordem, ordenação determinística dos dados recebidos, rolagem sem pressão longa e reordenação deliberada por pressão longa no card. A lista mantém o identificador do item arrastado e adia as recargas até a conclusão do drop. Um novo carregamento reinicializa o estado visual interno da lista, preservando o controlador de rolagem. O modal usa o mesmo componente.

Também foi impedido salvar a sequência antes de a soltura terminar. Após essa proteção, os seis testes de interação de categorias e rastreamento foram executados novamente e passaram. Uma consulta ao Supabase confirmou nove posições únicas e ausência de divergências entre `ordem` e `order`; a sequência em produção foi preservada.

Os botões de limpar carrinho acionam o som somente após a confirmação do usuário. A limpeza interna durante o checkout não emite esse efeito. O som de compra está nos caminhos de sucesso, com deduplicação pelo identificador do pedido, inclusive ao retornar das telas de pagamento. Não foram criados pedidos reais, realizadas cobranças ou enviados emails para testar estes ajustes.

O visualizador de fotos é o mesmo componente usado nos detalhes dos produtos. Foram preservados a animação dos cards, os controles de compra e os favoritos. O painel de rastreamento preserva o estado da câmera e a interpretação corrigida dos dados de endereço.

Não houve alteração do esquema do banco. Os testes de interação e responsividade foram automatizados; não havia aparelho conectado para uma verificação física nesta entrega.

## Artefatos Android

O pacote de entrega contém o AAB e o APK assinados, certificado público, mapeamento R8, símbolos nativos, notas, documentação e manifesto de integridade. Os registros da validação de assinatura, manifesto, biblioteca ELF, alinhamento e varredura de configuração ficam em `build/releases/1.0.16/`, fora do Git.

- `bundletool validate` aprovado; manifesto com minSdk 24, targetSdk 36 e depuração desabilitada.
- Assinaturas do AAB e APK conferidas com a chave de upload configurada.
- 21 bibliotecas ELF inspecionadas, com alinhamento de 16 KB em todas as bibliotecas de 64 bits.
- Quatro APKs derivados do bundle e o APK arm64 aprovados na verificação de alinhamento de 16 KB.
- Nove arquivos de símbolos nativos e o mapeamento R8 extraídos do próprio AAB.
- AAB sem os valores privados de pagamento e chaves privilegiadas presentes na configuração local.
- Os quatro efeitos WAV estão presentes e íntegros tanto no AAB quanto no APK.
