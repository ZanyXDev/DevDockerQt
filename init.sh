#!/usr/bin/env bash
set -Euo pipefail
set -x  # Раскомментируйте только для отладки
#Пт 10 апр 2026 20:24:21 
# =============================================================================
# 1. Валидация и дефолты критических переменных
# =============================================================================
: "${QT_VERSION:?❌ Error: QT_VERSION is not set. Pass via ENV/ARG.}"
: "${QTCREATOR_URL:?❌ Error: QTCREATOR_URL is not set.}"

export USER_ID="${USER_ID:-1000}"
export GROUP_ID="${GROUP_ID:-1000}"
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export ANDROID_HOME="/opt/android-sdk"
export ANDROID_SDK_ROOT=/opt/android-sdk
export ANDROID_NDK_ROOT=/opt/android-sdk/ndk/27.2.12479018
export CCACHE_MAXSIZE=20G
export CCACHE_COMPRESS=1
export CCACHE_COMPRESSLEVEL=6


echo "📦 Configuring environment: Qt=${QT_VERSION}, UID=${USER_ID}:GID=${GROUP_ID}"

# =============================================================================
# 2. Создание директорий
# =============================================================================
echo '📁 Creating directory structure...'
mkdir -p /opt/download \
	 /opt/bin \
         /ccache/${USER_ID:-1000} \
         /ccache/${USER_ID:-1000}\tmp \
         /usr/local/src/fonts/adobe-fonts/source-code-pro 
         
chown -R "${USER_ID}:${GROUP_ID}" /ccache/${USER_ID:-1000}         
# =============================================================================
# 3. Загрузка и распаковка зависимостей
# =============================================================================
if [ ! -f /opt/.initialized ]; then
    echo '⬇️ Downloading dependencies...'
    declare -a DOWNLOADS=(
        "${QTCREATOR_URL}#/opt/download/qtcreator.deb"
        "https://github.com/google/bundletool/releases/download/1.18.3/bundletool-all-1.18.3.jar#/opt/bin/bundletool-all-1.18.3.jar"
    )
    for item in "${DOWNLOADS[@]}"; do
        IFS='#' read -r url dest <<< "$item"
# Срезаем возможные лишние пробелы в начале и конце строки
    	url=$(echo "$url" | xargs)
    	dest=$(echo "$dest" | xargs)
	wget -v -c -O "$dest" "$url" || { echo "❌ Failed to download $url to $dest"; exit 1; }
    done &
    wait $! || exit 1

    echo '📦 Extracting dependencies...'
    # Безопасная установка .deb 
    apt-get install -y /opt/download/qtcreator.deb 
    echo 'Get ndk ...'
    export LANG=en_EN.UTF-8 
    export DEBIAN_FRONTEND=noninteractive 
    export GOOGLE_ANDROID_MIRROR="https://dl.google.com"
#   apt-get update    
#   apt-get install -y openjdk-17-jdk google-android-cmdline-tools-13.0-installer    
    yes | sdkmanager --sdk_root=${ANDROID_SDK_ROOT} --licenses > /dev/null 2>&1
    yes | sdkmanager --sdk_root=${ANDROID_SDK_ROOT} "platforms;android-36" "platform-tools" "build-tools;36.0.0" 
    yes | sdkmanager --sdk_root=${ANDROID_SDK_ROOT} "ndk;27.2.12479018" 
    yes | sdkmanager --sdk_root=${ANDROID_SDK_ROOT} "cmdline-tools;latest"
    yes | sdkmanager --sdk_root=${ANDROID_SDK_ROOT} "emulator"
    yes | sdkmanager --sdk_root=${ANDROID_SDK_ROOT} "system-images;android-36;google_apis_playstore;x86_64"
#    apt-get remove -y --purge openjdk-17-jdk google-android-cmdline-tools-13.0-installer 
    touch /opt/.initialized
    echo '✅ Initialization stage complete.'
else
    echo 'ℹ️ Already initialized. Skipping download/extract.'
fi

