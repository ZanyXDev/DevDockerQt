#!/usr/bin/env bash
set -Euo pipefail
#set -x  # Раскомментируйте только для отладки
# =============================================================================
# 0. Интерактивное меню для выборочного запуска этапов
# =============================================================================

# Флаги для пропуска этапов (по умолчанию все включены)
RUN_SETUP_ENV="${RUN_SETUP_ENV:-1}"
RUN_CREATE_DIRS="${RUN_CREATE_DIRS:-1}"
RUN_DOWNLOAD_DEPS="${RUN_DOWNLOAD_DEPS:-1}"
RUN_GIT_REPOS="${RUN_GIT_REPOS:-1}"
RUN_BUILD_AMD64="${RUN_BUILD_AMD64:-1}"
RUN_BUILD_ANDROID="${RUN_BUILD_ANDROID:-1}"
RUN_FINALIZE="${RUN_FINALIZE:-1}"

show_menu() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  🛠️  Qt6 Builder — Выбор этапов выполнения                 ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Текущие настройки:"
    echo "  [1] Setup Env        : $([ "$RUN_SETUP_ENV" = "1" ] && echo '✅' || echo '⏭️')"
    echo "  [2] Create Dirs      : $([ "$RUN_CREATE_DIRS" = "1" ] && echo '✅' || echo '⏭️')"
    echo "  [3] Download Deps    : $([ "$RUN_DOWNLOAD_DEPS" = "1" ] && echo '✅' || echo '⏭️')"
    echo "  [4] Git Repos        : $([ "$RUN_GIT_REPOS" = "1" ] && echo '✅' || echo '⏭️')"
    echo "  [5] Build AMD64      : $([ "$RUN_BUILD_AMD64" = "1" ] && echo '✅' || echo '⏭️')"
    echo "  [6] Build Android    : $([ "$RUN_BUILD_ANDROID" = "1" ] && echo '✅' || echo '⏭️')"
    echo "  [7] Finalize         : $([ "$RUN_FINALIZE" = "1" ] && echo '✅' || echo '⏭️')"
    echo ""
    echo "  [A] Все этапы (по умолчанию)"
    echo "  [N] Ничего не делать (только показать меню)"
    echo "  [0] Выход"
    echo ""
    echo "💡 Подсказка: введите номер этапа для переключения (✅/⏭️),"
    echo "   или 'A' для выбора всех, '0' для запуска."
    echo -n "Ваш выбор: "
}

toggle_stage() {
    local stage="$1"
    local var="RUN_${stage}"
    if [[ "${!var}" = "1" ]]; then
        export "$var"=0
        echo "⏭️  Этап $stage пропущен"
    else
        export "$var"=1
        echo "✅  Этап $stage включён"
    fi
}

# Обработка аргументов командной строки для автоматизации
if [[ "${1:-}" == "--menu" ]]; then
    while true; do
        show_menu
        read -r choice
        case "$choice" in
            1) toggle_stage "SETUP_ENV" ;;
            2) toggle_stage "CREATE_DIRS" ;;
            3) toggle_stage "DOWNLOAD_DEPS" ;;
            4) toggle_stage "GIT_REPOS" ;;
            5) toggle_stage "BUILD_AMD64" ;;
            6) toggle_stage "BUILD_ANDROID" ;;
            7) toggle_stage "FINALIZE" ;;
            [Aa]) 
                export RUN_SETUP_ENV=1 RUN_CREATE_DIRS=1 RUN_DOWNLOAD_DEPS=1
                export RUN_GIT_REPOS=1 RUN_BUILD_AMD64=1 RUN_BUILD_ANDROID=1 RUN_FINALIZE=1
                echo "✅ Все этапы включены"
                ;;
            [Nn])
                export RUN_SETUP_ENV=0 RUN_CREATE_DIRS=0 RUN_DOWNLOAD_DEPS=0
                export RUN_GIT_REPOS=0 RUN_BUILD_AMD64=0 RUN_BUILD_ANDROID=0 RUN_FINALIZE=0
                echo "⏭️  Все этапы пропущены"
                ;;
            0|"") break ;;
            *) echo "❌ Неверный выбор" ;;
        esac
        echo ""; read -p "Нажмите Enter для продолжения..."
        clear
    done
