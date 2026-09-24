#!/usr/bin/env bash

# ============================================================
# DOTFILES MANAGER
# ============================================================

set -Eeuo pipefail

# ============================================================
# COLORS
# ============================================================

readonly BLUE='\033[0;34m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'

# ============================================================
# GLOBAL VARIABLES
# ============================================================

# Визначити абсолютний шлях до директорії, де лежить цей скрипт
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

readonly HOME_DIR="$HOME"
readonly DOTFILES_DIR="$SCRIPT_DIR/dotfiles"
readonly RECOVERY_DIR="$SCRIPT_DIR/dotfiles-recovery"
readonly SCRIPT_NAME="$(basename "$0")"

DRY_RUN=false

# ============================================================
# BACKUP CONFIGURATION
# ============================================================

readonly BACKUP_DIRS=(
    ".config/helix"
    ".config/nvim"
    ".config/wezterm"
    ".config/kitty"
    ".config/eza"
    ".config/Kvantum"
    ".config/mc"
    ".config/starship"
    ".config/television"
    ".config/yazi"
    ".config/zed"
)

readonly BACKUP_FILES=(
    ".zshrc"
    ".zsh_alias.zsh"
    ".zsh_path.zsh"
)

# ============================================================
# LOGGING
# ============================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_git() {
    echo -e "${MAGENTA}[GIT]${NC} $1"
}

