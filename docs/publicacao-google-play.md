# Publicação Android na Google Play

A branch `main` aciona o workflow **Carro das Delícias na Google Play**. Alterações exclusivamente na documentação e nas notas de versão ficam fora do gatilho. O workflow roda a análise do Dart e os testes do Flutter, Python e Node antes de compilar. As execuções de produção são serializadas.

## Configuração inicial

1. No projeto Google Cloud **carro-das-delicias**, [ative a Google Play Android Developer API](https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com?project=carro-das-delicias) e crie uma conta de serviço exclusiva para o GitHub Actions. Gere a credencial JSON dessa conta.
2. Em **Usuários e permissões** da Play Console, adicione o e-mail da conta de serviço. Limite o acesso ao **Carro das Delícias** (`com.rdtech.carrodasdelicias`) e conceda visualização de informações do app e liberação para produção.
3. Em **Settings → Environments** do GitHub, crie o ambiente `google-play` e limite a implantação à branch `main`. Cadastre estes segredos no ambiente.

| Secret | Valor |
| --- | --- |
| `PLAY_SERVICE_ACCOUNT_JSON` | Conteúdo do JSON da conta de serviço de publicação. |
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | Chave de **upload** existente em Base64, em uma linha. |
| `CM_KEYSTORE_PASSWORD` | Valor de `storePassword` em `android/key.properties`. |
| `CM_KEY_ALIAS` | Valor de `keyAlias` em `android/key.properties`. |
| `CM_KEY_PASSWORD` | Valor de `keyPassword` em `android/key.properties`. |
| `ANDROID_PUBLIC_CONFIG_JSON` | JSON da configuração pública usada no build Android, incluindo `GOOGLE_WEB_CLIENT_ID` e o token público `MAPBOX_ACCESS_TOKEN` iniciado em `pk.`. |

O GitHub CLI autenticado pode cadastrar os arquivos pela entrada padrão. Execute na raiz do app, com `PLAY_JSON_PATH` apontando para a credencial da conta de publicação.

```bash
gh secret set --env google-play PLAY_SERVICE_ACCOUNT_JSON < "$PLAY_JSON_PATH"
base64 -w 0 android/upload-keystore.jks | gh secret set --env google-play ANDROID_UPLOAD_KEYSTORE_BASE64
python3 -c 'import json, sys; from pathlib import Path; sys.path.insert(0, "tool"); from build_android_release import public_configuration; print(json.dumps(public_configuration(Path(".env.json"))))' |
  gh secret set --env google-play ANDROID_PUBLIC_CONFIG_JSON
```

4. Em **Actions → Carro das Delícias na Google Play → Run workflow**, escolha a branch `main` e o modo `validate`. O workflow consulta a Play Console e verifica a assinatura do AAB.
5. Após a validação, em **Settings → Secrets and variables → Actions → Variables**, crie a **variável do repositório** `PLAY_AUTO_PUBLISH` com valor `true`. Para disparar a primeira publicação com o código atual da `main`, escolha o modo manual `publish`.
6. Em **Visão geral da publicação** na Play Console, confira o status da publicação gerenciada. Com ela desativada, a Play Store pode liberar a atualização aprovada automaticamente. Com ela ativada, a liberação continua sob controle da Play Console.

## Versão e revisão

O workflow consulta os códigos dos AABs, APKs e releases de todas as faixas da Play Console e considera também o código do `pubspec.yaml`. O código gerado é maior que os códigos encontrados. Os commits do app determinam o incremento da versão. Use títulos em português para gerar as notas `pt-BR`. Os prefixos `fix:` e `feat:` sinalizam correções e recursos novos. Use `feat!:` ou um rodapé `BREAKING CHANGE:` para uma nova versão principal.

O envio usa a faixa de produção com distribuição integral após a aprovação. Se já houver mudanças em revisão, a Play Console pode reiniciar a análise para incluir o novo envio. Para pausar os envios em pushes, defina `PLAY_AUTO_PUBLISH` como `false`. Os testes e o acionamento manual continuam disponíveis.

O resumo de cada execução indica teste concluído, AAB validado, envio para revisão ou falha. Para receber avisos de sucesso e de falha, acompanhe o repositório e habilite **Actions** nas [configurações de notificações do GitHub](https://github.com/settings/notifications).
