#!/usr/bin/env bash

# Визначити абсолютний шлях до директорії, де лежить цей скрипт
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# === Основні шляхи ===
BACKUP_DIR="${SCRIPT_DIR}/back_prog"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_NAME="prog_settings_$TIMESTAMP.tar.gz"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

# === Файли та папки, які перевіряємо ===
CONFIG_ITEMS=(
  "$HOME/.config/kitty"
  "$HOME/.config/nvim"
  "$HOME/.config/starship"
  "$HOME/.config/yazi"
)

ZSH_ITEMS=(
  "$HOME/.zshrc"
  "$HOME/.zsh_path"
  "$HOME/.zsh_alias"
)

# === Резервне копіювання ===
backup_prog_settings() {
  echo "📦 Створюю резервну копію config programs..."

  mkdir -p "$BACKUP_DIR"

  INCLUDE_ITEMS=()

  for item in "${CONFIG_ITEMS[@]}" "${ZSH_ITEMS[@]}"; do
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
restore_prog_settings() {
  read -e -p "📂 Вкажи шлях до архіву (.tar.gz): " ARCHIVE

  if [ ! -f "$ARCHIVE" ]; then
    echo "❌ Архів не знайдено."
    exit 1
  fi

  echo "🔁 Розпаковую архів..."
  tar xzf "$ARCHIVE" -C "$HOME"

  echo "🔧 Встановлюю права..."
  chown -R "$USER:$USER" "$HOME/.config"

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
    backup_prog_settings
    ;;
  2)
    restore_prog_settings
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
