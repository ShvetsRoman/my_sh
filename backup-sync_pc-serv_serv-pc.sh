#!/bin/bash
# ============================================================
# RSYNC BACKUP / SYNC
#   [SSH_HOST] MODE [-y]
#
# Усі аргументи необов'язкові, крім MODE.
#
# Приклади:
#   ./back_serv.sh test-up              # пряме підключення по IP
#   ./back_serv.sh -y test-up           # без confirm
#   ./back_serv.sh serv test-up         # через alias 'serv'
#   ./back_serv.sh -y serv test-up      # alias + без confirm
#   ./back_serv.sh serv -y test-up      # порядок не важливий
# ============================================================

set -Eeuo pipefail

# ---------- CONFIG ----------
# SSH_HOST=""
# readonly SSH_IP="192.168.88.7"
# readonly SSH_PORT="2241"
# readonly SSH_USER="serv"
# readonly SSH_KEY="$HOME/.ssh/id_serv"
# readonly REMOTE_DIR="/run/media/serv/media"

SSH_HOST=""
readonly SSH_IP="10.113.240.145"
readonly SSH_PORT="8022"
readonly SSH_USER="tel"
readonly SSH_KEY="$HOME/.ssh/id_serv"
readonly REMOTE_DIR="/data/data/com.termux/files/home"

readonly LOCAL_DIR="$HOME"

readonly BACKUP_DIRS=(
    "00_setup"
    "01_project"
    "03_work"
    "Documents"
    "Music"
    "Pictures"
)

# ---------- COLORS ----------
readonly R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' B=$'\e[34m' C=$'\e[36m' N=$'\e[0m'

log_info()  { echo -e "${B}[INFO]${N} $*"; }
log_ok()    { echo -e "${G}[ OK ]${N} $*"; }
log_warn()  { echo -e "${Y}[WARN]${N} $*" >&2; }
log_error() { echo -e "${R}[ERROR]${N} $*" >&2; exit 1; }
log_title() { echo -e "\n${C}── $* ──${N}"; }

# ---------- ARGS ----------
# Синтаксис: [SSH_HOST] MODE [-y]
#   MODE (обов'язковий) : test-up | sync-up | test-down | sync-down
#   -y|--yes (опційно)  : не питати confirm
#   SSH_HOST (опційно)  : alias з ~/.ssh/config; якщо відсутній —
#                         пряме підключення по IP/порту/ключу
MODE=""
ASSUME_YES=false

for arg in "$@"; do
    case "$arg" in
        -y|--yes)
            ASSUME_YES=true
            ;;
        test-up|sync-up|test-down|sync-down)
            [[ -n "$MODE" ]] && log_error "MODE вказано двічі: '$MODE' і '$arg'"
            MODE="$arg"
            ;;
        -*)
            log_error "Невідомий прапорець: $arg"
            ;;
        *)
            [[ -n "$SSH_HOST" ]] && log_error "SSH_HOST вказано двічі: '$SSH_HOST' і '$arg'"
            SSH_HOST="$arg"
            ;;
    esac
done

# MODE обов'язковий — без нього не знаємо напрямок і dry-run
if [[ -z "$MODE" ]]; then
    if [[ -n "$SSH_HOST" ]]; then
        log_error "Вказано SSH_HOST '$SSH_HOST', але не вказано MODE. Режим: test-up | sync-up | test-down | sync-down"
    else
        log_error "Вкажи режим: test-up | sync-up | test-down | sync-down"
    fi
fi

case "$MODE" in
    test-up)      DIR=up;   DRY=true  ;;
    sync-up)      DIR=up;   DRY=false ;;
    test-down)    DIR=down; DRY=true  ;;
    sync-down)    DIR=down; DRY=false ;;
esac

# ---------- SSH ----------
# Якщо SSH_HOST передано — використовуємо alias з ~/.ssh/config,
# інакше — пряме підключення по IP/порту/ключу.
if [[ -n "$SSH_HOST" ]]; then
    SSH_TARGET="$SSH_HOST"
    SSH_CMD=(ssh)
    RSYNC_RSH="ssh"
    SSH_MODE_DESC="SSH_HOST (alias '$SSH_HOST')"
