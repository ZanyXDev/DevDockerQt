#!/usr/bin/env bash
export USER_ID=$(id -u)
export GROUP_ID=$(id -g)
export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR

adb kill-server
adb -a nodaemon server start &> /dev/null &

docker compose up -d
docker compose exec -it qtcreator bash

#docker compose run --rm qtcreator bash
adb kill-server


