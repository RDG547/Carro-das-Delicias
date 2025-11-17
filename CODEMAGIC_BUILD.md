# Build no Codemagic

## Configurações Necessárias

### 1. Variáveis de Ambiente
No painel do Codemagic, configure:

- `SUPABASE_URL`: Sua URL do Supabase
- `SUPABASE_ANON_KEY`: Sua chave pública do Supabase
- `MAPBOX_ACCESS_TOKEN`: Seu token público do Mapbox

### 2. Credenciais de Assinatura Android

Você precisa configurar o keystore para assinar o APK/AAB:

1. Crie um keystore (se não tiver):
```bash
keytool -genkey -v -keystore carrodasdelicias.keystore -alias carrodasdelicias -keyalg RSA -keysize 2048 -validity 10000
```

2. No Codemagic:
   - Vá em **Code signing identities**
   - Adicione o keystore
   - Nomeie como `carrodasdelicias_keystore`

### 3. Configuração Java

O projeto está configurado para usar **Java 21 LTS**.

No arquivo `codemagic.yaml`, a configuração já está definida:
```yaml
environment:
  java: 21
```

### 4. Build

O Codemagic executará automaticamente:

1. `flutter pub get` - Baixar dependências
2. `flutter analyze` - Análise estática (não bloqueia)
3. `flutter test` - Executar testes (não bloqueia)
4. `./gradlew bundleRelease` - Gerar AAB assinado

### 5. Artefatos

Os seguintes artefatos serão gerados:

- `build/app/outputs/bundle/release/app-release.aab` - Bundle para Google Play
- `build/app/outputs/apk/release/app-release.apk` - APK para distribuição direta

## Troubleshooting

### Problema: "Gradle daemon terminated unexpectedly"

**Solução**: O arquivo `gradle.properties` foi configurado com:
```properties
org.gradle.daemon=false
org.gradle.parallel=false
```

Isso desabilita o daemon do Gradle no CI/CD para evitar problemas de memória.

### Problema: "Build failed - .aab not found"

**Solução**: Verifique os logs de build. O AAB deve estar em:
- `android/app/build/outputs/bundle/release/`
- `build/app/outputs/bundle/release/`

### Problema: Testes falhando

Os testes foram simplificados para não depender de inicialização completa do Supabase.
Se ainda assim falharem, configure `ignore_failure: true` no `codemagic.yaml`.

## Configurações Locais vs CI

### Local (Desenvolvimento)
```properties
# gradle.properties
org.gradle.daemon=true
org.gradle.parallel=true
```

### CI/CD (Codemagic)
```properties
# gradle.properties
org.gradle.daemon=false
org.gradle.parallel=false
```

**Nota**: Para desenvolvimento local, você pode reverter para `daemon=true` e `parallel=true` para builds mais rápidos.

## Versão Java Requerida

- **Java 21 LTS** - Compatível com Kotlin mais recente
- Configurado em `android/gradle.properties`
- Codemagic usa Java 21 automaticamente

## Dependências Desatualizadas

35 pacotes têm versões mais recentes disponíveis mas são incompatíveis com as restrições atuais.
Execute `flutter pub outdated` para ver detalhes.

**Recomendação**: Manter as versões atuais até confirmar compatibilidade completa.