elif [[ "${1:-}" == "--help" ]]; then
    echo "Использование: $0 [--menu|--help|STAGE]"
    echo "  --menu   : интерактивный выбор этапов"
    echo "  --help   : показать эту справку"
    echo "  STAGE    : запустить только указанный этап:"
    echo "             dirs|download|git|build_amd64|build_android|finalize"
    exit 0
fi

# Быстрый запуск одного этапа из командной строки
case "${1:-}" in
    dirs) export RUN_SETUP_ENV=0 RUN_DOWNLOAD_DEPS=0 RUN_GIT_REPOS=0 RUN_BUILD_AMD64=0 RUN_BUILD_ANDROID=0 RUN_FINALIZE=0 ;;
    download) export RUN_SETUP_ENV=0 RUN_CREATE_DIRS=0 RUN_GIT_REPOS=0 RUN_BUILD_AMD64=0 RUN_BUILD_ANDROID=0 RUN_FINALIZE=0 ;;
    git) export RUN_SETUP_ENV=0 RUN_CREATE_DIRS=0 RUN_DOWNLOAD_DEPS=0 RUN_BUILD_AMD64=0 RUN_BUILD_ANDROID=0 RUN_FINALIZE=0 ;;
    build_amd64) export RUN_SETUP_ENV=0 RUN_CREATE_DIRS=0 RUN_DOWNLOAD_DEPS=0 RUN_GIT_REPOS=0 RUN_BUILD_ANDROID=0 RUN_FINALIZE=0 ;;
    build_android) export RUN_SETUP_ENV=0 RUN_CREATE_DIRS=0 RUN_DOWNLOAD_DEPS=0 RUN_GIT_REPOS=0 RUN_BUILD_AMD64=0 RUN_FINALIZE=0 ;;
    finalize) export RUN_SETUP_ENV=0 RUN_CREATE_DIRS=0 RUN_DOWNLOAD_DEPS=0 RUN_GIT_REPOS=0 RUN_BUILD_AMD64=0 RUN_BUILD_ANDROID=0 ;;
esac

# =============================================================================
# 1. Валидация и дефолты критических переменных
# =============================================================================
check_deps() {
    local deps=(wget git cmake)
    for pkg in "${deps[@]}"; do
        command -v "$pkg" >/dev/null 2>&1 || { echo "❌ Требуется: $pkg"; exit 1; }
    done
}
if [[ "$RUN_SETUP_ENV" = "1" ]] && check_deps; then

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
export LANG=en_EN.UTF-8 
export DEBIAN_FRONTEND=noninteractive 
export GOOGLE_ANDROID_MIRROR="https://dl.google.com"    
echo "📦 Configuring environment: Qt=${QT_VERSION}, UID=${USER_ID}:GID=${GROUP_ID}"
else
    echo '⏭️  Skipping setup env (RUN_SETUP_ENV=0)'
fi
# =============================================================================
# 2. Создание директорий
# =============================================================================
if [[ "$RUN_CREATE_DIRS" = "1" ]]; then
    echo '📁 Creating directory structure...'
    mkdir -p /opt/download /opt/bin /ccache/${USER_ID:-1000} /ccache/${USER_ID:-1000}/tmp \
             /usr/local/src/fonts/adobe-fonts/source-code-pro 
    chown -R "${USER_ID}:${GROUP_ID}" /ccache/${USER_ID:-1000}         
else
    echo '⏭️  Skipping directory creation (RUN_CREATE_DIRS=0)'
