#!/bin/bash

HOST=192.168.88.7

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

if ping -c 3 ${HOST} | grep -e "mdev" >/dev/null; then
    colors green "[***] Резервне копіювання на ПК > HOME..."
    rsync -a --quiet -e "ssh -p 2241 -i /home/roman/.ssh/id_serv" serv@${HOST}:/run/media/serv/media/ ~/
    colors yellow "[***] END..."
else
    colors red "[***] ERROR ping server!!!!!"
    exit 0
fi
