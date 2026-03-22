#!/bin/bash

DIR_COPY="/run/media/notebook/media/cp_home"

rm -r "$HOME"/Видео
rm -r "$HOME"/Документы
rm -r "$HOME"/Загрузки
rm -r "$HOME"/Изображения
rm -r "$HOME"/Музыка
rm -r "$HOME"/Общедоступные
rm -r "$HOME"/Рабочий\ стол
rm -r "$HOME"/Шаблоны

ln -s "${DIR_COPY}"/Videos "$HOME"/Videos
ln -s "${DIR_COPY}"/Documents "$HOME"/Documents
ln -s "${DIR_COPY}"/Download "$HOME"/Download
ln -s "${DIR_COPY}"/Pictures "$HOME"/Pictures
ln -s "${DIR_COPY}"/Music "$HOME"/Music
ln -s "${DIR_COPY}"/Publicshare "$HOME"/Publicshare
ln -s "${DIR_COPY}"/Desktop "$HOME"/Desktop
ln -s "${DIR_COPY}"/Templates "$HOME"/Templates

rm "$HOME"/.config/user-dirs.dirs

cat << 'user-dirs' > "$HOME"/.config/user-dirs.dirs
  XDG_DESKTOP_DIR=""$HOME"/Desktop"
  XDG_DOCUMENTS_DIR=""$HOME"/Documents"
  XDG_DOWNLOAD_DIR=""$HOME"/Download"
  XDG_MUSIC_DIR=""$HOME"/Music"
  XDG_PICTURES_DIR=""$HOME"/Pictures"
  XDG_PUBLICSHARE_DIR=""$HOME"/Publicshare"
  XDG_TEMPLATES_DIR=""$HOME"/Templates"
  XDG_VIDEOS_DIR=""$HOME"/Videos"
user-dirs
