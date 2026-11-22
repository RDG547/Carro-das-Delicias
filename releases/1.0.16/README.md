# Entrega Android 1.0.16

- Pacote: `com.rdtech.carrodasdelicias`.
- Versão: `1.0.16`; código: `2026112201`.
- AAB: `build/releases/1.0.16/Carro-das-Delicias-1.0.16-2026112201.aab`.
- [Notas para a Play Store](notas-play-store-pt-BR.txt), [notas completas](notas-da-versao.md) e [validação técnica](validacao.md).

## Publicação

Envie o AAB ao aplicativo existente no Play Console, confira a chave de upload e a disponibilidade do código `2026112201` e cole as notas em português do Brasil. O pacote de entrega inclui o mapeamento R8, os símbolos nativos, o certificado público e os hashes SHA-256. O AAB também contém o mapeamento e os símbolos.

A atualização obrigatória baseada na oferta individual da Play Store, introduzida na 1.0.15, permanece ativa. Para testar o fluxo completo, o testador precisa ter instalado a 1.0.15 pela loja e receber a oferta desta versão na mesma faixa. A disponibilidade depende da distribuição no Play Console.

## Reproduzir

```sh
python3 tool/build_android_release.py --flutter /caminho/do/flutter --with-apk
```

O build usa somente configurações públicas permitidas pelo script e a chave privada de upload já configurada fora do Git. As regras de R8 e a compatibilidade com páginas de 16 KB da versão anterior foram preservadas.

Os efeitos sonoros são originais e estão em `assets/sounds/`; podem ser reproduzidos por `python3 tool/generate_app_sounds.py`. Não usam gravações de terceiros.
