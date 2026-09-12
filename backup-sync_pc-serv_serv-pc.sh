#!/bin/bash

# ============================================================
# RSYNC BACKUP / SYNC
# ============================================================
# PC → SERVER
#   dry-run-up   - перевірка без змін
#   sync-up      - реальна синхронізація
# SERVER → PC
#   dry-run-down - перевірка без змін
#   sync-down    - копіювання / оновлення без видалення
# ВАЖЛИВО:
#   --delete використовується ТІЛЬКИ для PC → SERVER.
#   SERVER → PC:
#       - нові файли копіюються;
#       - існуючі оновлюються;
#       - локальні файли НІКОЛИ не видаляються.
# SSH:
#   Якщо HOST_SSH заданий:
#       використовується SSH alias.
#   Якщо HOST_SSH порожній:
#       використовуються SSH_HOST / PORT / SSH_USER / SSH_KEY.
# ============================================================

set -Eeuo pipefail

# ============================================================
# CONFIG
# ============================================================

# ------------------------------------------------------------
# SSH alias (порожній рядок = використовувати пряме підключення)
# ------------------------------------------------------------
# Приклад ~/.ssh/config:
# Host serv
#     HostName 192.168.88.7
#     User serv
#     Port 2241
#     IdentityFile ~/.ssh/id_serv
# ------------------------------------------------------------

readonly HOST_SSH="serv"

# ------------------------------------------------------------
# Пряме SSH підключення (ігнорується, якщо HOST_SSH != "")
# ------------------------------------------------------------

readonly SSH_HOST="192.168.88.7"
readonly SSH_PORT="2241"
readonly SSH_USER="serv"
readonly SSH_KEY="$HOME/.ssh/id_serv"

# ------------------------------------------------------------
# Каталоги
# ------------------------------------------------------------

readonly REMOTE_DIR="/run/media/serv/media"
readonly LOCAL_DIR="$HOME"

readonly BACKUP_DIRS=(
    "00_setup"
    "01_project"
    "03_work"
    "Documents"
    "Music"
    "Pictures"
    "Videos"
)

# ------------------------------------------------------------
# Кольори
# ------------------------------------------------------------

readonly RED='\033[31m'
readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'
readonly BLUE='\033[34m'
readonly CYAN='\033[36m'
readonly NC='\033[0m'

# ============================================================
# GLOBAL VARIABLES
# ============================================================

MODE="${1:-}"

DIRECTION=""
DRY_RUN=false
USE_SSH_ALIAS=false

SSH_TARGET=""
SSH_DISPLAY=""
SSH_CMD=()
RSYNC_SSH=""
RSYNC_OPTIONS=()

TOTAL=0
SUCCESS=0
FAILED=0
FAILED_DIRS=()

# ============================================================
# LOGGING
# ============================================================

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }   # FIX: warnings → stderr
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }        # FIX: errors → stderr

log_title() {
    echo
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

# ============================================================
# ERROR HANDLING
# ============================================================

error_handler() {
    local exit_code=$?
    local line_number=$1
    local command="$2"

    echo
    log_error "Виникла помилка."
    log_error "Exit code : ${exit_code}"
    log_error "Рядок     : ${line_number}"
    log_error "Команда   : ${command}"

    exit "$exit_code"
}

cleanup() {
    local exit_code=$?
    # Місце для очищення тимчасових файлів / ресурсів.
    # FIX: явно зберігаємо exit code, інакше trap EXIT не впливає на нього.
    exit "$exit_code"
}

trap 'error_handler "$LINENO" "$BASH_COMMAND"' ERR
trap cleanup EXIT

# ============================================================
# USAGE
# ============================================================

usage() {
    cat << EOF

Використання:

  $0 dry-run-up
      Перевірити синхронізацію:
      ЛОКАЛЬНИЙ ПК → СЕРВЕР
      --delete використовується.
      Реальних змін НЕ буде.

  $0 sync-up
      Реальна синхронізація:
      ЛОКАЛЬНИЙ ПК → СЕРВЕР
      --delete використовується.
      Сервер стає дзеркалом локальних каталогів.

  $0 dry-run-down
      Перевірити синхронізацію:
      СЕРВЕР → ЛОКАЛЬНИЙ ПК
      --delete НЕ використовується.
      Реальних змін НЕ буде.

  $0 sync-down
      Реальна синхронізація:
      СЕРВЕР → ЛОКАЛЬНИЙ ПК
      --delete НЕ використовується.
      Нові файли копіюються.
      Існуючі оновлюються.
      Локальні файли залишаються.

Приклади:

  $0 dry-run-up
  $0 sync-up

  $0 dry-run-down
  $0 sync-down

EOF
}

# ============================================================
# ARGUMENT / MODE
# ============================================================

parse_mode() {
    case "$MODE" in
        dry-run-up)
            DIRECTION="up"
            DRY_RUN=true
            ;;
        sync-up)
            DIRECTION="up"
            DRY_RUN=false
            ;;
        dry-run-down)
            DIRECTION="down"
            DRY_RUN=true
            ;;
        sync-down)
            DIRECTION="down"
            DRY_RUN=false
            ;;
        *)
            log_error "Невірний або відсутній режим."
            usage >&2                       # FIX: usage → stderr при помилці
            exit 1
            ;;
    esac
}

