FROM ubuntu:noble

LABEL Description="Base development environment (Linux Desktop & Android 9+) for Qt 6.12.0"

ARG QT_WEBKIT
ARG QT_WEBENGINE
ARG QT_VERSION=6.12.0
ARG TARGETARCH
ARG BUILD_TAG
ARG QTCREATOR_URL
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG TZ=Europe/Moscow

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

COPY sources.list_noble /etc/apt/sources.list.d/ubuntu.sources

# 1. Слой: Базовые инструменты сборки, отладки и Python
RUN echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/90nolanguages \
 && echo 'APT::Get::Install-Recommends "false";' > /etc/apt/apt.conf.d/99nosuggest \
 && echo 'APT::Get::Install-Suggests "false";' >> /etc/apt/apt.conf.d/99nosuggest \
 && apt-get update && apt-get -y upgrade \
 && apt-get install -y --no-install-recommends \
    ssh-clients \
    software-properties-common gnupg ca-certificates apt-transport-https \
    build-essential cmake ninja-build git wget curl gdb lldb ccache \
    flex bison gperf perl ruby zstd lzip autoconf libtool \
    tzdata locales sudo iputils-ping mc xclip rsync micro \
    cppcheck clang-format clang-tidy strace valgrind \
    python3 python3-dev python3-pip python3-venv python3-html5lib \
 && add-apt-repository -y ppa:deadsnakes/ppa \
 && apt-get update \
 && apt-get install -y --no-install-recommends libpython3.11 \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Слой: Графический стек (X11, Wayland, OpenGL, Vulkan, PipeWire, Qt6 deps)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libx11-dev libx11-xcb-dev libxext-dev libxfixes-dev \
    libxi-dev libxrender-dev libxrandr-dev libxcursor-dev \
    libxcomposite-dev libxdamage-dev libxkbcommon-dev libxkbcommon-x11-dev \
    libxft-dev libxinerama-dev libxtst-dev libxkbfile-dev \
    libxcb1-dev libxcb-cursor0 libxcb-dri2-0-dev libxcb-glx0-dev \
    libxcb-icccm4-dev libxcb-image0-dev libxcb-keysyms1-dev \
    libxcb-randr0-dev libxcb-render0-dev libxcb-render-util0-dev \
    libxcb-shape0-dev libxcb-shm0-dev libxcb-sync-dev \
    libxcb-util-dev libxcb-xfixes0-dev libxcb-xinerama0-dev \
    libxcb-xinput-dev libxcb-xkb-dev libxcb-xtest0-dev \
    libwayland-dev wayland-protocols \
    libegl1-mesa-dev libgles2-mesa-dev libgbm-dev libdrm-dev \
    libgl1-mesa-dev libglu1-mesa-dev freeglut3-dev libepoxy-dev \
    libvulkan-dev glslang-tools spirv-tools \
    libcairo2-dev libpixman-1-dev libpango1.0-dev \
    libgtk-3-dev libglib2.0-dev libatk1.0-dev libatk-bridge2.0-dev \
    libatspi2.0-dev libgdk-pixbuf-2.0-dev \
    libpulse-dev libasound2-dev libasound2-plugins \
    pulseaudio-utils pipewire-alsa libpipewire-0.3-dev libspa-0.2-dev \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libgstreamer-plugins-good1.0-dev \
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev \
    libva-dev libvpx-dev libwebp-dev libwebpmux3 libjpeg-dev libpng-dev libtiff-dev \
    libfreetype-dev libfontconfig1-dev libharfbuzz-dev libicu-dev \
    libdbus-1-dev libudev-dev libcap-dev libsystemd-dev \
    libssl-dev libssl3 openssl libsqlite3-dev libnss3-dev libnspr4-dev \
    default-libmysqlclient-dev libprotobuf-dev libprotoc-dev \
    libdouble-conversion-dev libpcre2-dev libzstd-dev libb2-dev \
    libminizip-dev libmng-dev libsctp-dev libsnappy-dev liblzo2-2 \
 && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*

