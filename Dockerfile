# ==============================================================================
# ЭТАП 1: BUILDER (Полное окружение для компиляции Qt6 Desktop и Android)
# ==============================================================================
FROM ubuntu:noble AS builder

LABEL Description="Builder stage for Qt 6.12.0 (Desktop & Android)"

ARG QT_VERSION=6.12.0
ARG QTCREATOR_URL
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG TZ=Europe/Moscow

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

COPY sources.list_noble /etc/apt/sources.list.d/ubuntu.sources

# 1. Базовые инструменты сборки и генераторы кода для Qt6
RUN echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/90nolanguages \
 && echo 'APT::Get::Install-Recommends "false";' > /etc/apt/apt.conf.d/99nosuggest \
 && echo 'APT::Get::Install-Suggests "false";' >> /etc/apt/apt.conf.d/99nosuggest \
 && printf 'path-exclude=/usr/share/locale/*\npath-include=/usr/share/locale/ru*\npath-include=/usr/share/locale/en*\npath-include=/usr/share/locale/locale.alias\n' > /etc/dpkg/dpkg.cfg.d/01_nodoc \
 && apt-get update && apt-get -y upgrade \
 && apt-get install -y --no-install-recommends \
    software-properties-common gnupg ca-certificates apt-transport-https \
    build-essential cmake ninja-build git wget curl ccache pkg-config \
    flex bison gperf perl ruby zstd lzip autoconf libtool \
    tzdata locales sudo tmux \
    python3 python3-dev python3-pip python3-venv python3-html5lib \
 && add-apt-repository -y ppa:deadsnakes/ppa \
 && apt-get update \
 && apt-get install -y --no-install-recommends libpython3.11 \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Полный стек -dev зависимостей для сборки Qt6 (X11, Wayland, GTK3, FFmpeg, OpenGL, Vulkan)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libx11-dev libx11-xcb-dev libxext-dev libxfixes-dev \
    libxi-dev libxrender-dev libxrandr-dev libxcursor-dev \
    libxcomposite-dev libxdamage-dev libxkbcommon-dev libxkbcommon-x11-dev \
    libxft-dev libxinerama-dev libxtst-dev libxkbfile-dev \
    libxcb1-dev libxcb-cursor0 libxcb-cursor-dev libxcb-dri2-0-dev libxcb-glx0-dev \
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

# 3. Java 21 для установки Android SDK/NDK в init.sh
RUN mkdir -p /usr/share/man/man1 \
 && apt-get update && apt-get install -y --no-install-recommends \
    openjdk-21-jdk-headless protobuf-compiler xmlstarlet maven \
 && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*

RUN cat << 'EOF' > /usr/local/bin/container-stats.sh
#!/usr/bin/env bash
mem_cur=$(cat /sys/fs/cgroup/memory.current 2>/dev/null || echo 0)
mem_max=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo "max")
mem_cur_gb=$(awk -v c="$mem_cur" 'BEGIN {printf "%.1f", c/1073741824}')
if [[ "$mem_max" == "max" ]]; then
    mem_str="${mem_cur_gb}G"
else
    mem_max_gb=$(awk -v m="$mem_max" 'BEGIN {printf "%.1f", m/1073741824}')
    mem_str="${mem_cur_gb}/${mem_max_gb}G"
fi

swap_cur=$(cat /sys/fs/cgroup/memory.swap.current 2>/dev/null || echo 0)
swap_mb=$(awk -v s="$swap_cur" 'BEGIN {printf "%.0f", s/1048576}')

read -r quota period < /sys/fs/cgroup/cpu.max 2>/dev/null || { quota="max"; period=100000; }
if [[ "$quota" == "max" ]]; then
    cores=$(nproc)
else
    cores=$(awk -v q="$quota" -v p="$period" 'BEGIN {print q/p}')
fi

u1=$(awk '/usage_usec/ {print $2}' /sys/fs/cgroup/cpu.stat 2>/dev/null || echo 0)
t1=$(date +%s%N)
sleep 0.2
u2=$(awk '/usage_usec/ {print $2}' /sys/fs/cgroup/cpu.stat 2>/dev/null || echo 0)
t2=$(date +%s%N)

cpu_pct=$(awk -v u1="$u1" -v u2="$u2" -v t1="$t1" -v t2="$t2" -v c="$cores" 'BEGIN {
    dt = (t2 - t1) / 1000.0;
    if (dt > 0 && c > 0) printf "%.0f", ((u2 - u1) / dt / c) * 100;
    else print "0";
}')

io_str=$(awk '{
    for(i=1;i<=NF;i++) {
        if($i ~ /^rbytes=/) r += substr($i, 8);
        if($i ~ /^wbytes=/) w += substr($i, 8);
    }
} END {
    printf "R:%.1fG W:%.1fG", r/1073741824, w/1073741824
}' /sys/fs/cgroup/io.stat 2>/dev/null)
[[ -z "$io_str" ]] && io_str="R:0G W:0G"

echo "CPU:${cpu_pct}% | RAM:${mem_str} | SWP:${swap_mb}M | IO[${io_str}]"
EOF
RUN chmod +x /usr/local/bin/container-stats.sh \
&&  cat << 'EOF' > /etc/tmux.conf
set -g default-terminal "screen-256color"
set -g mouse on
set -g status-interval 2
set -g status-style bg=colour235,fg=colour136
set -g status-right-length 85
set -g status-right "#[fg=colour81]#(/usr/local/bin/container-stats.sh) #[fg=colour245]| #[fg=colour214]%H:%M:%S "
EOF

ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    ANDROID_HOME="/opt/android-sdk" \
    ANDROID_SDK_ROOT="/opt/android-sdk" \
    ANDROID_NDK_ROOT="/opt/android-sdk/ndk/27.2.12479018"