# ============================================================
# DEPENDENCIES
# ============================================================

check_dependencies() {
    log_title "ПЕРЕВІРКА СИСТЕМИ"

    local required=(rsync ssh mkdir stat)   # FIX: явний список
    local tool

    for tool in "${required[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "${tool} не встановлений."
            exit 1
        fi
        log_success "${tool} знайдений: $(command -v "$tool")"
    done
}

# ============================================================
# SSH CONFIGURATION
# ============================================================

configure_ssh() {
    if [[ -n "$HOST_SSH" ]]; then
        USE_SSH_ALIAS=true
        SSH_TARGET="$HOST_SSH"
        SSH_DISPLAY="$HOST_SSH"
        SSH_CMD=(ssh)
        RSYNC_SSH="ssh"
        return 0
    fi

    USE_SSH_ALIAS=false
    SSH_TARGET="${SSH_USER}@${SSH_HOST}"
    SSH_DISPLAY="${SSH_USER}@${SSH_HOST}:${SSH_PORT}"

    SSH_CMD=(
        ssh
        -p "$SSH_PORT"
        -i "$SSH_KEY"
    )

    # FIX: %q коректно екранує пробіли та спецсимволи у шляхах
    printf -v RSYNC_SSH 'ssh -p %q -i %q' "$SSH_PORT" "$SSH_KEY"
}

# ============================================================
# SSH KEY CHECK
# ============================================================

check_ssh_key() {
    if [[ "$USE_SSH_ALIAS" == true ]]; then
        log_success "SSH alias: ${HOST_SSH}"
        return 0
    fi

    if [[ ! -f "$SSH_KEY" ]]; then
        log_error "SSH ключ не знайдено:"
        log_error "${SSH_KEY}"
        exit 1
    fi

    # FIX: попередження про права ключа
    local perms
    perms="$(stat -c '%a' "$SSH_KEY" 2>/dev/null || echo '')"
    if [[ "$perms" != "600" && "$perms" != "400" ]]; then
        log_warning "Права ключа: ${perms} (рекомендовано 600)"
    fi

    log_success "SSH ключ знайдений:"
    log_info "${SSH_KEY}"
}

# ============================================================
# SHOW SSH CONFIGURATION
# ============================================================

show_ssh_config() {
    log_title "SSH CONFIGURATION"

    if [[ "$USE_SSH_ALIAS" == true ]]; then
        log_info "Mode    : SSH ALIAS"
        log_info "Host    : ${HOST_SSH}"
        log_info "Command : ssh ${HOST_SSH}"
    else
        log_info "Mode   : DIRECT SSH"
        log_info "Server : ${SSH_HOST}"
        log_info "Port   : ${SSH_PORT}"
        log_info "User   : ${SSH_USER}"
        log_info "Key    : ${SSH_KEY}"
    fi
}

# ============================================================
# SHOW SYNC MODE
# ============================================================

show_sync_mode() {
    log_title "РЕЖИМ РОБОТИ"

    if [[ "$DIRECTION" == "up" ]]; then
        log_info "Напрямок : ЛОКАЛЬНИЙ ПК → СЕРВЕР"
        log_info "Remote   : ${REMOTE_DIR}"
        log_warning "--delete : УВІМКНЕНО"
    else
        log_info "Напрямок : СЕРВЕР → ЛОКАЛЬНИЙ ПК"
        log_info "Remote   : ${REMOTE_DIR}"
        log_info "Local    : ${LOCAL_DIR}"
        log_success "--delete : ВИМКНЕНО"
        log_success "Локальні файли НЕ будуть видалятися."
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_warning "DRY-RUN: реальних змін НЕ буде."
    else
        log_warning "REAL SYNC: буде виконана реальна синхронізація."
    fi
}

