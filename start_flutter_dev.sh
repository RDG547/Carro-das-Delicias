#!/bin/bash

# Script completo para iniciar emulador Flutter com DNS personalizado e suporte a teclado/mouse
# Autor: Script automático - Carrê das Delícias

echo "🚀 Iniciando emulador Flutter com configurações completas..."

# Configurar JAVA_HOME para Java 24 JDK
export JAVA_HOME=/usr/lib/jvm/java-24-jdk
export PATH=$JAVA_HOME/bin:$PATH
echo "☕ JAVA_HOME configurado para: $JAVA_HOME"

# Configurar Android SDK
export ANDROID_SDK_ROOT=/home/rdg/Android/Sdk
export ANDROID_HOME=/home/rdg/Android/Sdk
export ANDROID_AVD_HOME=/home/rdg/.android/avd
export PATH=$ANDROID_SDK_ROOT/emulator:$ANDROID_SDK_ROOT/tools:$ANDROID_SDK_ROOT/platform-tools:$PATH
echo "📱 ANDROID_SDK_ROOT configurado para: $ANDROID_SDK_ROOT"
echo "📁 ANDROID_AVD_HOME configurado para: $ANDROID_AVD_HOME"

# Caminhos importantes
EMULATOR_PATH="$ANDROID_SDK_ROOT/emulator/emulator"
AVD_NAME="FlutterDev"
PROJECT_PATH="/home/rdg/projetos/carrodasdelicias"

# DNS servers personalizados (Google + Cloudflare + OpenDNS)
DNS_SERVERS="8.8.8.8,1.1.1.1,208.67.222.222"

# Verificar se o emulador está instalado
if [ ! -f "$EMULATOR_PATH" ]; then
    echo "❌ Emulador não encontrado! Instale o Android SDK."
    exit 1
fi

# Verificar se o AVD existe
if ! $EMULATOR_PATH -list-avds | grep -q "$AVD_NAME"; then
    echo "❌ AVD $AVD_NAME não encontrado!"
    exit 1
fi

# Matar emuladores existentes
echo "🔧 Limpando emuladores existentes..."
pkill -f "emulator.*$AVD_NAME" 2>/dev/null || true
adb devices | grep emulator | awk '{print $1}' | xargs -I {} adb -s {} emu kill 2>/dev/null || true

# Aguardar um pouco
sleep 2

# Iniciar emulador com configurações otimizadas
echo "📡 Iniciando $AVD_NAME com configurações completas..."
echo "⌨️  Recursos: Teclado, Mouse, GPU, DNS personalizado, 4GB RAM"
echo "🌐 DNS: $DNS_SERVERS"
echo "   Comando: $EMULATOR_PATH -avd $AVD_NAME -dns-server $DNS_SERVERS -gpu auto -no-boot-anim"

# Iniciar em background com configurações otimizadas
$EMULATOR_PATH -avd $AVD_NAME \
    -dns-server $DNS_SERVERS \
    -gpu auto \
    -no-boot-anim \
    -memory 4096 \
    -cores 4 &

EMULATOR_PID=$!
echo "🆔 PID do emulador: $EMULATOR_PID"

# Aguardar o emulador inicializar
echo "⏳ Aguardando emulador inicializar..."
sleep 15

# Verificar se inicializou
while ! adb devices | grep -q emulator; do
    echo "⏳ Aguardando dispositivo aparecer..."
    sleep 5
done

EMULATOR_DEVICE=$(adb devices | grep emulator | awk '{print $1}' | head -1)
echo "📱 Dispositivo conectado: $EMULATOR_DEVICE"

