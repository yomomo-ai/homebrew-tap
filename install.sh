#!/bin/sh
#
# influo-cli installer for macOS / Linux.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/yomomo-ai/homebrew-tap/main/install.sh | sh
#
# Detects OS + arch, downloads the latest release archive from the public
# tap repo (yomomo-ai/homebrew-tap, which also hosts the brew formula),
# and drops the binary into a user-writable bin directory on PATH.
# Mirrors the pattern of Anthropic's Claude installer.
#
# Override the install prefix with INFLUO_PREFIX, e.g.
#   curl … | INFLUO_PREFIX=$HOME/.local sh

set -eu

RELEASES_REPO="yomomo-ai/homebrew-tap"
BIN_NAME="influo"

red()   { printf '\033[31m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
muted() { printf '\033[90m%s\033[0m\n' "$1"; }
bold()  { printf '\033[1m%s\033[0m\n' "$1"; }

# ---- detect platform -------------------------------------------------------

os_raw=$(uname -s 2>/dev/null || echo unknown)
case "$os_raw" in
    Darwin)  os="darwin" ;;
    Linux)   os="linux" ;;
    *)       red "✗ 不支持的操作系统: $os_raw"; exit 1 ;;
esac

arch_raw=$(uname -m 2>/dev/null || echo unknown)
case "$arch_raw" in
    x86_64|amd64)   arch="amd64" ;;
    arm64|aarch64)  arch="arm64" ;;
    *)              red "✗ 不支持的架构: $arch_raw"; exit 1 ;;
esac

bold "influo · installer"
muted "─────────────────────────"
echo "  目标平台      $os/$arch"

# ---- look up latest release ------------------------------------------------

# Avoid jq dependency — pull tag_name with sed. GitHub's API returns a stable
# JSON shape for /releases/latest so a regex is fine.
tag=$(curl -fsSL "https://api.github.com/repos/${RELEASES_REPO}/releases/latest" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n1)
if [ -z "$tag" ]; then
    red "✗ 无法获取最新版本 (网络问题或仓库为空?)"
    exit 1
fi
echo "  最新版本      $tag"

# ---- download + extract ----------------------------------------------------

archive="${BIN_NAME}_${os}_${arch}.tar.gz"
url="https://github.com/${RELEASES_REPO}/releases/download/${tag}/${archive}"
echo "  下载          $url"

tmp=$(mktemp -d 2>/dev/null || mktemp -d -t influo)
trap 'rm -rf "$tmp"' EXIT INT TERM

if ! curl -fsSL "$url" -o "$tmp/${archive}"; then
    red "✗ 下载失败: $url"
    exit 1
fi
if ! tar -xzf "$tmp/${archive}" -C "$tmp"; then
    red "✗ 解压失败"
    exit 1
fi
if [ ! -f "$tmp/${BIN_NAME}" ]; then
    red "✗ 归档里没有找到 ${BIN_NAME} 可执行文件"
    exit 1
fi
chmod +x "$tmp/${BIN_NAME}"

# ---- install ---------------------------------------------------------------

# Prefer a user-writable bin dir on PATH; only fall back to /usr/local with
# sudo. INFLUO_PREFIX overrides the search.
candidates="${INFLUO_PREFIX:-} $HOME/.local $HOME/bin /usr/local"
target=""
for prefix in $candidates; do
    [ -z "$prefix" ] && continue
    bindir="$prefix/bin"
    if [ -d "$bindir" ] && [ -w "$bindir" ]; then
        target="$bindir/${BIN_NAME}"
        break
    fi
    # Allow creating $HOME/.local/bin / $HOME/bin on the fly — common on
    # fresh user accounts.
    case "$prefix" in
        "$HOME/"*)
            if mkdir -p "$bindir" 2>/dev/null && [ -w "$bindir" ]; then
                target="$bindir/${BIN_NAME}"
                break
            fi
            ;;
    esac
done

needs_sudo=""
if [ -z "$target" ]; then
    target="/usr/local/bin/${BIN_NAME}"
    needs_sudo="1"
fi

if [ -n "$needs_sudo" ]; then
    muted "  安装至 $target (需要 sudo 权限)"
    sudo mv "$tmp/${BIN_NAME}" "$target"
else
    echo "  安装位置      $target"
    mv "$tmp/${BIN_NAME}" "$target"
fi

green "✓ 安装完成"

# ---- PATH hint -------------------------------------------------------------

# If we landed in a directory not currently on PATH, print the line the user
# needs to add to their shell rc.
case ":$PATH:" in
    *":$(dirname "$target"):"*) ;;
    *)
        muted "─────────────────────────"
        echo "  $(dirname "$target") 不在 PATH 中。把下面这行加到 ~/.zshrc 或 ~/.bashrc:"
        echo
        echo "    export PATH=\"$(dirname "$target"):\$PATH\""
        ;;
esac

muted "─────────────────────────"
echo "  运行          ${BIN_NAME}"
