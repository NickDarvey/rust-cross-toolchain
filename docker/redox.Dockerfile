# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0 OR MIT

# Refs:
# - https://github.com/rust-lang/rust/blob/1.70.0/src/ci/docker/host-x86_64/dist-various-1/install-x86_64-redox.sh

ARG UBUNTU_VERSION=22.04

FROM ghcr.io/taiki-e/downloader as toolchain
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG RUST_TARGET
RUN mkdir -p /toolchain
# Use mirror: https://github.com/rust-lang/rust/commit/abd265ed0ed4fff89f87772150da1f66c863d7e1
RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://ci-mirrors.rust-lang.org/rustc/2022-11-27-relibc-install.tar.gz" \
        | tar xzf - -C /toolchain
# RUN curl --proto '=https' --tlsv1.2 -fsSL --retry 10 --retry-connrefused "https://static.redox-os.org/toolchain/${RUST_TARGET}/relibc-install.tar.gz" \
#         | tar xzf - -C /toolchain

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
COPY --from=toolchain /toolchain "${TOOLCHAIN_DIR}"

RUN --mount=type=bind,target=/docker \
    /docker/base/common.sh

ARG GCC_VERSION=13.2.0
RUN --mount=type=bind,target=/docker \
    CFLAGS="-I\"\${toolchain_dir}\"/${RUST_TARGET}/include" \
    CXXFLAGS="-std=c++14 -isystem\"\${toolchain_dir}\"/${RUST_TARGET}/include -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION} -I\"\${toolchain_dir}\"/${RUST_TARGET}/include/c++/${GCC_VERSION}/${RUST_TARGET}" \
    /docker/clang-cross.sh

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as test-base
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
COPY /test-base.sh /
RUN /test-base.sh
ARG RUST_TARGET
COPY /test-base /test-base
RUN /test-base/target.sh
COPY /test /test

FROM test-base as test-relocated
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}"/. /usr/local/
RUN /test/test.sh gcc
RUN /test/test.sh clang
RUN touch /DONE

FROM test-base as test
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
RUN /test/check.sh
RUN /test/test.sh gcc
RUN /test/test.sh clang
# COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-eEuxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
ENV PATH="/${RUST_TARGET}/bin:$PATH"
