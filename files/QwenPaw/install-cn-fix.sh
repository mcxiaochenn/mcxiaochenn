#!/usr/bin/env bash
# QwenPaw Installer (China-optimized)
# Usage: curl -fsSL <url>/install.sh | bash
#    or: bash install.sh [--version X.Y.Z] [--from-source]
#
# Installs QwenPaw into ~/.qwenpaw with a uv-managed Python environment.
# Users do NOT need Python pre-installed — uv handles everything.
#
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │  ChenDusk + Claude 中国大陆优化版本                                          │
# │  优化内容:                                                                   │
# │    - uv 安装使用 ghproxy 代理加速                                            │
# │    - GitHub 克隆使用 ghproxy 代理加速                                         │
# │    - PyPI 源智能选择 (清华/阿里/官方)                                         │
# │    - npm 源使用淘宝镜像 (npmmirror.com)                                       │
# │    - 网络超时优化，避免卡死                                                    │
# └─────────────────────────────────────────────────────────────────────────────┘
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    BOLD="\033[1m"
    GREEN="\033[0;32m"
    YELLOW="\033[0;33m"
    RED="\033[0;31m"
    RESET="\033[0m"
else
    BOLD="" GREEN="" YELLOW="" RED="" RESET=""
fi

info()  { printf "${GREEN}[qwenpaw]${RESET} %s\n" "$*"; }
warn()  { printf "${YELLOW}[qwenpaw]${RESET} %s\n" "$*"; }
error() { printf "${RED}[qwenpaw]${RESET} %s\n" "$*" >&2; }
die()   { error "$@"; exit 1; }

# ── Defaults ──────────────────────────────────────────────────────────────────
QWENPAW_HOME="${QWENPAW_HOME:-$HOME/.qwenpaw}"
QWENPAW_VENV="$QWENPAW_HOME/venv"
QWENPAW_BIN="$QWENPAW_HOME/bin"
PYTHON_VERSION="3.12"
QWENPAW_REPO="https://github.com/agentscope-ai/QwenPaw.git"

# ── 网络超时配置 (秒) ────────────────────────────────────────────────────────
CURL_CONNECT_TIMEOUT=5
CURL_MAX_TIMEOUT=30

# ── 镜像源配置 ────────────────────────────────────────────────────────────────
# uv 安装镜像 (ghproxy 代理 GitHub)
UV_INSTALL_MIRRORS=(
    "https://ghfast.top/https://github.com/astral-sh/uv/releases/latest/download/uv-installer.sh"
    "https://ghproxy.net/https://github.com/astral-sh/uv/releases/latest/download/uv-installer.sh"
    "https://mirror.ghproxy.com/https://github.com/astral-sh/uv/releases/latest/download/uv-installer.sh"
    "https://astral.sh/uv/install.sh"
)

# GitHub 克隆代理
GITHUB_PROXY_PREFIXES=(
    "https://ghfast.top/"
    "https://ghproxy.net/"
    "https://mirror.ghproxy.com/"
    ""
)

# PyPI 镜像源 (按优先级排序)
PYPI_MIRRORS=(
    "https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple/"
    "https://mirrors.aliyun.com/pypi/simple/"
    "https://pypi.tuna.tsinghua.edu.cn/simple/"
    "https://pypi.org/simple/"
)

# npm 镜像源
NPM_MIRROR="https://registry.npmmirror.com"

# ── 智能选择 PyPI 源 ─────────────────────────────────────────────────────────
choose_pypi_mirror() {
    for mirror in "${PYPI_MIRRORS[@]}"; do
        if curl -s --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIMEOUT" "$mirror" > /dev/null 2>&1; then
            echo "$mirror"
            info "Using PyPI mirror: $mirror" >&2
            return 0
        fi
    done
    # 如果所有源都失败，返回清华源作为默认
    echo "${PYPI_MIRRORS[0]}"
    warn "All PyPI mirrors test failed, using default: ${PYPI_MIRRORS[0]}" >&2
}

PYPI_MIRROR=$(choose_pypi_mirror)

# 清除旧虚拟环境，跳过交互提示
export UV_VENV_CLEAR=1

VERSION=""
FROM_SOURCE=false
SOURCE_DIR=""
EXTRAS=""
PRERELEASE=false

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="$2"; shift 2 ;;
        --from-source)
            FROM_SOURCE=true
            # Accept optional path argument (next arg that doesn't start with --)
            if [[ $# -ge 2 && "$2" != --* ]]; then
                SOURCE_DIR="$(cd "$2" && pwd)" || die "Directory not found: $2"
                shift
            fi
            shift ;;
        --extras)
            EXTRAS="$2"; shift 2 ;;
        --prerelease)
            PRERELEASE=true; shift ;;
        -h|--help)
            cat <<EOF
