# Configuração de Deep Links - Carro das Delícias

## O que foi implementado

O app agora suporta **Deep Linking** para compartilhamento de produtos. Quando um usuário compartilha um produto, é gerado um link no formato:

```
https://carrodasdelicias.app/produto/[ID_DO_PRODUTO]
```

### Funcionalidades

1. **App instalado**: Ao clicar no link, o app abre diretamente na tela do produto
2. **App não instalado**: O usuário é redirecionado para instalar o app (Play Store/App Store)
3. **Compartilhamento**: Links funcionam em WhatsApp, Facebook, Instagram, Twitter/X, etc.

## Arquivos configurados

### Android
- `android/app/src/main/AndroidManifest.xml` - Configurado com:
  - Custom URL Scheme: `carrodasdelicias://`
  - App Links (HTTPS): `https://carrodasdelicias.app`

### iOS
- `ios/Runner/Info.plist` - Configurado com:
  - Custom URL Scheme: `carrodasdelicias://`
  - Universal Links: `https://carrodasdelicias.app`

### Flutter
- `lib/services/deep_link_service.dart` - Serviço que processa os deep links
- `lib/screens/product_detail_screen.dart` - Função de compartilhamento atualizada
- `lib/auth_wrapper.dart` - Inicialização do serviço de deep links

## Configuração do domínio (IMPORTANTE)

Para que os **App Links (Android)** e **Universal Links (iOS)** funcionem corretamente com HTTPS, você precisa hospedar arquivos de verificação no domínio `carrodasdelicias.app`:

### 1. Android App Links

Crie o arquivo `https://carrodasdelicias.app/.well-known/assetlinks.json`:

```json
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "com.carrodasdelicias.app",
    "sha256_cert_fingerprints": [
      "SUBSTITUA_PELA_SUA_SHA256_FINGERPRINT"
    ]
  }
}]
```

**Como obter o SHA256:**
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

### 2. iOS Universal Links

Crie o arquivo `https://carrodasdelicias.app/.well-known/apple-app-site-association`:

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "TEAM_ID.com.carrodasdelicias.app",
        "paths": ["/produto/*"]
      }
    ]
  }
}
```

Substitua `TEAM_ID` pelo seu Apple Developer Team ID.

### 3. Fallback para usuários sem app

Crie uma página em `https://carrodasdelicias.app/produto/[id]` que:
- Detecta se é mobile e redireciona para as lojas
- Mostra informações do produto para desktop
- Exemplo de redirecionamento:

```html
<!DOCTYPE html>
<html>
<head>
    <title>Carro das Delícias - Produto</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
</head>
<body>
    <h1>Carro das Delícias</h1>
    <p>Baixe nosso app para ver este produto!</p>

    <script>
        const userAgent = navigator.userAgent || navigator.vendor || window.opera;

        // Detectar Android
        if (/android/i.test(userAgent)) {
            window.location.href = 'https://play.google.com/store/apps/details?id=com.carrodasdelicias.app';
        }
        // Detectar iOS
        else if (/iPad|iPhone|iPod/.test(userAgent) && !window.MSStream) {
            window.location.href = 'https://apps.apple.com/app/id[SEU_APP_ID]';
        }
    </script>
</body>
</html>
```

## Testando os Deep Links

### Durante desenvolvimento

1. **Custom URL Scheme** (funciona imediatamente):
   ```
   carrodasdelicias://produto/123
   ```

2. **Teste no terminal**:
   ```bash
   # Android
   adb shell am start -W -a android.intent.action.VIEW -d "carrodasdelicias://produto/123"

   # iOS (Simulator)
   xcrun simctl openurl booted "carrodasdelicias://produto/123"
   ```

### Após configurar o domínio

1. **HTTPS URLs**:
   ```
   https://carrodasdelicias.app/produto/123
   ```

2. **Teste compartilhando**:
   - Compartilhe um produto via WhatsApp
   - Clique no link compartilhado
   - O app deve abrir automaticamente

## Alternativas sem domínio próprio

Se não tiver um domínio próprio, pode usar:

1. **Firebase Dynamic Links** (gratuito)
2. **Branch.io** (tem plano gratuito)
3. **Apenas Custom URL Scheme** (funciona, mas não abre em navegador)

## Próximos passos

1. ✅ Código implementado
2. ⏳ Registrar domínio `carrodasdelicias.app`
3. ⏳ Configurar arquivos `.well-known/`
4. ⏳ Criar página de fallback
5. ⏳ Publicar app nas lojas
6. ⏳ Testar links em produção