CMD ["tmux", "new-session", "-A", "-s", "dev"]


# ==============================================================================
# ЭТАП 2: RUNTIME / DEV-IDE (Облегчённый образ для Qt Creator и сборки проектов)
# ==============================================================================
FROM ubuntu:noble AS runtime

LABEL Description="Lightweight Dev Environment (Qt Creator + Desktop & Android App Build) for Qt 6.12.0"

ARG QT_VERSION=6.12.0
ARG BUILD_TAG
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG TZ=Europe/Moscow

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

COPY sources.list_noble /etc/apt/sources.list.d/ubuntu.sources

# 1. Инструменты разработки, отладки и сборки пользовательских C++ приложений
RUN echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/90nolanguages \
 && echo 'APT::Get::Install-Recommends "false";' > /etc/apt/apt.conf.d/99nosuggest \
 && echo 'APT::Get::Install-Suggests "false";' >> /etc/apt/apt.conf.d/99nosuggest \
 && printf 'path-exclude=/usr/share/locale/*\npath-include=/usr/share/locale/ru*\npath-include=/usr/share/locale/en*\npath-include=/usr/share/locale/locale.alias\n' > /etc/dpkg/dpkg.cfg.d/01_nodoc \
 && apt-get update && apt-get -y upgrade \
 && apt-get install -y --no-install-recommends \
    openssh-client ca-certificates gnupg curl wget \
    build-essential cmake ninja-build git gdb lldb ccache pkg-config \
    cppcheck clang-format clang-tidy strace \
    tzdata locales sudo mc tmux micro \
    python3 python3-pip python3-venv \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Минимальные -dev заголовки (нужны публичным заголовкам QtGui/OpenGL/Vulkan)
#    + Runtime-библиотеки (без -dev) для работы плагинов собранного Qt6 и Qt Creator
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1-mesa-dev libegl1-mesa-dev libgles2-mesa-dev \
    libx11-dev libxext-dev libxkbcommon-dev libvulkan-dev libssl-dev \
    libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
    libxcb-randr0 libxcb-render0 libxcb-render-util0 libxcb-shape0 \
    libxcb-shm0 libxcb-sync1 libxcb-util1 libxcb-xfixes0 \
    libxcb-xinerama0 libxcb-xinput0 libxcb-xkb1 libxcb-glx0 libxcb-dri2-0 \
    libx11-xcb1 libxkbcommon-x11-0 libxcomposite1 libxdamage1 libxfixes3 \
    libxi6 libxrandr2 libxrender1 libxcursor1 libxtst6 \
    libwayland-client0 libwayland-cursor0 libwayland-egl1 \
    libgtk-3-0t64 libglib2.0-0t64 libcairo2 libpango-1.0-0 libgdk-pixbuf-2.0-0 \
    libatk1.0-0t64 libatk-bridge2.0-0t64 libatspi2.0-0t64 \
    libfontconfig1 libfreetype6 libharfbuzz0b libicu74 \
    libpulse0 pulseaudio-utils libasound2t64 libasound2-plugins pipewire-alsa \
    libavcodec60 libavformat60 libavutil58 libswscale7 libswresample4 \
    libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 \
    libdbus-1-3 libudev1 libssl3t64 openssl libsqlite3-0 libnss3 libnspr4 \
    libdouble-conversion3 libpcre2-16-0 libzstd1 libb2-1 \
    libjpeg8 libpng16-16t64 libtiff6 libwebp7 libwebpmux3 \
    libice6 libsm6 \
 && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*

# 3. Зависимости для сборки Android APK (Java 21)
RUN mkdir -p /usr/share/man/man1 \
 && apt-get update && apt-get install -y --no-install-recommends \
    openjdk-21-jdk-headless xmlstarlet maven protobuf-compiler \
 && apt-get clean && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/*
 
# 4. Копируем скрипт мониторинга и конфиг tmux из стадии builder
COPY --from=builder /usr/local/bin/container-stats.sh /usr/local/bin/container-stats.sh
COPY --from=builder /etc/tmux.conf /etc/tmux.conf

# Примечание: Qt Creator ставится в init.sh через apt-get install /opt/download/qtcreator.deb.
# Если вы хотите, чтобы Qt Creator был вшит в сам образ runtime, раскомментируйте блок ниже:
# ARG QTCREATOR_URL
# RUN wget -nv -O /tmp/qtcreator.deb "${QTCREATOR_URL}" \
#  && apt-get update && apt-get install -y --no-install-recommends /tmp/qtcreator.deb \
#  && rm -f /tmp/qtcreator.deb && apt-get clean && rm -rf /var/lib/apt/lists/*

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

ENV QT_HOST_PATH="/opt/qt/v${QT_VERSION}/gcc_64" \
    QT_PLUGIN_PATH="/opt/qt/v${QT_VERSION}/gcc_64/plugins" \
    QML_IMPORT_PATH="/opt/qt/v${QT_VERSION}/gcc_64/qml" \
    QML2_IMPORT_PATH="/opt/qt/v${QT_VERSION}/gcc_64/qml" \
    QT_QPA_FONTDIR="/usr/share/fonts/truetype"

ENV PATH="/opt/bin:/opt/qt-creator/bin:/opt/qt/v${QT_VERSION}/gcc_64/bin:/opt/qt/v${QT_VERSION}/android_arm64_v8a/bin:${JAVA_HOME}/bin:${PATH}"

# Локали, таймзона и настройка динамического линковщика
RUN printf "en_US.UTF-8 UTF-8\nru_RU.UTF-8 UTF-8\n" > /etc/locale.gen \
 && locale-gen en_US.UTF-8 ru_RU.UTF-8 \
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