# ============================================================
# SSH CONNECTION TEST
# ============================================================

check_ssh_connection() {
    log_title "ПЕРЕВІРКА SSH"
    log_info "Підключення: ${SSH_DISPLAY}"

    if "${SSH_CMD[@]}" \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        "$SSH_TARGET" \
        "true" >/dev/null 2>&1
    then
        log_success "SSH CONNECTION OK"
        return 0
    fi

    log_error "Не вдалося підключитися до сервера."

    if [[ "$USE_SSH_ALIAS" == true ]]; then
        log_info "SSH alias: ${HOST_SSH}"
        log_info "Перевірте ~/.ssh/config"
    else
        log_info "Перевірте:"
        log_info "  Server : ${SSH_HOST}"
        log_info "  Port   : ${SSH_PORT}"
        log_info "  User   : ${SSH_USER}"
        log_info "  Key    : ${SSH_KEY}"
    fi

    exit 1
}

# ============================================================
# REMOTE DIRECTORY
# ============================================================

check_remote_directory() {
    log_title "ПЕРЕВІРКА ВІДДАЛЕНОГО КАТАЛОГУ"

    if "${SSH_CMD[@]}" \
        "$SSH_TARGET" \
        "test -d '$REMOTE_DIR'"
    then
        log_success "Каталог існує:"
        log_info "${REMOTE_DIR}"
        return 0
    fi

    log_warning "Каталог не існує:"
    log_warning "${REMOTE_DIR}"

    if [[ "$DRY_RUN" == true ]]; then
        log_warning "DRY-RUN: каталог створювати НЕ будемо."
        return 0
    fi

    log_info "Створення каталогу..."

    if "${SSH_CMD[@]}" \
        "$SSH_TARGET" \
        "mkdir -p '$REMOTE_DIR'"
    then
        log_success "Каталог створено."
    else
        log_error "Не вдалося створити:"
        log_error "${REMOTE_DIR}"
        exit 1
    fi
}

# ============================================================
# BUILD RSYNC OPTIONS
# ============================================================
# REFACTOR: викликається один раз у main(), а не в циклі.

build_rsync_options() {
    RSYNC_OPTIONS=(
        --archive
        --verbose
        --stats
        --rsh="$RSYNC_SSH"
    )

    # FIX: progress2 у dry-run показує нулі — не додаємо
    if [[ "$DRY_RUN" == false ]]; then
        RSYNC_OPTIONS+=(--info=progress2)
    fi

    # --delete ТІЛЬКИ PC → SERVER
    if [[ "$DIRECTION" == "up" ]]; then
        RSYNC_OPTIONS+=(--delete)
    fi

    if [[ "$DRY_RUN" == true ]]; then
        RSYNC_OPTIONS+=(--dry-run)
    fi
}

# ============================================================
# PREPARE LOCAL DIRECTORY
# ============================================================

prepare_local_directory() {
    local local_dir="$1"

    if [[ -d "$local_dir" ]]; then
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY-RUN: каталог буде створено:"
        log_info "${local_dir}"
        return 0
    fi

    log_info "Створення локального каталогу:"
    log_info "${local_dir}"

    if mkdir -p "$local_dir"; then
        log_success "Локальний каталог створено."
    else
        log_error "Не вдалося створити:"
        log_error "${local_dir}"
        return 1
    fi
}

# ============================================================
# PREPARE REMOTE DIRECTORY
# ============================================================

prepare_remote_directory() {
    local remote_dir="$1"

    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi

    "${SSH_CMD[@]}" \
        "$SSH_TARGET" \
        "mkdir -p '$remote_dir'"
}

# ============================================================
# RSYNC: PC → SERVER
# ============================================================

rsync_up() {
    local dir="$1"

    local local_dir="${LOCAL_DIR}/${dir}/"
    local remote_dir="${REMOTE_DIR}/${dir}/"
    local remote_target="${SSH_TARGET}:${remote_dir}"

    log_info "Джерело:"
    log_info "${local_dir}"

    log_info "Призначення:"
    log_info "${remote_target}"

    if [[ ! -d "$local_dir" ]]; then
        log_error "Локальний каталог не знайдено:"
        log_error "${local_dir}"
        return 1
    fi

    if ! prepare_remote_directory "$remote_dir"; then
        log_error "Не вдалося створити:"
        log_error "${remote_dir}"
        return 1
    fi

    log_info "Запуск rsync: LOCAL → SERVER"

    rsync \
        "${RSYNC_OPTIONS[@]}" \
        "$local_dir" \
        "$remote_target"
}

