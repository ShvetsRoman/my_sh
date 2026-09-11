#!/bin/bash

SERVER="192.168.88.7"
PORT="2241"
HOST_SSH="serv"
USER="serv"
SSH_KEY="$HOME/.ssh/id_serv"

# rsync -avh --info=progress2 --delete -e "ssh -p ${PORT} -i ${SSH_KEY}" $HOME/00_setup "${USER}@${SERVER}:/run/media/serv/media/"

colors() {
  case "$1" in
    red)
      echo -e "\n\033[31m$2\033[0m"
    ;;
    yellow)
      echo -e "\n\033[33m$2\033[0m"
    ;;
    green)
      echo -e "\n\033[32m$2\033[0m"
    ;;
  esac
}

if ping -c 3 ${SERVER} | grep -e "mdev" >/dev/null; then
    colors green "[***] PING OK"

    colors green "[***] Резервне копіювання 00_setup..."
    rsync -avh --progress --delete ${HOME}/00_setup ${HOST_SSH}:/run/media/serv/media

    colors green "[***] Резервне копіювання 01_project..."
    rsync -avh --progress --delete ${HOME}/01_project ${HOST_SSH}:/run/media/serv/media

    colors green "[***] Резервне копіювання 03_work..."
    rsync -avh --progress --delete ${HOME}/03_work ${HOST_SSH}:/run/media/serv/media

    colors green "[***] Резервне копіювання Documents..."
    rsync -avh --progress --delete ${HOME}/Documents ${HOST_SSH}:/run/media/serv/media

    colors green "[***] Резервне копіювання Music..."
    rsync -avh --progress --delete ${HOME}/Music ${HOST_SSH}:/run/media/serv/media

    colors green "[***] Резервне копіювання Pictures..."
    rsync -avh --progress --delete ${HOME}/Pictures ${HOST_SSH}:/run/media/serv/media

    colors green "[***] Резервне копіювання Videos..."
    rsync -avh --progress --delete ${HOME}/Videos ${HOST_SSH}:/run/media/serv/media

colors yellow "[***] END..."

else
    colors red "[***] ERROR ping server!!!!!"
    exit 0
fi
