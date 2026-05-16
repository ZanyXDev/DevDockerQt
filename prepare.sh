#!/usr/bin/env bash
set -Eeuxo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
# Версии и пути
CCACHE_DIR=/ccache

QT_VERSION=6.11.0
# Образы и URL
QTCREATOR_IMAGE_NAME=${USER}/qt6-19-21-36-27.2.12479018
QTCREATOR_URL=https://github.com/qt-creator/qt-creator/releases/download/v19.0.0/qtcreator-linux-x64-19.0.1.deb

echo "QT_VERSION=${QT_VERSION}" >.env
echo "QTCREATOR_IMAGE_NAME=${QTCREATOR_IMAGE_NAME}" >>.env
echo "QTCREATOR_URL=${QTCREATOR_URL}" >>.env

echo "USER_ID=$(id -u)" >>.env
echo "GROUP_ID=$(id -g)" >>.env
echo "XDG_RUNTIME_DIR=/tmp/runtime-developer1"

# Пути для X11
echo "XSOCK=/tmp/.X11-unix" >>.env
echo "XAUTH=${HOME}/.Xauthority" >>.env

# Имена томов
echo "SRC_VOLUME_NAME=${QT_VERSION}-src-volume" >>.env
echo "OPT_VOLUME_NAME=${QT_VERSION}-opt-volume" >>.env
echo "CCACHE_VOLUME=${QT_VERSION}-ccache-volume" >>.env

#  Home directory
HOMEAPP="$HOME"/qtcreator-app/${QT_VERSION}
echo "Creating QtCreatorApp directory..."  
[[ -d $HOMEAPP ]] || mkdir $HOMEAPP  
echo "HOMEAPP=${HOMEAPP}" >>.env
# Загружаем статические конфиги в текущую сессию (опционально)
set -a
source .env
set +a