# =============================================================================
# 4. Git-репозитории и субмодули
# =============================================================================
if [ ! -f /opt/.cloned ]; then
    echo '🔧 Initializing git repositories...'
    git config --global --add safe.directory '*'

    clone_or_pull() {
        local repo="$1" target="$2"
        if [[ -d "${target}/.git" ]]; then
            echo "   ⬆️ Updating $(basename "$target")..."
            git -C "$target" pull --ff-only
        else
            echo "   📥 Cloning $(basename "$target")..."
            rm -rf "$target"
            git clone --depth 1 "$repo" "$target"
        fi
    }

    clone_or_pull "https://github.com/KDAB/android_openssl.git" "/opt/android-sdk/android_openssl"
    clone_or_pull "https://github.com/adobe-fonts/source-code-pro.git" "/usr/local/src/fonts/adobe-fonts/source-code-pro"

    echo "📥 Cloning Qt[${QT_VERSION}]..."
    if [[ -d "/usr/local/src/qt5/.git" ]]; then
        git -C /usr/local/src/qt5 fetch origin v"${QT_VERSION}"        
    else
        rm -rf /usr/local/src/qt5
        git clone --branch v"${QT_VERSION}" https://invent.kde.org/qt/qt/qt5.git /usr/local/src/qt5
    fi
echo "   Модуль     |   Статус в Qt 6             Что это было                                      Альтернатива / Решение                                           Рекомендация "
echo "qtcanvas3d    | ❌ Удалён в Qt 5.13     WebGL-based 3D через QML                        ✅ Qt Quick 3D                                                        -skip qtcanvas3d"
echo "qtfeedback    | ⚠️ Не поддерживается   Тактильная обратная связь (вибрация)            ✅ QFeedbackHapticsEffect в Qt Sensors или native Android API         -skip qtfeedback"
echo "qtgamepad     | ⚠️ Не в оф.сборке      Поддержка геймпадов                             ✅ qtgamepadlegacy (community port) или native input                   -skip qtgamepad" 
echo "qtpim         | ❌ Удалён               Personal Information Management                 ✅ Использовать Android APIs или Qt Contacts из Qt 5 (не портирован)  -skip qtpim"
echo "qtsystems     | ❌ Удалён               Доступ к системной информации (батарея,сеть)    ✅ QSysInfo,QNetworkInformation,native Android APIs                   -skip qtsystems"
echo "qtwebglplugin | ⚠️ Экспериментальный   QPA-плагин для рендеринга через WebGL в браузере ✅ Не нужен для native Android/Linux                                 -skip qtwebglplugin"
echo "qtxmlpatterns | ❌ Удалён в Qt 6.0      XPath/XQuery/XML Schema валидация               ✅ QXmlStreamReader/QXmlStreamWriter или библиотеки (libxml2,pugixml)-skip qtxmlpatterns"
echo "qtrepotools   | 🔧 Внутренний          Инструменты для сборки репозитория Qt            ✅ Не нужен для конечной сборки приложений                            -skip qtrepotools"
    cd /usr/local/src/qt5 \
    && git submodule deinit -f --all \
    && git config submodule.qtwebengine.active false \
    && git config submodule.qtdoc.active false \
    && git config submodule.qttranslations.active false \
    && git config submodule.qtcanvas3d.active false \
    && git config submodule.qtfeedback.active false \
    && git config submodule.qtgamepad.active false \
    && git config submodule.qtpim.active false \
    && git config submodule.qtrepotools.active false \
    && git config submodule.qtsystems.active false \
    && git config submodule.qtwebglplugin.active false \
    && git config submodule.qtxmlpatterns.active false \
    && git config submodule.qttranslations.update none \
    && git config submodule.qtdoc.update none \
    && git config submodule.qtwebengine.update none \
    && git config submodule.qtcanvas3d.update none \
    && git config submodule.qtfeedback.update none \
    && git config submodule.qtgamepad.update none \
    && git config submodule.qtpim.update none \
    && git config submodule.qtrepotools.update none \
    && git config submodule.qtsystems.update none \
    && git config submodule.qtwebglplugin.update none \
    && git config submodule.qtxmlpatterns.update none 
    git submodule update --init --recursive
    touch /opt/.cloned
    echo '✅ Git stage complete.'
else
    echo 'ℹ️ Already cloned. Skipping git.'
fi

# =============================================================================
# 5. Сборка Qt6 для AMD64
# =============================================================================