QwenPaw Installer (China-optimized by ChenDusk+Claude)

Usage: bash install.sh [OPTIONS]

Options:
  --version <VER>       Install a specific version (e.g. 0.0.2)
  --from-source [DIR]   Install from source. If DIR is given, use that local
                        directory; otherwise clone from GitHub.
  --extras <EXTRAS>     Comma-separated optional extras to install
                        (e.g. dev, whisper)
  --prerelease          Install the latest PyPI release, including pre-releases
  -h, --help            Show this help

Environment:
  QWENPAW_HOME        Installation directory (default: ~/.qwenpaw)

China-optimized features:
  - uv install via ghproxy mirror
  - GitHub clone via ghproxy mirror
  - PyPI mirror auto-selection (Tsinghua/Aliyun/Official)
  - npm registry mirror (npmmirror.com)
EOF
            exit 0 ;;
        *)
            die "Unknown option: $1 (try --help)" ;;
    esac
done

# ── OS check ──────────────────────────────────────────────────────────────────
OS="$(uname -s)"
case "$OS" in
    Linux|Darwin) ;;
    *) die "Unsupported OS: $OS. This installer supports Linux and macOS only." ;;
esac

printf "${GREEN}[qwenpaw]${RESET} Installing QwenPaw into ${BOLD}%s${RESET}\n" "$QWENPAW_HOME"

# ── Step 1: Ensure uv is available ───────────────────────────────────────────
ensure_uv() {
    if command -v uv &>/dev/null; then
        info "uv found: $(command -v uv)"
        return
    fi

    # Check common install locations not yet on PATH
    for candidate in "$HOME/.local/bin/uv" "$HOME/.cargo/bin/uv"; do
        if [ -x "$candidate" ]; then
            export PATH="$(dirname "$candidate"):$PATH"
            info "uv found: $candidate"
            return
        fi
    done

    info "Installing uv (trying mirror sources)..."

    # 尝试从多个镜像源安装 uv
    local install_success=false
    for mirror_url in "${UV_INSTALL_MIRRORS[@]}"; do
        info "Trying: $mirror_url"
        if curl -LsSf --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIMEOUT" "$mirror_url" 2>/dev/null | sh; then
            install_success=true
            info "uv installed successfully from mirror"
            break
        fi
        warn "Failed to install from this mirror, trying next..."
    done

    if [ "$install_success" = false ]; then
        die "Failed to install uv from all mirrors. Please install manually:
  - Run: curl -LsSf https://astral.sh/uv/install.sh | sh
  - Or download from: https://github.com/astral-sh/uv/releases"
    fi

    # Source the env file uv's installer creates, or add common paths
    if [ -f "$HOME/.local/bin/env" ]; then
        # shellcheck disable=SC1091
        . "$HOME/.local/bin/env"
    fi
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

    command -v uv &>/dev/null || die "Failed to install uv. Please install it manually: https://docs.astral.sh/uv/"
    info "uv installed successfully"
}

ensure_uv

# ── Step 2: Create / update virtual environment ──────────────────────────────
if [ -d "$QWENPAW_VENV" ]; then
    info "Existing environment found, upgrading..."
else
    info "Creating Python $PYTHON_VERSION environment..."
fi

uv venv "$QWENPAW_VENV" --python "$PYTHON_VERSION" --quiet

# Verify the venv was created
[ -x "$QWENPAW_VENV/bin/python" ] || die "Failed to create virtual environment"
info "Python environment ready ($("$QWENPAW_VENV/bin/python" --version))"

# ── Step 3: Install QwenPaw ────────────────────────────────────────────────────
# Build extras suffix: "" or "[dev,whisper]"
EXTRAS_SUFFIX=""
if [ -n "$EXTRAS" ]; then
    EXTRAS_SUFFIX="[$EXTRAS]"
fi