fi
# =============================================================================
# 3. Загрузка и распаковка зависимостей
# =============================================================================
if [[ "$RUN_DOWNLOAD_DEPS" = "1" ]]; then
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
    done 

    echo '📦 Extracting dependencies...'
    # Безопасная установка .deb 
    apt-get install -y /opt/download/qtcreator.deb 
    echo 'Get ndk ...'

    apt-get update    
    apt-get install -y openjdk-17-jdk google-android-cmdline-tools-13.0-installer    
    yes | sdkmanager --sdk_root=${ANDROID_SDK_ROOT} --licenses > /dev/null 2>&1
    yes | sdkmanager --sdk_root=${ANDROID_SDK_ROOT} "platforms;android-36" "platform-tools" "build-tools;36.0.0" 
    yes | sdkmanager --sdk_root=${ANDROID_SDK_ROOT} "ndk;27.2.12479018" 
    yes | sdkmanager --sdk_root=${ANDROID_SDK_ROOT} "cmdline-tools;latest"
    yes | sdkmanager --sdk_root=${ANDROID_SDK_ROOT} "emulator"
    yes | sdkmanager --sdk_root=${ANDROID_SDK_ROOT} "system-images;android-36;google_apis_playstore;x86_64"
    apt-get remove -y --purge openjdk-17-jdk google-android-cmdline-tools-13.0-installer 
    echo '✅ Initialization stage complete.'
else
    echo '⏭️  Skipping download/extract (RUN_DOWNLOAD_DEPS=0)'
fi
# =============================================================================
# 4. Git-репозитории и субмодули
# =============================================================================
if [[ "$RUN_GIT_REPOS" = "1" ]]; then
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
    echo '✅ Git stage complete.'
else
    echo '⏭️  Skipping git clone (RUN_GIT_REPOS=0)'
fi
# =============================================================================
# 5. Сборка Qt6 для AMD64
# =============================================================================
if [[ "$RUN_BUILD_AMD64" = "1" ]]; then
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
    START_TIME=$(date +%s)
    # Run configure 
/usr/local/src/qt5/configure \
 -ccache \
 -prefix "/opt/qt/v${QT_VERSION}/gcc_64" \
 -release \
 -opensource \
 -confirm-license \
 -nomake examples \
 -nomake tests \
 -feature-openssl \
 -skip qtcanvas3d -skip qtfeedback -skip qtgamepad -skip qtpim \
 -skip qtsystems -skip qtwebglplugin -skip qtxmlpatterns -skip qtrepotools \
 -skip qt3d -skip qtquick3d -skip qtwebengine -skip qtwebview \
 -skip qtdoc -skip qttranslations -skip qtlottie -skip qtscxml \
 -skip qtspeech -skip qtvirtualkeyboard -skip qtactiveqt

   # cmake --build . --parallel $(($(nproc --ignore=1))) 
    cmake --build . -j1
    cmake --install .
    cp config.summary /opt/qt/v${QT_VERSION}/gcc_64
    END_TIME=$(date +%s)
    echo "Build time: $((END_TIME - START_TIME)) seconds" > /opt/qt/v${QT_VERSION}/gcc_64/build.time.log
    echo '✅ amd64 build complete.'
else
    echo '⏭️  Skipping amd64 build (RUN_BUILD_AMD64=0)'
fi
# =============================================================================
# 6. Сборка Qt6 для Android
# ============================================================================
if [[ "$RUN_BUILD_ANDROID" = "1" ]]; then
 # Unset ВСЕ переменные, связанные с кросс-компиляцией и путями Qt
    unset QT_HOST_PATH
    unset QT_PLUGIN_PATH
    unset QML_IMPORT_PATH
    unset QML2_IMPORT_PATH
    export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
    export ANDROID_HOME="/opt/android-sdk"
    export ANDROID_SDK_ROOT=/opt/android-sdk
    export ANDROID_NDK_ROOT=/opt/android-sdk/ndk/27.2.12479018
    apt update
    apt install maven
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
    
#    cmake --build . --parallel $(($(nproc --ignore=1))) 
    cmake --build .  --parallel 1
    cmake --install .
    cp config.summary /opt/qt/v${QT_VERSION}/android_arm64_v8a   
    
    echo '✅ Android build complete.'
else
    echo '⏭️  Skipping android_arm64_v8a build (RUN_BUILD_ANDROID=0)'
fi
# =============================================================================
# 7. Финализация
# =============================================================================
if [[ "$RUN_FINALIZE" = "1" ]]; then
echo '👤 Applying ownership permissions...'
chown -R "${USER_ID}:${GROUP_ID}" /opt
echo '🎉 Initialization & Build finished successfully.'
else
    echo '⏭️  Skipping finalize (RUN_FINALIZE=0)'
fi