else
    [[ -f "$SSH_KEY" ]] || log_error "SSH ключ не знайдено: $SSH_KEY"
    SSH_TARGET="${SSH_USER}@${SSH_IP}"
    SSH_CMD=(ssh -p "$SSH_PORT" -i "$SSH_KEY")
    printf -v RSYNC_RSH 'ssh -p %q -i %q' "$SSH_PORT" "$SSH_KEY"
    SSH_MODE_DESC="пряме ${SSH_USER}@${SSH_IP}:${SSH_PORT}"
fi

# ---------- RSYNC OPTIONS ----------
RSYNC_OPTS=(--archive --verbose --stats --human-readable --rsh="$RSYNC_RSH")
[[ "$DRY" == false ]] && RSYNC_OPTS+=(--info=progress2)
[[ "$DIR" == up   ]] && RSYNC_OPTS+=(--delete)
[[ "$DRY" == true ]] && RSYNC_OPTS+=(--dry-run)

# ---------- PRE-FLIGHT ----------
for t in rsync ssh mkdir stat; do
    command -v "$t" >/dev/null || log_error "Не знайдено: $t"
done

log_title "РЕЖИМ"
log_info "Напрямок : $([[ $DIR == up ]] && echo 'PC → SERVER' || echo 'SERVER → PC')"
log_info "SSH mode : $SSH_MODE_DESC"
log_info "Remote   : $SSH_TARGET:$REMOTE_DIR"
log_info "Local    : $LOCAL_DIR"
log_info "Delete   : $([[ $DIR == up ]] && echo 'ТАК' || echo 'НІ')"
log_info "Dry-run  : $([[ $DRY == true ]] && echo 'ТАК' || echo 'НІ')"

log_title "SSH"
"${SSH_CMD[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$SSH_TARGET" true \
    || log_error "SSH недоступний: $SSH_TARGET"
log_ok "SSH OK"

"${SSH_CMD[@]}" "$SSH_TARGET" "mkdir -p '$REMOTE_DIR'" \
    || log_error "Не вдалося створити $REMOTE_DIR"

# ---------- CONFIRM ----------
if [[ "$DRY" == false && "$ASSUME_YES" == false ]]; then
    if [[ "$DIR" == up ]]; then
        log_warn "PC → SERVER з --delete. Файли на сервері будуть видалені!"
    else
        log_warn "SERVER → PC. Локальні каталоги в $LOCAL_DIR будуть оновлені:"
        log_warn "  ${BACKUP_DIRS[*]}"
        log_warn "Існуючі файли з тими ж іменами буде перезаписано (--delete НЕ використовується)."
    fi
    read -rp "Продовжити? [y/N] " a
    [[ "$a" == y ]] || { log_info "Скасовано."; exit 0; }
fi

# ---------- SYNC ----------
TOTAL=0; SUCCESS=0; FAILED=0; FAILED_DIRS=()

for d in "${BACKUP_DIRS[@]}"; do
    ((++TOTAL))
    log_title "КАТАЛОГ: $d"

    if [[ "$DIR" == up ]]; then
        SRC="${LOCAL_DIR}/${d}/"
        DST="${SSH_TARGET}:${REMOTE_DIR}/${d}/"
        [[ -d "$SRC" ]] || { log_warn "Немає локально: $SRC"; ((++FAILED)); FAILED_DIRS+=("$d"); continue; }
        [[ "$DRY" == false ]] && "${SSH_CMD[@]}" "$SSH_TARGET" "mkdir -p '${REMOTE_DIR}/${d}'"
    else
        SRC="${SSH_TARGET}:${REMOTE_DIR}/${d}/"
        DST="${LOCAL_DIR}/${d}/"

        # Розрізняємо SSH-помилку (rc=255) від "каталог відсутній" (rc=1)
        set +e
        "${SSH_CMD[@]}" -o BatchMode=yes -o ConnectTimeout=5 \
            "$SSH_TARGET" "test -d '${REMOTE_DIR}/${d}'"
        rc=$?
        set -e

        if (( rc == 255 )); then
            log_error "SSH-помилка при перевірці ${REMOTE_DIR}/${d} (rc=255). Перервано."
        elif (( rc != 0 )); then
            log_warn "Немає на сервері: ${REMOTE_DIR}/${d}"
            ((++FAILED)); FAILED_DIRS+=("$d"); continue
        fi

        [[ "$DRY" == false ]] && mkdir -p "$DST"
    fi

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

(( FAILED == 0 ))