log_title() {
    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ============================================================
# ERROR HANDLER
# ============================================================

error_handler() {
    local exit_code="$1"
    local line="$2"
    local command="$3"
    local source="$4"

    echo

    log_error "Помилка виконання"
    log_error "Файл    : $source"
    log_error "Рядок   : $line"
    log_error "Команда : $command"
    log_error "Код     : $exit_code"
}

trap 'error_handler "$?" "$LINENO" "$BASH_COMMAND" "${BASH_SOURCE[0]}"' ERR

# ============================================================
# DEPENDENCIES
# ============================================================

check_dependencies() {
    local dependencies=(
        "rsync"
        "diff"
        "git"
    )

    for command in "${dependencies[@]}"; do

        if ! command -v "$command" &>/dev/null; then
            log_error "Не знайдено залежність: $command"
            return 1
        fi

    done
}

# ============================================================
# DOTFILES DIRECTORY
# ============================================================

create_dotfiles_dir() {

    if [[ ! -d "$DOTFILES_DIR" ]]; then
        log_info "Створення каталогу: $DOTFILES_DIR"

        mkdir -p "$DOTFILES_DIR"
    fi
}

check_dotfiles_dir() {

    if [[ ! -d "$DOTFILES_DIR" ]]; then
        log_error "Каталог dotfiles не існує:"
        log_error "$DOTFILES_DIR"
        log_info "Спочатку виконай: ./$SCRIPT_NAME backup"

        return 1
    fi
}

# ============================================================
# RECOVERY DIRECTORY
# ============================================================

create_recovery_dir() {

    if [[ ! -d "$RECOVERY_DIR" ]]; then

        log_info "Створення каталогу recovery:"
        log_info "$RECOVERY_DIR"

        mkdir -p "$RECOVERY_DIR"
    fi
}

# ============================================================
# BACKUP DIRECTORIES
# ============================================================

backup_dirs() {

    for item in "${BACKUP_DIRS[@]}"; do

        local source="$HOME_DIR/$item"
        local destination="$DOTFILES_DIR/$item"

        if [[ ! -d "$source" ]]; then
            log_warning "Каталог не існує: ~/$item"
            continue
        fi

        log_title "$item"

        mkdir -p "$(dirname "$destination")"

        if [[ "$DRY_RUN" == true ]]; then

            log_info "Dry-run: ~/$item"

            rsync \
                --archive \
                --delete \
                --dry-run \
                "$source/" \
                "$destination/"

        else

            rsync \
                --archive \
                --delete \
                "$source/" \
                "$destination/"

            log_success "Backup: ~/$item"

        fi
    done
}

# ============================================================
# BACKUP FILES
# ============================================================

backup_files() {

    for item in "${BACKUP_FILES[@]}"; do

        local source="$HOME_DIR/$item"
        local destination="$DOTFILES_DIR/$item"

        if [[ ! -f "$source" ]]; then
            log_warning "Файл не існує: ~/$item"
            continue
        fi

        log_title "$item"

        mkdir -p "$(dirname "$destination")"

        if [[ "$DRY_RUN" == true ]]; then

            log_info "Dry-run: ~/$item"

            rsync \
                --archive \
                --dry-run \
                "$source" \
                "$destination"

        else

            rsync \
                --archive \
                "$source" \
                "$destination"

            log_success "Backup: ~/$item"

        fi
    done
}

# ============================================================
# BACKUP
# ============================================================

backup() {

    log_info "Початок backup"

    create_dotfiles_dir

    backup_dirs
    backup_files

    log_success "Backup завершено"
}

# ============================================================
# CREATE RECOVERY BACKUP
# ============================================================

create_recovery_backup() {

    if [[ "$DRY_RUN" == true ]]; then
        log_warning "Dry-run: recovery backup не створюється"
        return 0
    fi

    create_recovery_dir

    local timestamp
    local recovery_path

    timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
    recovery_path="$RECOVERY_DIR/$timestamp"

    mkdir -p "$recovery_path"

    log_info "Створення recovery backup:"
    log_info "$recovery_path"

    # --------------------------------------------------------
    # КАТАЛОГИ
    # --------------------------------------------------------

    for item in "${BACKUP_DIRS[@]}"; do

        local source="$HOME_DIR/$item"
        local destination="$recovery_path/$item"

        if [[ ! -d "$source" ]]; then
            log_warning "Каталог не існує: ~/$item"
            continue
        fi

        mkdir -p "$(dirname "$destination")"

        rsync \
            --archive \
            "$source/" \
            "$destination/"

        log_success "Recovery: ~/$item"
    done

    # --------------------------------------------------------
    # ФАЙЛИ
    # --------------------------------------------------------

    for item in "${BACKUP_FILES[@]}"; do

        local source="$HOME_DIR/$item"
        local destination="$recovery_path/$item"

        if [[ ! -f "$source" ]]; then
            log_warning "Файл не існує: ~/$item"
            continue
        fi

        mkdir -p "$(dirname "$destination")"

        rsync \
            --archive \
            "$source" \
            "$destination"

        log_success "Recovery: ~/$item"
    done

    log_success "Recovery backup створено:"
    log_success "$recovery_path"
}

# ============================================================
# RESTORE DIRECTORIES
# ============================================================

restore_dirs() {

    for item in "${BACKUP_DIRS[@]}"; do

        local source="$DOTFILES_DIR/$item"
        local destination="$HOME_DIR/$item"

        if [[ ! -d "$source" ]]; then
            log_warning "У backup немає каталогу: ~/$item"
            continue
        fi

        log_title "$item"

        mkdir -p "$destination"

        if [[ "$DRY_RUN" == true ]]; then

            log_info "Dry-run: restore ~/$item"

            rsync \
                --archive \
                --dry-run \
                "$source/" \
                "$destination/"

        else

            rsync \
                --archive \
                "$source/" \
                "$destination/"

            log_success "Restore: ~/$item"

        fi
    done
}

# ============================================================
# RESTORE FILES
# ============================================================

restore_files() {

    for item in "${BACKUP_FILES[@]}"; do

        local source="$DOTFILES_DIR/$item"
        local destination="$HOME_DIR/$item"

        if [[ ! -f "$source" ]]; then
            log_warning "У backup немає файлу: ~/$item"
            continue
        fi

        log_title "$item"

        if [[ "$DRY_RUN" == true ]]; then

            log_info "Dry-run: restore ~/$item"

            rsync \
                --archive \
                --dry-run \
                "$source" \
                "$destination"

        else

            rsync \
                --archive \
                "$source" \
                "$destination"

            log_success "Restore: ~/$item"

        fi
    done
}

# ============================================================
# RESTORE
# ============================================================

restore() {

    check_dotfiles_dir

    if [[ "$DRY_RUN" == false ]]; then

        read -rp \
            "Створити recovery backup перед restore? [Y/n]: " \
            answer

        if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
            create_recovery_backup
        else
            log_warning "Recovery backup пропущено"
        fi

        echo

        read -rp \
            "Продовжити restore? [y/N]: " \
            answer

        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            log_warning "Restore скасовано"
            return 0
        fi
    fi

    restore_dirs
    restore_files

    log_success "Restore завершено"
}

# ============================================================
# DIFF DIRECTORIES
# ============================================================

diff_dirs() {

    for item in "${BACKUP_DIRS[@]}"; do

        local backup_item="$DOTFILES_DIR/$item"
        local home_item="$HOME_DIR/$item"

        if [[ ! -d "$backup_item" ]]; then
            continue
        fi

        if [[ ! -d "$home_item" ]]; then
            log_warning "Каталог відсутній у HOME: ~/$item"
            continue
        fi

        log_title "$item"

        diff \
            -ruN \
            "$backup_item" \
            "$home_item" || true
    done
}

# ============================================================
# DIFF FILES
# ============================================================

diff_files() {

    for item in "${BACKUP_FILES[@]}"; do

        local backup_item="$DOTFILES_DIR/$item"
        local home_item="$HOME_DIR/$item"

        if [[ ! -f "$backup_item" ]]; then
            continue
        fi

        if [[ ! -f "$home_item" ]]; then
            log_warning "Файл відсутній у HOME: ~/$item"
            continue
        fi

        log_title "$item"

        diff \
            -u \
            "$backup_item" \
            "$home_item" || true
    done
}

# ============================================================
# DIFF
# ============================================================

show_diff() {

    check_dotfiles_dir

    diff_dirs
    diff_files
}

# ============================================================
# LIST
# ============================================================

list_backup() {

    check_dotfiles_dir

    echo
    echo -e "${CYAN}Dotfiles:${NC}"
    echo

    for item in "${BACKUP_DIRS[@]}"; do

        if [[ -d "$DOTFILES_DIR/$item" ]]; then
            echo -e "${GREEN}✓${NC} ~/$item"
        else
            echo -e "${RED}✗${NC} ~/$item"
        fi
    done

    for item in "${BACKUP_FILES[@]}"; do

        if [[ -f "$DOTFILES_DIR/$item" ]]; then
            echo -e "${GREEN}✓${NC} ~/$item"
        else
            echo -e "${RED}✗${NC} ~/$item"
        fi
    done
}

# ============================================================
# STATUS
# ============================================================

status() {

    echo

    echo -e "${CYAN}Dotfiles:${NC}"

    if [[ -d "$DOTFILES_DIR" ]]; then
        echo -e "${GREEN}✓${NC} $DOTFILES_DIR"
    else
        echo -e "${RED}✗${NC} $DOTFILES_DIR"
    fi

    echo

    echo -e "${CYAN}Recovery:${NC}"

    if [[ -d "$RECOVERY_DIR" ]]; then
        echo -e "${GREEN}✓${NC} $RECOVERY_DIR"
    else
        echo -e "${RED}✗${NC} $RECOVERY_DIR"
    fi

    echo

    echo -e "${CYAN}Configured items:${NC}"

    for item in "${BACKUP_DIRS[@]}"; do

        if [[ -d "$HOME_DIR/$item" ]]; then
            echo -e "${GREEN}✓${NC} ~/$item"
        else
            echo -e "${RED}✗${NC} ~/$item"
        fi
    done

    for item in "${BACKUP_FILES[@]}"; do

        if [[ -f "$HOME_DIR/$item" ]]; then
            echo -e "${GREEN}✓${NC} ~/$item"
        else
            echo -e "${RED}✗${NC} ~/$item"
        fi
    done
}

# ============================================================
# CLEAN DOTFILES
# ============================================================

clean_backup() {

    if [[ ! -d "$DOTFILES_DIR" ]]; then
        log_warning "Каталог dotfiles не існує"
        return 0
    fi

    echo

    log_warning "Буде видалено:"
    echo "$DOTFILES_DIR"

    echo

    read -rp "Продовжити? [y/N]: " answer

    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        log_warning "Операцію скасовано"
        return 0
    fi

    rm -rf -- "$DOTFILES_DIR"

    log_success "Dotfiles backup видалено"
}

# ============================================================
# RECOVERY LIST
# ============================================================

recovery_list() {

    if [[ ! -d "$RECOVERY_DIR" ]]; then
        log_warning "Recovery каталог не існує:"
        log_warning "$RECOVERY_DIR"
        return 0
    fi

    local recovery_backups=()

    while IFS= read -r -d '' path; do
        recovery_backups+=("$path")
    done < <(
        find "$RECOVERY_DIR" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -print0 |
        sort -z -r
    )

    if [[ "${#recovery_backups[@]}" -eq 0 ]]; then
        log_warning "Recovery backup відсутні"
        return 0
    fi

    echo
    echo -e "${CYAN}Recovery backups:${NC}"
    echo

    local number=1

    for path in "${recovery_backups[@]}"; do

        local timestamp
        timestamp="$(basename "$path")"

        echo -e "${GREEN}${number})${NC} $timestamp"

        ((number++))
    done

    echo
}

# ============================================================
# RECOVERY RESTORE
# ============================================================

recovery_restore() {

    if [[ ! -d "$RECOVERY_DIR" ]]; then
        log_error "Recovery каталог не існує:"
        log_error "$RECOVERY_DIR"
        return 1
    fi

    local recovery_backups=()

    while IFS= read -r -d '' path; do
        recovery_backups+=("$path")
    done < <(
        find "$RECOVERY_DIR" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -print0 |
        sort -z -r
    )

    if [[ "${#recovery_backups[@]}" -eq 0 ]]; then
        log_warning "Recovery backup відсутні"
        return 0
    fi

    echo
    echo -e "${CYAN}Доступні recovery backups:${NC}"
    echo

    local number=1

    for path in "${recovery_backups[@]}"; do

        local timestamp
        timestamp="$(basename "$path")"

        echo -e "${GREEN}${number})${NC} $timestamp"

        ((number++))
    done

    echo

    local selected

    read -rp "Вибери номер recovery backup: " selected

    if [[ ! "$selected" =~ ^[0-9]+$ ]]; then
        log_error "Некоректний номер"
        return 1
    fi

    if (( selected < 1 || selected > ${#recovery_backups[@]} )); then
        log_error "Номер поза діапазоном"
        return 1
    fi

    local selected_path
    selected_path="${recovery_backups[selected-1]}"

    echo
    log_info "Обрано:"
    log_info "$selected_path"

    echo

    read -rp "Продовжити restore? [y/N]: " answer

    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        log_warning "Recovery restore скасовано"
        return 0
    fi

    # Перед recovery restore зберігаємо
    # поточний стан HOME
    create_recovery_backup

    echo

    log_info "Відновлення з:"
    log_info "$selected_path"

    # --------------------------------------------------------
    # КАТАЛОГИ
    # --------------------------------------------------------

    for item in "${BACKUP_DIRS[@]}"; do

        local source="$selected_path/$item"
        local destination="$HOME_DIR/$item"

        if [[ ! -d "$source" ]]; then
            log_warning "У recovery немає: ~/$item"
            continue
        fi

        mkdir -p "$destination"

        rsync \
            --archive \
            "$source/" \
            "$destination/"

        log_success "Відновлено: ~/$item"
    done

    # --------------------------------------------------------
    # ФАЙЛИ
    # --------------------------------------------------------

    for item in "${BACKUP_FILES[@]}"; do

        local source="$selected_path/$item"
        local destination="$HOME_DIR/$item"

        if [[ ! -f "$source" ]]; then
            log_warning "У recovery немає: ~/$item"
            continue
        fi

        rsync \
            --archive \
            "$source" \
            "$destination"

        log_success "Відновлено: ~/$item"
    done

    log_success "Recovery restore завершено"
}

# ============================================================
# GIT CHECK
# ============================================================

check_git_repo() {

    check_dotfiles_dir

    if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
        log_error "Git repository не ініціалізований:"
        log_error "$DOTFILES_DIR"
        log_info "Виконай: ./$SCRIPT_NAME init"

        return 1
    fi
}

# ============================================================
# GIT INIT
# ============================================================

git_init() {

    create_dotfiles_dir

    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        log_warning "Git repository вже існує"
        return 0
    fi

    git -C "$DOTFILES_DIR" init

    log_success "Git repository створено"

    local gitignore="$DOTFILES_DIR/.gitignore"

    if [[ ! -f "$gitignore" ]]; then

        cat > "$gitignore" <<'EOF'
*.tmp
*.bak
*.swp
*.swo
.DS_Store
Thumbs.db
EOF

        log_success ".gitignore створено"
    fi
}

# ============================================================
# GIT STATUS
# ============================================================

git_status() {

    check_git_repo

    echo

    log_git "Git status"

    git -C "$DOTFILES_DIR" status --short

    echo
}

# ============================================================
# GIT COMMIT
# ============================================================

git_commit() {

    check_git_repo

    local message="${1:-}"

    if [[ -z "$message" ]]; then

        read -rp "Commit message: " message

        if [[ -z "$message" ]]; then
            log_error "Commit message не може бути порожнім"
            return 1
        fi
    fi

    if \
        git -C "$DOTFILES_DIR" diff --quiet &&
        git -C "$DOTFILES_DIR" diff --cached --quiet &&
        [[ -z "$(git -C "$DOTFILES_DIR" status --porcelain)" ]]
    then

        log_warning "Змін для commit немає"
        return 0
    fi

    git -C "$DOTFILES_DIR" add .

    git -C "$DOTFILES_DIR" commit -m "$message"

    log_success "Commit створено:"
    log_success "$message"
}

# ============================================================
# GIT LOG
# ============================================================

git_log() {

    check_git_repo

    git -C "$DOTFILES_DIR" log \
        --oneline \
        --decorate \
        --graph \
        --all \
        -20
}

# ============================================================
# GIT PUSH
# ============================================================

git_push() {

    check_git_repo

    if ! git -C "$DOTFILES_DIR" remote get-url origin &>/dev/null; then
        log_error "Remote 'origin' не налаштований"
        log_info "git -C ~/.dotfiles remote add origin <URL>"

        return 1
    fi

    local branch

    branch="$(git -C "$DOTFILES_DIR" branch --show-current)"

    if [[ -z "$branch" ]]; then
        log_error "Не вдалося визначити Git branch"
        return 1
    fi

    git -C "$DOTFILES_DIR" push \
        -u \
        origin \
        "$branch"

    log_success "Push завершено"
}

# ============================================================
# GIT PULL
# ============================================================

git_pull() {

    check_git_repo

    if ! git -C "$DOTFILES_DIR" remote get-url origin &>/dev/null; then
        log_error "Remote 'origin' не налаштований"
        return 1
    fi

    git -C "$DOTFILES_DIR" pull

    log_success "Pull завершено"
}

# ============================================================
# GIT REMOTE
# ============================================================

git_remote() {

    check_git_repo

    echo

    git -C "$DOTFILES_DIR" remote -v

    echo
}

# ============================================================
# GIT INFO
# ============================================================

git_info() {

    check_git_repo

    echo

    echo -e "${CYAN}Git repository:${NC}"
    echo "$DOTFILES_DIR"

    echo

    echo -e "${CYAN}Branch:${NC}"
    git -C "$DOTFILES_DIR" branch --show-current

    echo

    echo -e "${CYAN}Remote:${NC}"

    if git -C "$DOTFILES_DIR" remote get-url origin &>/dev/null; then
        git -C "$DOTFILES_DIR" remote -v
    else
        echo "origin не налаштований"
    fi

    echo
}

# ============================================================
# MENU
# ============================================================

menu() {

    while true; do

        clear

        echo
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}          DOTFILES MANAGER${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo

        echo -e "${CYAN}BACKUP${NC}"
        echo "  1) Backup"
        echo "  2) Restore"
        echo "  3) Diff"
        echo "  4) List"
        echo "  5) Status"
        echo "  6) Clean"

        echo

        echo -e "${CYAN}RECOVERY${NC}"
        echo "  7) Recovery list"
        echo "  8) Recovery restore"

        echo

        echo -e "${CYAN}GIT${NC}"
        echo "  9) Git init"
        echo " 10) Git status"
        echo " 11) Git commit"
        echo " 12) Git log"
        echo " 13) Git push"
        echo " 14) Git pull"
        echo " 15) Git remote"
        echo " 16) Git info"

        echo
        echo "  0) Exit"

        echo

        read -rp "Вибір: " choice

        echo

        case "$choice" in

            1)
                backup
                ;;

            2)
                restore
                ;;

            3)
                show_diff
                ;;

            4)
                list_backup
                ;;

            5)
                status
                ;;

            6)
                clean_backup
                ;;

            7)
                recovery_list
                ;;

            8)
                recovery_restore
                ;;

            9)
                git_init
                ;;

            10)
                git_status
                ;;

            11)
                git_commit
                ;;

            12)
                git_log
                ;;

            13)
                git_push
                ;;

            14)
                git_pull
                ;;

            15)
                git_remote
                ;;

            16)
                git_info
                ;;

            0)
                log_info "Вихід"
                exit 0
                ;;

            *)
                log_error "Невірний вибір"
                ;;
        esac

        echo
        read -rp "Натисни Enter для продовження..."
    done
}