# 3. Слой: Зависимости для сборки Android (Java 21)
RUN mkdir -p /usr/share/man/man1 \
 && apt-get update && apt-get install -y --no-install-recommends \
    openjdk-21-jdk-headless protobuf-compiler xmlstarlet maven \
 && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*

# Переменные окружения
ENV TERM=xterm-color \
    TZ=Europe/Moscow \
    LD_LIBRARY_PATH=/usr/local/lib \
    DISPLAY=:0 \
    PERSIST=1 \
    PS1="\u@${BUILD_TAG}:\w\$ " \
    HOME=/home/developer \
    XAUTHORITY=/home/developer/.Xauthority

ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    JRE_CACERTS_PATH=/opt/java/openjdk/lib/security/cacerts \
    JAVA_VERSION="jdk-21.0.10" 

ENV OPENSSL_ROOT_DIR="/opt/android-sdk/android_openssl/ssl_3"

ENV ANDROID_HOME="/opt/android-sdk" \
    ANDROID_SDK_ROOT="/opt/android-sdk" \
    ANDROID_NDK_ROOT="/opt/android-sdk/ndk/27.2.12479018" \
    ANDROID_NDK_PLATFORM="android-28" \
    ANDROID_API_VERSION="android-36" \
    ANDROID_BUILD_TOOLS_REVISION="36.0.0"

# Для CMake Qt6 QT_HOST_PATH должен указывать строго на десктопный Qt
ENV QT_HOST_PATH="/opt/qt/v${QT_VERSION}/gcc_64" \
    QT_PLUGIN_PATH="/opt/qt/v${QT_VERSION}/gcc_64/plugins" \
    QML_IMPORT_PATH="/opt/qt/v${QT_VERSION}/gcc_64/qml" \
    QML2_IMPORT_PATH="/opt/qt/v${QT_VERSION}/gcc_64/qml" \
    QT_QPA_FONTDIR="/usr/share/fonts/truetype"

ENV PATH="/opt/bin:/opt/qt-creator/bin:/opt/qt/v${QT_VERSION}/gcc_64/bin:/opt/qt/v${QT_VERSION}/android_arm64_v8a/bin:${JAVA_HOME}/bin:${PATH}"

# Локали, таймзона, ccache и ldconfig
RUN sed -i -e 's/# ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen \
 && sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
 && locale-gen \
 && update-locale LANG=ru_RU.UTF-8 LC_ALL=ru_RU.UTF-8 \
 && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo ${TZ} > /etc/timezone \
 && echo "/opt/qt/v${QT_VERSION}/gcc_64/lib" >> /etc/ld.so.conf.d/x86_64-linux-gnu.conf \
 && echo "/opt/qt/v${QT_VERSION}/android_arm64_v8a/lib" >> /etc/ld.so.conf.d/x86_64-linux-gnu.conf \
 && /sbin/ldconfig \
 && printf 'pcm.!default { type pulse fallback "sysdefault" }\nctl.!default { type pulse }\n' > /etc/asound.conf

ENV LANG=ru_RU.UTF-8 \
    LC_ALL=ru_RU.UTF-8 \
    CCACHE_MAXSIZE=20G \
    CCACHE_COMPRESS=1 \
    CCACHE_COMPRESSLEVEL=6

# Создание пользователя developer
RUN if [ ${USER_ID:-0} -ne 0 ] && [ ${GROUP_ID:-0} -ne 0 ]; then \
        deluser --remove-home ubuntu || true; \
        groupadd -g ${GROUP_ID} developer; \
        useradd -u ${USER_ID} -g ${GROUP_ID} -m -s /bin/bash developer; \
        usermod -aG sudo,audio developer; \
        echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers; \
    fi

USER developer
WORKDIR /home/developer

ENTRYPOINT []
CMD ["/bin/bash", "-l", "-i"]