# ============================================================
# RSYNC: SERVER → PC
# ============================================================

rsync_down() {
    local dir="$1"

    local remote_dir="${REMOTE_DIR}/${dir}/"
    local remote_source="${SSH_TARGET}:${remote_dir}"

    # FIX: раніше було "${LOCAL_DIR}/" — усі каталоги зливалися в $HOME.
    local local_dir="${LOCAL_DIR}/${dir}/"

    log_info "Джерело:"
    log_info "${remote_source}"

    log_info "Призначення:"
    log_info "${local_dir}"

    if ! "${SSH_CMD[@]}" \
        "$SSH_TARGET" \
        "test -d '$remote_dir'"
    then
        log_error "Каталог на сервері не знайдено:"
        log_error "${remote_dir}"
        return 1
    fi

    if ! prepare_local_directory "$local_dir"; then
        return 1
    fi

    log_info "Запуск rsync: SERVER → LOCAL"

    rsync \
        "${RSYNC_OPTIONS[@]}" \
        "$remote_source" \
        "$local_dir"
}

# ============================================================
# PROCESS ONE DIRECTORY
# ============================================================
# REFACTOR: прибрано дублювання if/else для up/down.

process_directory() {
    local dir="$1"

    # FIX: ((++TOTAL)) замість ((TOTAL++)) — останній падає при set -e,
    # коли початкове значення 0.
    ((++TOTAL))

    log_title "КАТАЛОГ: ${dir}"

    local fn
    case "$DIRECTION" in
        up)   fn=rsync_up ;;
        down) fn=rsync_down ;;
    esac

    if "$fn" "$dir"; then
        log_success "Каталог ${dir} синхронізовано."
        ((++SUCCESS))
    else
        log_error "Помилка синхронізації каталогу ${dir}."
        ((++FAILED))
        FAILED_DIRS+=("$dir")
    fi
}

# ============================================================
# PROCESS ALL DIRECTORIES
# ============================================================

process_all_directories() {
    local dir
    for dir in "${BACKUP_DIRS[@]}"; do
        # FIX: || true — щоб set -e не валив цикл, якщо функція поверне != 0
        process_directory "$dir" || true
    done
}

# ============================================================
# SUMMARY
# ============================================================

show_summary() {
    log_title "ПІДСУМОК"
    echo

    log_info "Усього каталогів : ${TOTAL}"
    log_info "Успішно          : ${SUCCESS}"
    log_info "Помилок          : ${FAILED}"

    if (( ${#FAILED_DIRS[@]} > 0 )); then
        log_warning "Каталоги з помилками: ${FAILED_DIRS[*]}"
    fi

    echo

    if [[ "$DIRECTION" == "up" ]]; then
        log_info "Напрямок: ЛОКАЛЬНИЙ ПК → СЕРВЕР"
        log_info "--delete: УВІМКНЕНО"
    else
        log_info "Напрямок: СЕРВЕР → ЛОКАЛЬНИЙ ПК"
        log_info "--delete: ВИМКНЕНО"
        log_success "Локальні файли НЕ видаляються."
    fi

    echo

    if [[ "$DRY_RUN" == true ]]; then
        log_warning "DRY-RUN ЗАВЕРШЕНО"
        log_info "Реальних змін виконано НЕ було."
    elif [[ "$FAILED" -eq 0 ]]; then
        log_success "СИНХРОНІЗАЦІЯ ЗАВЕРШЕНА УСПІШНО."
    else
        log_warning "СИНХРОНІЗАЦІЯ ЗАВЕРШЕНА З ПОМИЛКАМИ."
    fi

    echo
}

# ============================================================
# FINAL EXIT STATUS
# ============================================================

get_exit_status() {
    if [[ "$FAILED" -gt 0 ]]; then
        return 1
    fi
    return 0
}

# ============================================================
# MAIN
# ============================================================

main() {
    # Mode
    parse_mode

    # System
    check_dependencies

    # SSH
    configure_ssh
    check_ssh_key
    show_ssh_config

    # Sync mode
    show_sync_mode

    # Connection
    check_ssh_connection

    # Remote directory
    check_remote_directory

    # REFACTOR: rsync options будуються один раз, а не в циклі
    build_rsync_options

    # Sync
    process_all_directories

    # Summary
    show_summary

    # Exit
    get_exit_status
}

# ============================================================
# START
# ============================================================

main "$@"
