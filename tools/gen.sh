#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -euo pipefail
IFS=$'\n\t'
cd "$(dirname "$0")"/..

# shellcheck disable=SC2154
trap 's=$?; echo >&2 "$0: error on line "${LINENO}": ${BASH_COMMAND}"; exit ${s}' ERR

# USAGE:
#    ./tools/gen.sh

bail() {
    echo >&2 "error: $*"
    exit 1
}

known_target_group=(
    # Linux
    linux_gnu
    linux_musl
    linux_uclibc
    linux_ohos
    android
    # Darwin
    macos
    ios
    tvos
    watchos
    # BSD
    freebsd
    netbsd
    openbsd
    dragonfly
    # Solarish
    solaris
    illumos
    # Windows
    windows_msvc
    windows_gnu
    # WASM
    wasi
    emscripten
    wasm_unknown
    # Other
    aix
    cuda
    espidf
    fuchsia
    haiku
    hermit
    horizon
    l4re
    nto
    psp
    psx
    redox
    sgx
    solid_asp3
    uefi
    vita
    vxworks
    xous
    none
)

rm -rf tmp/gen/os
mkdir -p tmp/gen/os
# shellcheck disable=SC2207
rustc_targets=($(rustc --print target-list))
# shellcheck disable=SC2207
rustup_targets=($(rustup target list | sed 's/ .*//g'))
for target_spec in $(rustc -Z unstable-options --print all-target-specs-json | jq -c '. | to_entries | .[]'); do
    target=$(jq <<<"${target_spec}" -r '.key')
    target_spec=$(jq <<<"${target_spec}" -c '.value')
    os=$(jq <<<"${target_spec}" -r '.os')
    if [[ "${os}" == "null" ]]; then
        os=none
    fi
    env=$(jq <<<"${target_spec}" -r '.env')
    if [[ "${env}" == "null" ]]; then
        case "${target}" in
            wasm*-unknown-unknown) echo "${target}" >>"tmp/gen/os/wasm_unknown" ;;
            *) echo "${target}" >>"tmp/gen/os/${os}" ;;
        esac
    else
        case "${os}" in
            linux | windows) echo "${target}" >>"tmp/gen/os/${os}_${env}" ;;
            none | unknown) echo "${target}" >>"tmp/gen/os/${env}" ;;
            *) echo "${target}" >>"tmp/gen/os/${os}" ;;
        esac
    fi
done
target_list_file=tools/target-list-generated
cat >"${target_list_file}" <<EOF
#!/bin/false
# shellcheck shell=bash # not executable
# shellcheck disable=SC2034

# This file is @generated by $(basename "$0").
# It is not intended for manual editing.

EOF
os_list=()
emit_targets() {
    os_list+=("${os}")
    echo "${os}_targets=(" >>"${target_list_file}"
    # shellcheck disable=SC2013
    for target in $(cat "${os_targets}"); do
        tier3=1
        for t in "${rustup_targets[@]}"; do
            if [[ "${target}" == "${t}" ]]; then
                tier3=''
                echo "    ${target}" >>"${target_list_file}"
                break
            fi
        done
        if [[ -n "${tier3}" ]]; then
            echo "    ${target} # tier3" >>"${target_list_file}"
        fi
    done
    echo ")" >>"${target_list_file}"
}
for os in "${known_target_group[@]}"; do
    os_targets="tmp/gen/os/${os}"
    if [[ -e "${os_targets}" ]]; then
        emit_targets
        rm -f "${os_targets}"
    else
        bail "there is no target for '${os}_targets' group"
    fi
done
rmdir tmp/gen/os &>/dev/null \
    || for os_targets in tmp/gen/os/*; do
        os=$(basename "${os_targets}")
        emit_targets
    done
echo "targets=(" >>"${target_list_file}"
for os in "${os_list[@]}"; do
    echo "    \${${os}_targets[@]+\"\${${os}_targets[@]}\"}" >>"${target_list_file}"
done
echo ")" >>"${target_list_file}"

support_status_file=platform-support-status.md
tier3_support_status_file=platform-support-status-tier3.md
cat >"${support_status_file}" <<EOF
<!--
This file is @generated by $(basename "$0").
It is not intended for manual editing.
-->

# Tier 1 & Tier 2 Platform Support Status

See [${tier3_support_status_file}](${tier3_support_status_file}) for Tier 3 platforms.

EOF
cat >"${tier3_support_status_file}" <<EOF
<!--
This file is @generated by $(basename "$0").
It is not intended for manual editing.
-->

# Tier 3 Platform Support Status

See [${support_status_file}](${support_status_file}) for Tier 1 & Tier 2 platforms.

EOF
support_list=$(<tools/target-list-shared.sh)
for target in "${rustc_targets[@]}"; do
    tier3=1
    for t in "${rustup_targets[@]}"; do
        if [[ "${target}" == "${t}" ]]; then
            tier3=''
            break
        fi
    done
    if grep <<<"${support_list}" -Eq "^ +${target}( |$)"; then
        status='- [x]'
    else
        status='- [ ]'
    fi
    if [[ -n "${tier3}" ]]; then
        echo "${status} ${target}" >>"${tier3_support_status_file}"
    else
        echo "${status} ${target}" >>"${support_status_file}"
    fi
done