## Ensure console frontend assets are in src/qwenpaw/console/ for source installs.
## Sets _CONSOLE_COPIED=1 if we populated the directory (so we can clean up).
_CONSOLE_COPIED=0
_CONSOLE_AVAILABLE=0
prepare_console() {
    local repo_dir="$1"
    local console_src="$repo_dir/console/dist"
    local console_dest="$repo_dir/src/qwenpaw/console"

    # Already populated
    if [ -f "$console_dest/index.html" ]; then
        _CONSOLE_AVAILABLE=1
        return
    fi

    # Copy pre-built assets if available (e.g. developer already ran npm build)
    if [ -d "$console_src" ] && [ -f "$console_src/index.html" ]; then
        info "Copying console frontend assets..."
        mkdir -p "$console_dest"
        cp -R "$console_src/"* "$console_dest/"
        _CONSOLE_COPIED=1
        _CONSOLE_AVAILABLE=1
        return
    fi

    # Try to build if npm is available
    if [ ! -f "$repo_dir/console/package.json" ]; then
        warn "Console source not found — the web UI won't be available."
        return
    fi

    if ! command -v npm &>/dev/null; then
        warn "npm not found — skipping console frontend build."
        warn "Install Node.js from https://nodejs.org/ then re-run this installer,"
        warn "or run 'cd console && npm ci && npm run build' manually."
        return
    fi

    info "Building console frontend (npm ci && npm run build)..."
    # 使用淘宝 npm 镜像源
    (cd "$repo_dir/console" && npm ci --registry "$NPM_MIRROR" && npm run build)
    if [ -f "$console_src/index.html" ]; then
        mkdir -p "$console_dest"
        cp -R "$console_src/"* "$console_dest/"
        _CONSOLE_COPIED=1
        _CONSOLE_AVAILABLE=1
        info "Console frontend built successfully"
        return
    fi

    warn "Console build completed but index.html not found — the web UI won't be available."
}

## Remove console assets we copied into the source tree.
cleanup_console() {
    local repo_dir="$1"
    if [ "$_CONSOLE_COPIED" = 1 ]; then
        rm -rf "$repo_dir/src/qwenpaw/console/"*
    fi
}

