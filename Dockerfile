FROM ubuntu:noble

LABEL Description="This image based on Ubuntu noble,provides a base development \
                   environment (Linux and Android) for Qt6 developers"
# Declare build parameters.
ARG QT_WEBKIT
ARG QT_WEBENGINE
ARG QT_VERSION
ARG TARGETARCH
ARG BUILD_TAG
ARG QTCREATOR_URL
ARG USER_ID
ARG GROUP_ID
ARG TZ

ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
COPY sources.list_noble /etc/apt/sources.list.d/ubuntu.sources

#-------------------- go-faster apt -------------------------------------------
RUN \
   export MAKEFLAGS="-j$(nproc)" \
&& export LANG=en_EN.UTF-8 \
&& export DEBIAN_FRONTEND=noninteractive \
&& echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/90nolanguages \
&& echo 'APT::Get::Install-Recommends "false";'> /etc/apt/apt.conf.d/99nosuggest \
&& echo 'APT::Get::Install-Suggests "false";' >> /etc/apt/apt.conf.d/99nosuggest \
&& dpkg --add-architecture i386 \
&& apt-get -y update \
&& apt-get -y upgrade \
&& apt-get -y install \
# Базовая сборка и утилиты
  build-essential cmake ninja-build git meld wget curl gdb ccache \
  flex bison gperf perl ruby zstd lzip \
  tzdata locales sudo iputils-ping nano mc xclip\
  \
  # Other cpp tools
  cppcheck graphviz doxygen lldb clang-format autoconf \
  \
  # Other debug tools
  strace \    
  \
  # Memory leaks cpp tools 
   valgrind \  
  \
  # Python (нужен для qtdeclarative, qtdoc, тестов)
  python3 python3-dev python3-pip python3-venv python3-html5lib \
  \
  # Графический стек (X11 + Wayland + EGL/GL)
  libx11-dev libx11-xcb-dev libxext-dev libxfixes-dev \
  libxi-dev libxrender-dev libxrandr-dev libxcursor-dev \
  libxcomposite-dev libxdamage-dev libxkbcommon-dev libxkbcommon-x11-dev \
  libwayland-dev libegl1-mesa-dev libgles2-mesa-dev libgbm-dev \
  libdrm-dev libgl1-mesa-dev libglu1-mesa-dev freeglut3-dev \
  \
  # LibXCB 
  '^libxcb.*-dev' \
  libxcb1-dev libxcb-dri2-0-dev libxcb-glx0-dev \
  libxcb-icccm4-dev libxcb-image0-dev libxcb-keysyms1-dev \
  libxcb-randr0-dev libxcb-render0-dev libxcb-render-util0-dev \
  libxcb-shape0-dev libxcb-shm0-dev libxcb-sync-dev \
  libxcb-util-dev libxcb-xfixes0-dev libxcb-xinerama0-dev \
  libxcb-xinput-dev libxcb-xkb-dev libxcb-xtest0-dev \
  libx11-xcb-dev libxcb-xinerama0-dev libxcb-xinput-dev \
  libxcb-xkb-dev libxkbfile-dev \
  \
  # Мультимедиа и кодеки
  libpulse-dev libasound2-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libgstreamer-plugins-good1.0-dev \
  libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev \
  libva-dev libvpx-dev libwebp-dev libwebpmux3 libjpeg-dev libpng-dev libtiff-dev \
  \
  # Шрифты, ввод, сеть, крипто, БД
  libfreetype-dev libfontconfig1-dev libharfbuzz-dev libicu-dev \
  libdbus-1-dev libudev-dev libcap-dev libsystemd-dev \
  libssl-dev libsqlite3-dev libnss3-dev libnspr4-dev \
  default-libmysqlclient-dev libprotobuf-dev libprotoc-dev \
  apt-transport-https  ca-certificates gnupg libssl3 openssl \
  \
  # Some libs
  libdouble-conversion3 libc6 libc-bin libtool \   
  \
  # Qt 6 специфичные
  libclang-dev libclang-rt-dev libxcb-cursor0 \
  libdouble-conversion-dev libpcre2-dev libzstd-dev libb2-dev \
  libminizip-dev libmng-dev \
  libsctp-dev libsnappy-dev \  
  \
  # Vulkan Современный рендерер Qt Quick / RHI
  libvulkan-dev glslang-tools spirv-tools \
  \
  # PipeWire Современный аудио/видео бэкенд для Linux
  libpipewire-0.3-dev libspa-0.2-dev \
  \
  # Libclang Интеграция с Qt Creator (Clangd, QML LSP)
  libclang-17-dev \
  \
  # For Android 
  openjdk-17-jdk google-android-cmdline-tools-13.0-installer  \  
  openjdk-21-jdk protobuf-compiler xmlstarlet \
  \
  # For Android armv7a 
  libc6:i386 libncurses6:i386 libstdc++6:i386 g++-multilib libc6-dev-i386 \
  libstdc++-13-dev:i386 \                     
