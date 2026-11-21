# Entrega Android 1.0.15

- Pacote: `com.rdtech.carrodasdelicias`
- Versão: `1.0.15`; código: `2026112104`.
- AAB assinado: `build/releases/1.0.15/Carro-das-Delicias-1.0.15-2026112104.aab`.
- Notas para a loja: [notas-play-store-pt-BR.txt](notas-play-store-pt-BR.txt).
- Notas completas: [notas-da-versao.md](notas-da-versao.md).
- Verificações técnicas: [validacao.md](validacao.md).

## Publicação

1. No aplicativo existente no Play Console, crie uma versão e envie o AAB. Confira a chave de upload e a disponibilidade do código `2026112104`.
2. Cole as notas em português do Brasil e execute o relatório de pré-lançamento antes da distribuição.
3. Envie também `mapping.txt` e `native-debug-symbols.zip` se a Console solicitar. O AAB inclui o mapeamento e os símbolos nativos.
4. Preserve os endereços existentes de privacidade, termos e exclusão de conta.

## Atualização obrigatória

A consulta usa a biblioteca oficial Google Play In-App Updates, sem depender de uma versão global cadastrada no banco. A disponibilidade corresponde à conta, instalação, aparelho e faixa de distribuição reconhecidos pela Play Store. APKs instalados por fora da loja e plataformas sem essa API continuam funcionando sem uma exigência indevida.

Uma oferta confirmada é guardada localmente para que reiniciar o app sem internet não evite a atualização. Quando a instalação alcança a versão oferecida ou a loja retira a oferta, o bloqueio é liberado. Cancelar uma atualização mantém o aviso, com opção de tentar novamente ou abrir a Play Store. Uma atualização imediata em andamento pode ser retomada ao retornar ao app.

O recurso começa a funcionar nas instalações da **1.0.15**. Ele não pode acrescentar esse aviso a versões anteriores que não possuem o código. Para validar a experiência real da loja, instale a 1.0.15 por uma faixa de teste, disponibilize um build posterior ao mesmo testador e confirme o fluxo. A publicação e a oferta de uma segunda versão no Play Console são necessárias para esse teste; instalar um APK local não comprova a disponibilidade da loja.

Referência: [integração oficial e retomada de atualizações](https://developer.android.com/guide/playcore/in-app-updates/kotlin-java), [teste pela Google Play](https://developer.android.com/guide/playcore/in-app-updates/test).

## Otimização Android

O build usa R8 em modo completo, redução de recursos e regras revisadas para Mapbox Maps 11.31.3 / Common 24.31.3. Os nomes e membros da interface JNI são preservados. As classes JSON usadas pelo código nativo permanecem protegidas; o restante do Gson segue suas próprias regras de serialização.

As substituições são limitadas às versões exatas dos dois artefatos. Ao atualizar o Mapbox, revise novamente suas regras e o mapa em um build de produção. Não remova regras de JNI para aumentar artificialmente os indicadores.

O relatório local do R8 é comparável entre os dois builds; as porcentagens da Play Console dependem da análise do artefato efetivamente publicado.

Referências: [regras de preservação](https://developer.android.com/topic/performance/app-optimization/keep-rules-overview), [filtro de regras por dependência](https://developer.android.com/reference/tools/gradle-api/9.3/com/android/build/api/dsl/KeepRules), [ponta a ponta e recuos](https://developer.android.com/develop/ui/views/layout/edge-to-edge).

## Reproduzir o build

```sh
python3 tool/build_android_release.py --flutter /caminho/do/flutter --with-apk
```

O script usa somente a lista de configurações públicas permitidas. A chave de upload permanece em `android/key.properties` ou nas variáveis privadas de assinatura, fora do Git. Os binários e os logs ficam em `build/`; nenhum dado de conta usado nos testes deve ser publicado.
