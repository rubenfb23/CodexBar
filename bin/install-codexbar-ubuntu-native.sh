#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFTLY_VERSION="${SWIFTLY_VERSION:-1.1.1}"
SWIFT_VERSION="${SWIFT_VERSION:-6.2.1}"
LOCAL_BIN_DIR="${HOME}/.local/bin"
DESKTOP_FILE_DIR="${HOME}/.local/share/applications"
SWIFTLY_HOME_DIR="${HOME}/.local/share/swiftly"
SWIFTLY_BIN_DIR="${HOME}/.local/bin"

log() {
    printf '[codexbar-linux] %s\n' "$*"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'Missing required command: %s\n' "$1" >&2
        exit 1
    }
}

run_privileged() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    else
        require_cmd sudo
        sudo "$@"
    fi
}

ensure_apt_packages() {
    if ! command -v apt-get >/dev/null 2>&1; then
        log "Skipping apt package install because apt-get is unavailable."
        return
    fi

    log "Installing Ubuntu build/runtime packages for the native app"
    run_privileged apt-get update
    run_privileged apt-get install -y \
        ca-certificates \
        curl \
        gpg \
        pkg-config \
        xdg-utils \
        libgtk-4-dev \
        libadwaita-1-dev
}

source_swiftly_env_if_present() {
    if [[ -f "${SWIFTLY_HOME_DIR}/env.sh" ]]; then
        # shellcheck disable=SC1090
        source "${SWIFTLY_HOME_DIR}/env.sh"
        export PATH="${SWIFTLY_BIN_DIR}:${PATH}"
    fi
}

bootstrap_swift_if_needed() {
    source_swiftly_env_if_present
    if command -v swift >/dev/null 2>&1; then
        return
    fi

    require_cmd curl
    require_cmd tar

    local arch
    arch="$(uname -m)"
    local archive_url="https://download.swift.org/swiftly/linux/swiftly-${SWIFTLY_VERSION}-${arch}.tar.gz"
    local temp_dir
    temp_dir="$(mktemp -d)"
    local post_install
    post_install="$(mktemp)"

    log "Swift not found. Bootstrapping Swiftly from ${archive_url}"
    curl -fsSL "${archive_url}" -o "${temp_dir}/swiftly.tar.gz"
    tar -xzf "${temp_dir}/swiftly.tar.gz" -C "${temp_dir}"
    mkdir -p "${SWIFTLY_BIN_DIR}"
    install -m 0755 "${temp_dir}/swiftly" "${SWIFTLY_BIN_DIR}/swiftly"

    "${SWIFTLY_BIN_DIR}/swiftly" init --assume-yes --skip-install
    source_swiftly_env_if_present

    log "Installing Swift ${SWIFT_VERSION}"
    swiftly install "${SWIFT_VERSION}" --use --assume-yes --post-install-file "${post_install}"
    if [[ -s "${post_install}" ]]; then
        log "Running Swift toolchain post-install steps"
        run_privileged bash "${post_install}"
    fi
    source_swiftly_env_if_present
}

build_binaries() {
    require_cmd swift

    log "Building CodexBarCLI"
    swift build -c release --product CodexBarCLI

    log "Building CodexBarLinux"
    swift build -c release --product CodexBarLinux
}

install_binaries() {
    local bin_dir
    bin_dir="$(swift build -c release --product CodexBarLinux --show-bin-path)"
    mkdir -p "${LOCAL_BIN_DIR}"

    install -m 0755 "${bin_dir}/CodexBarCLI" "${LOCAL_BIN_DIR}/CodexBarCLI"
    install -m 0755 "${bin_dir}/CodexBarLinux" "${LOCAL_BIN_DIR}/CodexBarLinux"
    ln -sf "CodexBarCLI" "${LOCAL_BIN_DIR}/codexbar"
    ln -sf "CodexBarLinux" "${LOCAL_BIN_DIR}/codexbar-linux"
}

install_desktop_file() {
    mkdir -p "${DESKTOP_FILE_DIR}"
    cat > "${DESKTOP_FILE_DIR}/com.steipete.codexbar.linux.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=CodexBar Ubuntu
Comment=Native Ubuntu window for CodexBar usage
Exec=${LOCAL_BIN_DIR}/codexbar-linux
Terminal=false
Categories=Development;Utility;
StartupNotify=true
EOF
}

main() {
    ensure_apt_packages
    bootstrap_swift_if_needed
    build_binaries
    install_binaries
    install_desktop_file

    log "Installed into ${LOCAL_BIN_DIR}"
    log "If this shell still cannot find swift, run: source ${SWIFTLY_HOME_DIR}/env.sh"
    log "Launch with: ${LOCAL_BIN_DIR}/codexbar-linux"
}

main "$@"