&& apt-get -y autoremove \
&& apt-get -y autoclean \
&& apt-get -y clean \
&& rm -rf /var/lib/apt/lists/*
#------------------ set ENV ---------------------------------------------------
# Set environment variables, see Readme.md
# Allow colored output on command line.
ENV TERM=xterm-color  
# +Timezone (если надо на этапе сборки)
ENV TZ=Europe/Moscow
# Add libusb dans library path
ENV LD_LIBRARY_PATH=/usr/local/lib
ENV DISPLAY=:0
ENV PERSIST=1
ENV PS1="\u@${BUILD_TAG}:\w\$ "
ENV HOME=/home/developer

ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ENV JRE_CACERTS_PATH=/opt/java/openjdk/lib/security/cacerts
ENV JAVA_VERSION="jdk-21.0.10"
ENV OPENSSL_ROOT_DIR="/opt/android_openssl/ssl_1.1"

ENV ANDROID_HOME="/opt/android-sdk"
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_NDK_ROOT=/opt/android-sdk/ndk/27.2.12479018
ENV ANDROID_NDK_PLATFORM=android-27
ENV ANDROID_API_VERSION=android-36
ENV ANDROID_BUILD_TOOLS_REVISION=36.0.0


#Troubleshooting
#Enabling the logging categories under qt.qpa is a good idea in general. This will show some debug prints both from eglfs and the input handlers.
#ENV QT_LOGGING_RULES=qt.qpa.*=true

ENV QT_HOST_PATH="/opt/qt/v${QT_VERSION}/gcc_64:${QT_HOST_PATH}"
ENV QT_PLUGIN_PATH="/opt/qt/v${QT_VERSION}/gcc_64/plugins:${QT_PLUGIN_PATH}"
ENV QML_IMPORT_PATH="/opt/qt/v${QT_VERSION}/gcc_64/qml:${QML_IMPORT_PATH}"
ENV QML2_IMPORT_PATH="/opt/qt/v${QT_VERSION}/gcc_64/qml:${QML2_IMPORT_PATH}"

#ENV QT_HOST_PATH="/opt/qt/v${QT_VERSION}/android_x86_x64:${QT_HOST_PATH}"
#ENV QT_PLUGIN_PATH="/opt/qt/v${QT_VERSION}/android_x86_x64/plugins:${QT_PLUGIN_PATH}"
#ENV QML_IMPORT_PATH="/opt/qt/v${QT_VERSION}/android_x86_x64/qml:${QML_IMPORT_PATH}"
#ENV QML2_IMPORT_PATH="/opt/qt/v${QT_VERSION}/android_x86_x64/qml:${QML2_IMPORT_PATH}"

ENV QT_QPA_FONTDIR="/usr/share/fonts/truetype"

ENV PATH="${JAVA_HOME}/bin:${PATH}"
ENV PATH="/opt/qt/v${QT_VERSION}/gcc_64/bin:${PATH}"
ENV PATH="/opt/qt/v${QT_VERSION}/android_x86_x64/bin:${PATH}"
ENV PATH="/opt/qt-creator/bin:${PATH}"
ENV PATH="/opt/bin:${PATH}"
ENV XAUTHORITY=/home/developer/.Xauthority

# Generate required locales and set consistent defaults
RUN sed -i -e 's/# ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen \
 && sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
 && locale-gen \
 && update-locale LANG=ru_RU.UTF-8 LC_ALL=ru_RU.UTF-8

ENV LANG=ru_RU.UTF-8
ENV LC_ALL=ru_RU.UTF-8

# Tune CCACHE
ENV CCACHE_MAXSIZE=20G
ENV CCACHE_COMPRESS=1
ENV CCACHE_COMPRESSLEVEL=6

# Setup ldconfig path
RUN \
    echo "/usr/local/lib" >> /etc/ld.so.conf.d/x86_64-linux-gnu.conf  \
&&  echo "/opt/qt/v${QT_VERSION}/gcc_64/lib" >> /etc/ld.so.conf.d/x86_64-linux-gnu.conf \
&&  /sbin/ldconfig

# Setup Timezone
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime &&  echo ${TZ} > /etc/timezone 

RUN  \
if [ ${USER_ID:-0} -ne 0 ] && [ ${GROUP_ID:-0} -ne 0 ]; then \
        deluser --remove-home ubuntu ;\
        echo "Create user developer ${USER_ID}:${GROUP_ID}" ;\
        groupadd -g ${GROUP_ID} developer ;\
        useradd -u ${USER_ID} -g ${GROUP_ID} developer ;\
        install -d -m 0755 -o developer -g ${GROUP_ID} /home/developer ;\
        adduser developer sudo ;\
        echo "adding user developer to audio group" ;\
        adduser developer audio ;\
        echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers ;\
        mkdir -p /home/developer ;\
        chown ${USER_ID}:${GROUP_ID} -R /home/developer ;\
fi 


#COPY --chown=${USER_ID}:${GROUP_ID} toolchain.cmake /opt/toolchain.cmake
#add rsync dotless files after first run in /home/developer
USER developer  

WORKDIR /home/developer

# Это отраслевой стандарт для интерактивных dev-контейнеров. 
# Docker Compose с stdin_open: true и tty: true корректно подхватит терминал, 
# а bash сам определит интерактивность и прочитает ~/.bashrc.     
ENTRYPOINT []
CMD ["/bin/bash", "-l", "-i"]
