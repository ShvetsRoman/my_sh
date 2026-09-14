#!/bin/bash
# ============================================================
# RSYNC BACKUP / SYNC
#   test-up   | sync-up     : PC → SERVER (--delete)
#   test-down | sync-down   : SERVER → PC (без --delete)
# ============================================================

set -Eeuo pipefail

# ---------- CONFIG ----------
readonly SSH_HOST="server"          # "" = пряме підключення
readonly SSH_IP="192.168.88.7"
readonly SSH_PORT="2241"
readonly SSH_USER="serv"
readonly SSH_KEY="$HOME/.ssh/id_serv"

readonly REMOTE_DIR="/run/media/serv/media"
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
log_ok()   { echo -e "${G}[ OK ]${N} $*"; }
log_warn() { echo -e "${Y}[WARN]${N} $*" >&2; }
log_error()  { echo -e "${R}[ERROR]${N} $*" >&2; exit 1; }
log_title() { echo -e "\n${C}── $* ──${N}"; }

# ---------- ARGS ----------
MODE=""
ASSUME_YES=false
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=true ;;
        *)        MODE="$arg" ;;
    esac
done

case "$MODE" in
    test-up)      DIR=up;   DRY=true  ;;
    sync-up)      DIR=up;   DRY=false ;;
    test-down)    DIR=down; DRY=true  ;;
    sync-down)    DIR=down; DRY=false ;;
    *) log_error "Режим: test-up | sync-up | test-down | sync-down" ;;
esac

# ---------- SSH ----------
if [[ -n "$SSH_HOST" ]]; then
    SSH_TARGET="$SSH_HOST"
    SSH_CMD=(ssh)
    RSYNC_RSH="ssh"
else
    [[ -f "$SSH_KEY" ]] || log_error "SSH ключ не знайдено: $SSH_KEY"
    SSH_TARGET="${SSH_USER}@${SSH_IP}"
    SSH_CMD=(ssh -p "$SSH_PORT" -i "$SSH_KEY")
    printf -v RSYNC_RSH 'ssh -p %q -i %q' "$SSH_PORT" "$SSH_KEY"
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
log_info "Remote   : $SSH_TARGET:$REMOTE_DIR"
log_info "Delete   : $([[ $DIR == up ]] && echo 'ТАК' || echo 'НІ')"
log_info "Dry-run  : $([[ $DRY == true ]] && echo 'ТАК' || echo 'НІ')"

log_title "SSH"
"${SSH_CMD[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$SSH_TARGET" true \
    || log_error "SSH недоступний: $SSH_TARGET"
log_ok "SSH OK"

# Гарантуємо існування віддаленого кореня
"${SSH_CMD[@]}" "$SSH_TARGET" "mkdir -p '$REMOTE_DIR'" \
    || log_error "Не вдалося створити $REMOTE_DIR"

# ---------- CONFIRM ----------
if [[ "$DIR" == up && "$DRY" == false && "$ASSUME_YES" == false ]]; then
    log_warn "PC → SERVER з --delete. Файли на сервері будуть видалені!"
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
        "${SSH_CMD[@]}" "$SSH_TARGET" "test -d '${REMOTE_DIR}/${d}'" \
            || { log_warn "Немає на сервері: ${REMOTE_DIR}/${d}"; ((++FAILED)); FAILED_DIRS+=("$d"); continue; }
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
(( ${#FAILED_DIRS[@]} )) && log_warn "З помилками: ${FAILED_DIRS[*]}"

if [[ "$DRY" == true ]]; then
    log_warn "DRY-RUN завершено (змін не внесено)."
elif (( FAILED == 0 )); then
    log_ok "Готово."
else
    log_warn "Готово з помилками."
fi

(( FAILED == 0 ))