# ============================================================
# HELP
# ============================================================

show_help() {

    cat <<EOF

${CYAN}DOTFILES MANAGER${NC}

Використання:
    $SCRIPT_NAME <command> [options]

${CYAN}BACKUP:${NC}

    backup
        Створити backup dotfiles

    restore
        Відновити dotfiles з backup

    diff
        Порівняти HOME з backup

    list
        Показати файли та каталоги backup

    status
        Показати стан dotfiles та recovery

    clean
        Видалити ~/.dotfiles

${CYAN}RECOVERY:${NC}

    recovery-list
        Показати всі timestamp recovery backups

    recovery-restore
        Відновити вибраний recovery backup

${CYAN}GIT:${NC}

    init
        Ініціалізувати Git repository

    git-status
        Показати Git status

    commit [message]
        Створити Git commit

    log
        Показати Git history

    push
        Відправити зміни на remote

    pull
        Отримати зміни з remote

    remote
        Показати Git remote

    info
        Показати Git інформацію

${CYAN}OPTIONS:${NC}

    --dry-run
        Показати операції без змін

    -h, --help
        Показати цю довідку

EOF
}

# ============================================================
# ARGUMENT PARSER
# ============================================================

parse_arguments() {

    if [[ "$#" -eq 0 ]]; then
        menu
        return
    fi

    local command="$1"
    shift

    local positional_args=()

    while [[ "$#" -gt 0 ]]; do

        case "$1" in

            --dry-run)
                DRY_RUN=true
                ;;

            -h|--help)
                show_help
                return 0
                ;;

            -*)
                log_error "Невідома опція: $1"
                return 1
                ;;

            *)
                positional_args+=("$1")
                ;;
        esac

        shift
    done

    case "$command" in

        backup)
            backup
            ;;

        restore)
            restore
            ;;

        diff)
            show_diff
            ;;

        list)
            list_backup
            ;;

        status)
            status
            ;;

        clean)
            clean_backup
            ;;

        recovery-list)
            recovery_list
            ;;

        recovery-restore)
            recovery_restore
            ;;

        init)
            git_init
            ;;

        git-status)
            git_status
            ;;

        commit)
            git_commit "${positional_args[0]:-}"
            ;;

        log)
            git_log
            ;;

        push)
            git_push
            ;;

        pull)
            git_pull
            ;;

        remote)
            git_remote
            ;;

        info)
            git_info
            ;;

        menu)
            menu
            ;;

        help)
            show_help
            ;;

        *)
            log_error "Невідома команда: $command"
            echo
            show_help
            return 1
            ;;
    esac
}

# ============================================================
# MAIN
# ============================================================

main() {

    check_dependencies

    parse_arguments "$@"
}

main "$@"
