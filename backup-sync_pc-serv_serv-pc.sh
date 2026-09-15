#!/bin/bash

# ============================================================
# RSYNC BACKUP / SYNC
#   test-up   | sync-up     : PC → SERVER (--delete)
#   test-down | sync-down   : SERVER → PC (без --delete)
# ============================================================

# -E : успадковувати ERR trap у функціях/підоболонках
# -e : зупинятись на першій помилці
# -u : помилка при використанні неініціалізованої змінної
# -o pipefail : пайп вважається невдалим, якщо хоч одна ланка впала
set -Eeuo pipefail

# ---------- CONFIG ----------
readonly SSH_HOST="serv"          # "" = пряме підключення по IP
readonly SSH_IP="192.168.88.7"
readonly SSH_PORT="2241"
readonly SSH_USER="serv"
readonly SSH_KEY="$HOME/.ssh/id_serv"

readonly REMOTE_DIR="/run/media/serv/media"   # корінь бекапу на сервері
readonly LOCAL_DIR="$HOME"                    # корінь бекапу на PC

# Каталоги, які синхронізуються в обох напрямках
readonly BACKUP_DIRS=(
    "00_setup"
    "01_project"
    "03_work"
    "Documents"
    "Music"
    "Pictures"
)

# ---------- COLORS ----------
# Кольори для логів (ANSI escape)
readonly R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' B=$'\e[34m' C=$'\e[36m' N=$'\e[0m'

# Функції логування. Помилки та попередження йдуть у stderr,
# щоб їх можна було відокремити від звичайного виводу.
log_info()  { echo -e "${B}[INFO]${N} $*"; }
log_ok()    { echo -e "${G}[ OK ]${N} $*"; }
log_warn()  { echo -e "${Y}[WARN]${N} $*" >&2; }
log_error() { echo -e "${R}[ERROR]${N} $*" >&2; exit 1; }
log_title() { echo -e "\n${C}── $* ──${N}"; }

# ---------- ARGS ----------
# Розбір аргументів: перший непрапорційний аргумент = MODE,
# -y|--yes = підтвердити автоматично (не питати confirm)
MODE=""
ASSUME_YES=false
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=true ;;
        *)        MODE="$arg" ;;
    esac
done

# Визначаємо напрямок (up/down) та режим (dry-run чи реальний)
case "$MODE" in
    test-up)      DIR=up;   DRY=true  ;;   # PC → SERVER, тільки показати
    sync-up)      DIR=up;   DRY=false ;;   # PC → SERVER, реально
    test-down)    DIR=down; DRY=true  ;;   # SERVER → PC, тільки показати
    sync-down)    DIR=down; DRY=false ;;   # SERVER → PC, реально
    *) log_error "Режим: test-up | sync-up | test-down | sync-down" ;;
esac

# ---------- SSH ----------
# Якщо SSH_HOST заданий — використовуємо ssh alias з ~/.ssh/config,
# інакше — пряме підключення по IP з ключем і портом.
if [[ -n "$SSH_HOST" ]]; then
    SSH_TARGET="$SSH_HOST"
    SSH_CMD=(ssh)
    RSYNC_RSH="ssh"
else
    [[ -f "$SSH_KEY" ]] || log_error "SSH ключ не знайдено: $SSH_KEY"
    SSH_TARGET="${SSH_USER}@${SSH_IP}"
    SSH_CMD=(ssh -p "$SSH_PORT" -i "$SSH_KEY")
    # %q коректно заквотить порт і шлях до ключа,
    # щоб rsync потім розібрав --rsh через shell без сюрпризів
    printf -v RSYNC_RSH 'ssh -p %q -i %q' "$SSH_PORT" "$SSH_KEY"
fi

# ---------- RSYNC OPTIONS ----------
# Базові опції: архів (права, час, симлінки), детальний вивід, статистика
RSYNC_OPTS=(--archive --verbose --stats --human-readable --rsh="$RSYNC_RSH")
# Прогрес показуємо лише в реальному режимі (у dry-run він неінформативний)
[[ "$DRY" == false ]] && RSYNC_OPTS+=(--info=progress2)
# --delete тільки для up: видаляє на сервері те, чого немає локально.
# Для down НЕ використовуємо, щоб не знести локальні файли.
[[ "$DIR" == up   ]] && RSYNC_OPTS+=(--delete)
# У test-режимах додаємо --dry-run (нічого не змінюється)
[[ "$DRY" == true ]] && RSYNC_OPTS+=(--dry-run)

# ---------- PRE-FLIGHT ----------
# Перевіряємо, що всі потрібні утиліти встановлені
for t in rsync ssh mkdir stat; do
    command -v "$t" >/dev/null || log_error "Не знайдено: $t"
done

# Інформуємо користувача про параметри запуску
log_title "РЕЖИМ"
log_info "Напрямок : $([[ $DIR == up ]] && echo 'PC → SERVER' || echo 'SERVER → PC')"
log_info "Remote   : $SSH_TARGET:$REMOTE_DIR"
log_info "Local    : $LOCAL_DIR"
log_info "Delete   : $([[ $DIR == up ]] && echo 'ТАК' || echo 'НІ')"
log_info "Dry-run  : $([[ $DRY == true ]] && echo 'ТАК' || echo 'НІ')"

