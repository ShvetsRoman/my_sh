#!/usr/bin/env bash

# Визначити абсолютний шлях до директорії, де лежить цей скрипт
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# === Основні шляхи ===
BACKUP_DIR="${SCRIPT_DIR}/back_kde"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_NAME="kde_settings_$TIMESTAMP.tar.gz"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

# === Файли та папки, які перевіряємо ===
CONFIG_ITEMS=(
  "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
  "$HOME/.config/kdeglobals"
  "$HOME/.config/kwinrc"
  "$HOME/.config/kglobalshortcutsrc"
  "$HOME/.config/kscreenlockerrc"
  "$HOME/.config/krunnerrc"
  "$HOME/.config/dolphinrc"
  "$HOME/.config/konsole"
)

LOCAL_SHARE_ITEMS=(
  "$HOME/.local/share/plasma"
  "$HOME/.local/share/kxmlgui5"
  "$HOME/.local/share/konsole"
)

# === Резервне копіювання ===
backup_kde_settings() {
  echo "📦 Створюю резервну копію KDE..."

  mkdir -p "$BACKUP_DIR"

  INCLUDE_ITEMS=()

  for item in "${CONFIG_ITEMS[@]}" "${LOCAL_SHARE_ITEMS[@]}"; do
    if [ -e "$item" ]; then
      REL_PATH="${item#$HOME/}"  # відносний шлях
      INCLUDE_ITEMS+=("--transform=s,^$HOME/,," -C "$HOME" "$REL_PATH")
    fi
  done

  if [ ${#INCLUDE_ITEMS[@]} -eq 0 ]; then
    echo "⚠️ Немає доступних файлів для резервного копіювання."
    exit 1
  fi

  tar czf "$BACKUP_PATH" "${INCLUDE_ITEMS[@]}"
  if [ $? -eq 0 ]; then
    echo "✅ Бекап успішно створено: $BACKUP_PATH"
  else
    echo "❌ Помилка під час архівації."
  fi
}

# === Відновлення ===
restore_kde_settings() {
  read -e -p "📂 Вкажи шлях до архіву (.tar.gz): " ARCHIVE

  if [ ! -f "$ARCHIVE" ]; then
    echo "❌ Архів не знайдено."
    exit 1
  fi

  echo "🔁 Розпаковую архів..."
  tar xzf "$ARCHIVE" -C "$HOME"

  echo "🔧 Встановлюю права..."
  chown -R "$USER:$USER" "$HOME/.config" "$HOME/.local/share"

  echo "🔄 Перезапускаю Plasma..."
  kquitapp5 plasmashell && kstart5 plasmashell

  echo "✅ Відновлення завершено."
}

# === Меню ===
echo "=============================="
echo " KDE Settings Backup Tool"
echo "=============================="
echo "1) 📥 Резервне копіювання"
echo "2) 🔁 Відновлення"
echo "3) ❌ Вихід"
echo "=============================="
read -p "Вибери дію (1-3): " choice

case "$choice" in
  1)
    backup_kde_settings
    ;;
  2)
    restore_kde_settings
    ;;
  3)
    echo "👋 Вихід."
    exit 0
    ;;
  *)
    echo "❌ Невірний вибір."
    exit 1
    ;;
esac
