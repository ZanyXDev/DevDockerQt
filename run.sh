#!/usr/bin/env bash
export USER_ID=$(id -u)
export GROUP_ID=$(id -g)
export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR

echo "1. Перезапуск ADB сервера на хосте..."
adb kill-server
adb -a nodaemon server start &> /dev/null &
sleep 2

echo "2. Пересоздание и запуск контейнера..."
docker compose down
docker compose up -d

echo "4. Подключение к интерактивной сессии контейнера..."
docker compose exec -it qtcreator bash

#Очистка ADB на хосте при выходе из контейнера
adb kill-server