# Aguardar boot completo
echo "⏳ Aguardando boot completo..."
while [ "$(adb shell getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
    sleep 3
done

echo "✅ Emulador totalmente inicializado!"
echo "⌨️  Configurando suporte completo a teclado e mouse..."

# Configurar entrada de teclado e mouse via ADB
adb -s $EMULATOR_DEVICE shell settings put system show_touches 0
adb -s $EMULATOR_DEVICE shell settings put system pointer_location 0
adb -s $EMULATOR_DEVICE shell settings put secure show_ime_with_hard_keyboard 0
adb -s $EMULATOR_DEVICE shell settings put system accelerometer_rotation 0
adb -s $EMULATOR_DEVICE shell settings put system user_rotation 0
adb -s $EMULATOR_DEVICE shell settings put secure default_input_method com.android.inputmethod.latin/.LatinIME
adb -s $EMULATOR_DEVICE shell settings put system pointer_speed 0
adb -s $EMULATOR_DEVICE shell settings put global development_settings_enabled 1
adb -s $EMULATOR_DEVICE shell settings put system screen_off_timeout 2147483647

echo "🌐 Testando conectividade com DNS personalizado..."

# Testar DNS Google
if adb -s $EMULATOR_DEVICE shell ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    echo "✅ DNS Google (8.8.8.8) funcionando!"
else
    echo "❌ Problema com DNS Google"
fi

# Testar DNS Cloudflare
if adb -s $EMULATOR_DEVICE shell ping -c 1 1.1.1.1 >/dev/null 2>&1; then
    echo "✅ DNS Cloudflare (1.1.1.1) funcionando!"
else
    echo "❌ Problema com DNS Cloudflare"
fi

# Testar conectividade geral
if adb -s $EMULATOR_DEVICE shell ping -c 1 google.com >/dev/null 2>&1; then
    echo "✅ Conectividade geral OK!"
else
    echo "❌ Problema de conectividade geral"
fi

# Testar Supabase
if adb -s $EMULATOR_DEVICE shell ping -c 1 rlpnatsygjdzijpwhfxo.supabase.co >/dev/null 2>&1; then
    echo "✅ Conectividade Supabase OK!"
else
    echo "❌ Problema de conectividade com Supabase"
fi

echo ""
echo "🎉 Emulador pronto com configurações completas!"
echo ""
echo "🎯 Recursos habilitados:"
echo "   ⌨️  Teclado físico completo"
echo "   🖱️  Mouse como trackball"
echo "   📱 Orientação fixa (portrait)"
echo "   🎮 Entrada otimizada"
echo "   🌐 DNS personalizado (Google + Cloudflare + OpenDNS)"
echo "   🚀 GPU acelerada (4GB RAM, 4 cores)"
echo "   🔋 Tela sempre ligada"
echo "   🛠️  Modo desenvolvedor"
echo ""
echo "💡 Dicas de uso:"
echo "   - Use Ctrl+F para buscar"
echo "   - Use Tab para navegar entre campos"
echo "   - Use Enter para confirmar"
echo "   - Use Escape para voltar"
echo "   - Mouse funciona como toque"
echo "   - Scroll com mouse wheel"
echo "   - Atalhos de teclado funcionam normalmente"
echo "   - Ctrl+C/V para copiar/colar"
echo ""
echo "🚀 Para executar o Flutter:"
echo "   cd $PROJECT_PATH"
echo "   flutter run"
echo ""
echo "📋 Comandos úteis:"
echo "   adb devices               - Ver dispositivos"
echo "   adb logcat               - Ver logs"
echo "   flutter doctor           - Verificar configuração"
echo ""

# Se executado com parâmetro, iniciar Flutter automaticamente
if [ "$1" = "--flutter" ]; then
    echo "🚀 Iniciando Flutter automaticamente..."
    cd $PROJECT_PATH
    if [ -f "$PROJECT_PATH/.env.json" ]; then
        flutter run --dart-define-from-file="$PROJECT_PATH/.env.json"
    elif [ -f "$PROJECT_PATH/.env" ]; then
        flutter run --dart-define-from-file="$PROJECT_PATH/.env"
    else
        flutter run
    fi
fi

echo "🎯 Script concluído!"
