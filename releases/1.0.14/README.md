# Entrega Android 1.0.14

- Pacote: `com.rdtech.carrodasdelicias`
- Nome da versão: `1.0.14`
- Código da versão: `2026112103` (build anterior: `2026112102`)
- Flutter: `3.50.1`; Dart: `3.14.0`; Gradle: `9.5.0`; AGP: `9.3.1`.
- AAB: `build/app/outputs/bundle/release/app-release.aab`.
- APK para testes arm64: `build/app/outputs/flutter-apk/app-release.apk`.
- Notas para o campo da Play Store: [notas-play-store-pt-BR.txt](notas-play-store-pt-BR.txt).
- Notas completas: [notas-da-versao.md](notas-da-versao.md).

## Gerar novamente

Configure a chave de upload já usada pelo app em `android/key.properties`, ou as variáveis de assinatura `CM_KEYSTORE_*` e `CM_KEY_*` do Codemagic. Os arquivos de chave e senhas são privados e ignorados pelo Git.

Informe `MAPBOX_ACCESS_TOKEN` público (`pk.`) e `GOOGLE_WEB_CLIENT_ID` em `.env.json` ou no ambiente. O script também aceita as configurações públicas `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `STRIPE_PUBLISHABLE_KEY` e `FIREBASE_*` listadas em `tool/build_android_release.py`. Firebase usa o arquivo nativo existente quando não há configuração Dart explícita.

```sh
python3 tool/build_android_release.py --flutter /caminho/do/flutter --with-apk
```

O script filtra a configuração por uma lista de chaves públicas e remove o arquivo temporário ao terminar. `STRIPE_SECRET_KEY`, `ABACATEPAY_API_KEY` e chaves privilegiadas do Supabase não são repassadas ao build. PIX e cartão em produção usam as Edge Functions existentes no servidor.

## Validação

O resultado final das verificações está em [validacao-2026112103.md](validacao-2026112103.md). Os arquivos binários e logs ficam em `build/`, fora do Git. O pacote de entrega inclui os hashes SHA-256 para conferência de integridade.

## Enviar à Play Store

1. Abra o aplicativo existente no Play Console e crie uma versão na faixa desejada. Para conferir o comportamento no telefone antes da publicação, use a faixa de testes internos.
2. Envie o AAB desta entrega. Confira o pacote, a versão e a chave de upload cadastrada. O código `2026112103` precisa ainda estar disponível no histórico do Play Console; o valor anterior verificado foi o do repositório.
3. Use `1.0.14` como nome da versão e cole o conteúdo de `notas-play-store-pt-BR.txt` no idioma português do Brasil.
4. Mantenha os endereços existentes de [privacidade](https://carrodasdelicias.vercel.app/politica-de-privacidade.html), [termos](https://carrodasdelicias.vercel.app/termos-de-servico.html) e [exclusão de conta](https://carrodasdelicias.vercel.app/excluir-conta.html). As declarações de dados e de localização em segundo plano devem corresponder à operação real do app. Esta entrega não altera respostas do Play Console.
5. Em **Integridade do app > Assinatura de apps**, confira o SHA-256 do **certificado de assinatura do app**. Se o Google Play usa um certificado diferente da chave de upload local, adicione esse SHA-256 ao `website/.well-known/assetlinks.json` e publique o site novamente. O arquivo atual contém os certificados locais de depuração e upload; a página de compartilhamento também oferece abertura por intent e encaminhamento à loja.
6. Execute a análise de pré-lançamento e confira os fluxos de login, recuperação de senha, busca, edição, favoritos, mapa e compartilhamento em um aparelho. A publicação na Play Store é uma etapa posterior ao envio destes arquivos.

Referências oficiais consultadas em 21/11/2026: [API de destino exigida](https://developer.android.com/google/play/requirements/target-sdk), [compatibilidade com páginas de 16 KB](https://developer.android.com/guide/practices/page-sizes), [validação com bundletool](https://developer.android.com/tools/bundletool) e [preparo de uma versão](https://support.google.com/googleplay/android-developer/answer/9859348).
