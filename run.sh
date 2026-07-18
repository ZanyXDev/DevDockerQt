#!/usr/bin/env bash
adb kill-server
adb -a nodaemon server start &> /dev/null &

docker compose up -d
docker compose exec -it qtcreator bash

#docker compose run --rm qtcreator bash
adb kill-server