## Ensure docs are available in src/qwenpaw/docs/ for source installs.
_DOCS_COPIED=0
prepare_docs() {
    local repo_dir="$1"
    local docs_src="$repo_dir/website/public/docs"
    local docs_dest="$repo_dir/src/qwenpaw/docs"

    if [ -d "$docs_dest" ] && ls "$docs_dest"/*.md >/dev/null 2>&1; then
        return
    fi

    if [ -d "$docs_src" ] && ls "$docs_src"/*.md >/dev/null 2>&1; then
        mkdir -p "$docs_dest"
        cp "$docs_src/"*.md "$docs_dest/"
        _DOCS_COPIED=1
    fi
}

cleanup_docs() {
    local repo_dir="$1"
    if [ "$_DOCS_COPIED" = 1 ]; then
        rm -rf "$repo_dir/src/qwenpaw/docs"
    fi
}

# 尝试从多个 GitHub 代理克隆仓库
git_clone_with_proxy() {
    local repo_url="$1"
    local target_dir="$2"

    for proxy_prefix in "${GITHUB_PROXY_PREFIXES[@]}"; do
        local full_url="${proxy_prefix}${repo_url}"
        info "Trying to clone: $full_url"
        if git clone --depth 1 "$full_url" "$target_dir" 2>/dev/null; then
            info "Clone successful from: $full_url"
            return 0
        fi
        warn "Clone failed from this proxy, trying next..."
    done

    die "Failed to clone repository from all mirrors. Please check your network or clone manually:
  git clone --depth 1 $repo_url"
}

if [ "$FROM_SOURCE" = true ]; then
    if [ -n "$SOURCE_DIR" ]; then
        info "Installing QwenPaw from local source: $SOURCE_DIR"
        prepare_console "$SOURCE_DIR"
        prepare_docs "$SOURCE_DIR"
        info "Installing package from source..."
        uv pip install "${SOURCE_DIR}${EXTRAS_SUFFIX}" --python "$QWENPAW_VENV/bin/python" --index-url "$PYPI_MIRROR"
        cleanup_console "$SOURCE_DIR"
        cleanup_docs "$SOURCE_DIR"
    else
        info "Installing QwenPaw from source (GitHub via mirror)..."
        CLONE_DIR="$(mktemp -d)"
        trap 'rm -rf "$CLONE_DIR"' EXIT
        git_clone_with_proxy "$QWENPAW_REPO" "$CLONE_DIR"
        prepare_console "$CLONE_DIR"
        prepare_docs "$CLONE_DIR"
        info "Installing package from source..."
        uv pip install "${CLONE_DIR}${EXTRAS_SUFFIX}" --python "$QWENPAW_VENV/bin/python" --index-url "$PYPI_MIRROR"
        # CLONE_DIR is cleaned up by trap; no need for cleanup_console/cleanup_docs
    fi
else
    PACKAGE="qwenpaw"
    if [ -n "$VERSION" ]; then
        PACKAGE="qwenpaw==$VERSION"
    fi

    PRERELEASE_ARGS=()
    if [ "$PRERELEASE" = true ]; then
        PRERELEASE_ARGS=(--prerelease=allow)
    fi

    info "Installing ${PACKAGE}${EXTRAS_SUFFIX} from PyPI..."
    uv pip install "${PACKAGE}${EXTRAS_SUFFIX}" --python "$QWENPAW_VENV/bin/python" --quiet --index-url "$PYPI_MIRROR" --refresh-package qwenpaw ${PRERELEASE_ARGS[@]+"${PRERELEASE_ARGS[@]}"}
fi

# Verify the CLI entry point exists
[ -x "$QWENPAW_VENV/bin/qwenpaw" ] || die "Installation failed: qwenpaw CLI not found in venv"
info "QwenPaw installed successfully"

# Check console availability (for PyPI installs, check the installed package)
if [ "$_CONSOLE_AVAILABLE" = 0 ]; then
    # Check if console assets were included in the installed package
    CONSOLE_CHECK="$("$QWENPAW_VENV/bin/python" -c "import importlib.resources, qwenpaw; p=importlib.resources.files('qwenpaw')/'console'/'index.html'; print('yes' if p.is_file() else 'no')" 2>/dev/null || echo 'no')"
    if [ "$CONSOLE_CHECK" = "yes" ]; then
        _CONSOLE_AVAILABLE=1
    fi
fi

# ── Step 4: Create wrapper script ────────────────────────────────────────────
mkdir -p "$QWENPAW_BIN"

cat > "$QWENPAW_BIN/qwenpaw" << 'WRAPPER'
#!/usr/bin/env bash
# QwenPaw CLI wrapper — delegates to the uv-managed environment.
set -euo pipefail

QWENPAW_HOME="${QWENPAW_HOME:-$HOME/.qwenpaw}"
REAL_BIN="$QWENPAW_HOME/venv/bin/qwenpaw"

if [ ! -x "$REAL_BIN" ]; then
    echo "Error: QwenPaw environment not found at $QWENPAW_HOME/venv" >&2
    echo "Please reinstall: curl -fsSL <install-url> | bash" >&2
    exit 1
fi

exec "$REAL_BIN" "$@"
WRAPPER

chmod +x "$QWENPAW_BIN/qwenpaw"
info "Wrapper created at $QWENPAW_BIN/qwenpaw"

# ── Step 5: Update PATH in shell profile ─────────────────────────────────────
PATH_ENTRY="export PATH=\"\$HOME/.qwenpaw/bin:\$PATH\""

add_to_profile() {
    local profile="$1"
    if [ -f "$profile" ] && grep -qF '.qwenpaw/bin' "$profile"; then
        return 0  # already present
    fi
    if [ -f "$profile" ] || [ "$2" = "create" ]; then
        printf '\n# QwenPaw\n%s\n' "$PATH_ENTRY" >> "$profile"
        info "Updated $profile"
        return 0
    fi
    return 1
}

UPDATED_PROFILE=false

case "$OS" in
    Darwin)
        add_to_profile "$HOME/.zshrc" "create" && UPDATED_PROFILE=true
        # Also update bash profile if it exists
        add_to_profile "$HOME/.bash_profile" "no-create" || true
        ;;
    Linux)
        add_to_profile "$HOME/.bashrc" "create" && UPDATED_PROFILE=true
        # Also update zshrc if it exists
        add_to_profile "$HOME/.zshrc" "no-create" || true
        ;;
esac

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
printf "${GREEN}${BOLD}QwenPaw installed successfully!${RESET}\n"
echo ""

# Install summary
printf "  Install location:  ${BOLD}%s${RESET}\n" "$QWENPAW_HOME"
printf "  Python:            ${BOLD}%s${RESET}\n" "$("$QWENPAW_VENV/bin/python" --version 2>&1)"
if [ "$_CONSOLE_AVAILABLE" = 1 ]; then
    printf "  Console (web UI):  ${GREEN}available${RESET}\n"
else
    printf "  Console (web UI):  ${YELLOW}not available${RESET}\n"
    echo "                     Install Node.js and re-run to enable the web UI."
fi
echo ""

if [ "$UPDATED_PROFILE" = true ]; then
    echo "To get started, open a new terminal or run:"
    echo ""
    printf "  ${BOLD}source ~/.zshrc${RESET}  # or ~/.bashrc\n"
    echo ""
fi

echo "Then run:"
echo ""
printf "  ${BOLD}qwenpaw init${RESET}       # first-time setup\n"
printf "  ${BOLD}qwenpaw app${RESET}        # start QwenPaw\n"
echo ""
printf "To upgrade later, re-run this installer.\n"
printf "To uninstall, run: ${BOLD}qwenpaw uninstall${RESET}\n"