if [ ! -f /opt/.builded_amd64 ]; then
    echo '🔨 Building Qt6 for amd64...'
    rm -rf /tmp/build_qt5_amd64
    mkdir -p /tmp/build_qt5_amd64
    cd /tmp/build_qt5_amd64
    # Unset ВСЕ переменные, связанные с кросс-компиляцией и путями Qt
    unset QT_HOST_PATH
    unset QT_PLUGIN_PATH
    unset QML_IMPORT_PATH
    unset QML2_IMPORT_PATH
    unset ANDROID_NDK_ROOT
    unset ANDROID_SDK_ROOT
    unset ANDROID_HOME
    unset ANDROID_API_VERSION
    # (Опционально) Убрать Android из PATH, чтобы не подхватились инструменты
    export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v android | tr '\n' ':' | sed 's/:$//')
    # Run configure 
    /usr/local/src/qt5/configure \
        -ccache \
        -prefix "/opt/qt/v${QT_VERSION}/gcc_64" \
        -release \
        -opensource -confirm-license \
        -nomake examples -nomake tests \
        -feature-openssl \
        -skip qtcanvas3d -skip qtfeedback -skip qtgamepad -skip qtpim \
        -skip qtsystems -skip qtwebglplugin -skip qtxmlpatterns -skip qtrepotools \
        -skip qt3d -skip qtquick3d -skip qtwebengine -skip qtwebview \
        -skip qtdoc -skip qttranslations -skip qtlottie -skip qtscxml \
        -skip qtspeech -skip qtvirtualkeyboard -skip qtactiveqt

    cmake --build . --parallel $(($(nproc)))
    cmake --install .
    cp config.summary /opt/qt/v${QT_VERSION}/gcc_64
    touch /opt/.builded_amd64
    echo '✅ amd64 build complete.'
else
    echo 'ℹ️ Already built for amd64. Skipping.'
fi

# =============================================================================
# 6. Сборка Qt6 для Android
# =============================================================================
if [ ! -f /opt/.build_android_arm64_v8a ]; then
    # Unset ВСЕ переменные, связанные с кросс-компиляцией и путями Qt
    unset QT_HOST_PATH
    unset QT_PLUGIN_PATH
    unset QML_IMPORT_PATH
    unset QML2_IMPORT_PATH
    echo '🔨 Building Qt6 for android_arm64_v8a...'
    rm -rf /tmp/build_qt5_android_arm64_v8a
    mkdir -p /tmp/build_qt5_android_arm64_v8a
    alias bundletool='java -jar /opt/bundletool-all-1.18.3.jar'
    cd /tmp/build_qt5_android_arm64_v8a
    /usr/local/src/qt5/configure \
    -verbose -release -nomake examples -nomake tests \
    -prefix /opt/qt/v${QT_VERSION}/android_arm64_v8a \    
    -android-ndk $ANDROID_NDK_ROOT \
    -android-sdk $ANDROID_SDK_ROOT \
    -qt-host-path /opt/qt/v${QT_VERSION}/gcc_64 \
    -android-abis arm64-v8a -- \
    -skip qttasktree -skip qtpdf \
    -skip qtcanvas3d -skip qtfeedback -skip qtgamepad -skip qtpim \
    -skip qtsystems -skip qtwebglplugin -skip qtxmlpatterns -skip qtrepotools \
    -skip qt3d -skip qtquick3d -skip qtwebengine -skip qtwebview \
    -skip qtdoc -skip qttranslations -skip qtlottie -skip qtscxml \
    -skip qtspeech -skip qtvirtualkeyboard -skip qtactiveqt \
    -DOPENSSL_INCLUDE_DIR=/opt/android-sdk/android_openssl/ssl_3/include \
    -DOPENSSL_LIBRARIES=/opt/android-sdk/android_openssl/ssl_3/arm64-v8a 
    
    cmake --build . --parallel $(($(nproc)))
    cmake --install .
    cp config.summary /opt/qt/v${QT_VERSION}/android_arm64_v8a   
    touch /opt/.builded_android_arm64_v8a
    echo '✅ Android build complete.'
else
    echo 'ℹ️ Already built for Android. Skipping.'
fi

# =============================================================================
# 7. Финализация
# =============================================================================
echo '👤 Applying ownership permissions...'
chown -R "${USER_ID}:${GROUP_ID}" /opt
echo '🎉 Initialization & Build finished successfully.'