# Перевірка SSH: BatchMode=yes забороняє запит пароля,
# ConnectTimeout=5 не дає зависнути на мертвому хості
log_title "SSH"
"${SSH_CMD[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$SSH_TARGET" true \
    || log_error "SSH недоступний: $SSH_TARGET"
log_ok "SSH OK"

# Гарантуємо існування віддаленого кореня (навіть у dry-run —
# це ідемпотентно і спрощує подальші запуски)
"${SSH_CMD[@]}" "$SSH_TARGET" "mkdir -p '$REMOTE_DIR'" \
    || log_error "Не вдалося створити $REMOTE_DIR"

# ---------- CONFIRM ----------
# Показуємо попередження та питаємо підтвердження лише для реальних
# (не dry-run) запусків і якщо не передано -y.
if [[ "$DRY" == false && "$ASSUME_YES" == false ]]; then
    if [[ "$DIR" == up ]]; then
        # up: головний ризик — --delete на сервері
        log_warn "PC → SERVER з --delete. Файли на сервері будуть видалені!"
    else
        # down: зараз --delete немає, але попереджаємо про перезапис
        # (захист на випадок, якщо колись додадуть --delete)
        log_warn "SERVER → PC. Локальні каталоги в $LOCAL_DIR будуть оновлені:"
        log_warn "  ${BACKUP_DIRS[*]}"
        log_warn "Існуючі файли з тими ж іменами буде перезаписано (--delete НЕ використовується)."
    fi
    read -rp "Продовжити? [y/N] " a
    [[ "$a" == y ]] || { log_info "Скасовано."; exit 0; }
fi

# ---------- SYNC ----------
# Лічильники для підсумку та масив каталогів, які впали
TOTAL=0; SUCCESS=0; FAILED=0; FAILED_DIRS=()

for d in "${BACKUP_DIRS[@]}"; do
    ((++TOTAL))
    log_title "КАТАЛОГ: $d"

    if [[ "$DIR" == up ]]; then
        # Напрямок PC → SERVER
        SRC="${LOCAL_DIR}/${d}/"              # з trailing slash — копіюємо вміст
        DST="${SSH_TARGET}:${REMOTE_DIR}/${d}/"

        # Локальний каталог відсутній — це FAILED, йдемо далі
        [[ -d "$SRC" ]] || { log_warn "Немає локально: $SRC"; ((++FAILED)); FAILED_DIRS+=("$d"); continue; }

        # Створюємо віддалений каталог заздалегідь (у dry-run не чіпаємо)
        [[ "$DRY" == false ]] && "${SSH_CMD[@]}" "$SSH_TARGET" "mkdir -p '${REMOTE_DIR}/${d}'"
    else
        # Напрямок SERVER → PC
        SRC="${SSH_TARGET}:${REMOTE_DIR}/${d}/"
        DST="${LOCAL_DIR}/${d}/"

        # Розрізняємо SSH-помилку (rc=255) від "каталог відсутній" (rc=1).
        # set +e потрібен, бо set -Eeuo pipefail вбив би скрипт на non-zero.
        set +e
        "${SSH_CMD[@]}" -o BatchMode=yes -o ConnectTimeout=5 \
            "$SSH_TARGET" "test -d '${REMOTE_DIR}/${d}'"
        rc=$?
        set -e

        if (( rc == 255 )); then
            # SSH зламався (мережа, ключ, хост) — далі сенсу немає,
            # наступні каталоги теж впадуть. Зупиняємось.
            log_error "SSH-помилка при перевірці ${REMOTE_DIR}/${d} (rc=255). Перервано."
        elif (( rc != 0 )); then
            # Каталог справді відсутній на сервері — це FAILED, йдемо далі
            log_warn "Немає на сервері: ${REMOTE_DIR}/${d}"
            ((++FAILED)); FAILED_DIRS+=("$d"); continue
        fi

        # Створюємо локальний каталог (у dry-run не чіпаємо)
        [[ "$DRY" == false ]] && mkdir -p "$DST"
    fi

    # Власне rsync. Опції вже зібрані вище з урахуванням напрямку та dry-run.
    if rsync "${RSYNC_OPTS[@]}" "$SRC" "$DST"; then
        log_ok "$d синхронізовано"
        ((++SUCCESS))
    else
        log_warn "$d — помилка"
        ((++FAILED)); FAILED_DIRS+=("$d")
    fi
done

# ---------- SUMMARY ----------
log_title "ПІДСУМОК"
log_info "Усього: $TOTAL | OK: $SUCCESS | FAIL: $FAILED"
# Явна умова `> 0` — читабельніше й без ризику вплинути на exit code,
# як було б з конструкцією `(( ${#FAILED_DIRS[@]} )) && ...`
if (( ${#FAILED_DIRS[@]} > 0 )); then
    log_warn "З помилками: ${FAILED_DIRS[*]}"
fi

if [[ "$DRY" == true ]]; then
    log_warn "DRY-RUN завершено (змін не внесено)."
elif (( FAILED == 0 )); then
    log_ok "Готово."
else
    log_warn "Готово з помилками."
fi

# Exit code скрипта = результат останньої команди:
# 0 якщо всі каталоги успішні, 1 якщо були помилки.
(( FAILED == 0 ))
