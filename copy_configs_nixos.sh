#!/bin/bash

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

colors green "[***] Резервне копіювання nixos configs..."
cp /etc/nixos/* "${HOME}"/00_setup/sh/inst/prog_nix/conf_nix/etc_nixos/
colors green "[***] Копіювання закінчене nixos configs..."
