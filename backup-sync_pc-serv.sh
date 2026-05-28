#!/bin/bash

HOST_IP=192.168.88.7
HOST=serv

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

if ping -c 3 ${HOST_IP} | grep -e "mdev" >/dev/null; then
    colors green "[***] PING OK"

    colors green "[***] Резервне копіювання 00_setup..."
    rsync -avh --progress --delete /home/roman/00_setup serv@${HOST}:/run/media/serv/media

    colors green "[***] Резервне копіювання 01_project..."
    rsync -avh --progress --delete /home/roman/01_project serv@${HOST}:/run/media/serv/media

    colors green "[***] Резервне копіювання 03_work..."
    rsync -avh --progress --delete /home/roman/03_work serv@${HOST}:/run/media/serv/media

    colors green "[***] Резервне копіювання Documents..."
    rsync -avh --progress --delete /home/roman/Documents serv@${HOST}:/run/media/serv/media

    colors green "[***] Резервне копіювання Music..."
    rsync -avh --progress --delete /home/roman/Music serv@${HOST}:/run/media/serv/media

    colors green "[***] Резервне копіювання Pictures..."
    rsync -avh --progress --delete /home/roman/Pictures serv@${HOST}:/run/media/serv/media

    colors green "[***] Резервне копіювання Videos..."
    rsync -avh --progress --delete /home/roman/Videos serv@${HOST}:/run/media/serv/media

colors yellow "[***] END..."

else
    colors red "[***] ERROR ping server!!!!!"
    exit 0
fi
