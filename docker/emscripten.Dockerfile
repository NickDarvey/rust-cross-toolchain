# syntax=docker/dockerfile:1.3-labs

ARG UBUNTU_VERSION=18.04

# https://github.com/rust-lang/rust/blob/3c857f48ce12d1f98f3ea6d48eb9e33d8d60c985/src/ci/docker/scripts/emscripten.sh#L23
ARG EMSCRIPTEN_VERSION=1.39.20
ARG NODE_VERSION=12.18.1

FROM emscripten/emsdk:"${EMSCRIPTEN_VERSION}" as emsdk

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as builder
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG TOOLCHAIN_DIR="/${RUST_TARGET}"
ARG SYSROOT_DIR="${TOOLCHAIN_DIR}/${RUST_TARGET}"
COPY --from=emsdk /emsdk "${TOOLCHAIN_DIR}"

FROM ghcr.io/taiki-e/build-base:ubuntu-"${UBUNTU_VERSION}" as test-base
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
COPY /test-base.sh /
RUN /test-base.sh
RUN apt-get update -qq && apt-get -o Dpkg::Use-Pty=0 install -y --no-install-recommends \
    libxml2 \
    python3
ARG RUST_TARGET
COPY /test-base-target.sh /
RUN /test-base-target.sh
COPY /test /test

FROM test-base as test-relocated
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG NODE_VERSION
ENV EMSDK="/usr/local/${RUST_TARGET}"
ENV EM_CACHE="${EMSDK}/upstream/emscripten/cache"
ENV EMSDK_NODE="${EMSDK}/node/${NODE_VERSION}_64bit/bin/node"
ENV PATH="${EMSDK}:${EMSDK}/upstream/emscripten:${EMSDK}/node/${NODE_VERSION}_64bit/bin:$PATH"
# NOTE: `/"${RUST_TARGET}"/. /usr/local/` doesn't work
COPY --from=builder /"${RUST_TARGET}" /usr/local/"${RUST_TARGET}"
RUN /test/test.sh emcc
RUN touch /DONE

FROM test-base as test
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
ARG NODE_VERSION
ENV EMSDK="/${RUST_TARGET}"
ENV EM_CACHE="${EMSDK}/upstream/emscripten/cache"
ENV EMSDK_NODE="${EMSDK}/node/${NODE_VERSION}_64bit/bin/node"
ENV PATH="${EMSDK}:${EMSDK}/upstream/emscripten:${EMSDK}/node/${NODE_VERSION}_64bit/bin:$PATH"
COPY --from=builder /"${RUST_TARGET}" /"${RUST_TARGET}"
RUN /test/check.sh
RUN /test/test.sh emcc
RUN node --version
COPY --from=test-relocated /DONE /

FROM ubuntu:"${UBUNTU_VERSION}" as final
SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TARGET
COPY --from=test /"${RUST_TARGET}" /"${RUST_TARGET}"
COPY --from=test /"${RUST_TARGET}-dev" /"${RUST_TARGET}-dev"
ARG NODE_VERSION
ENV EMSDK="/${RUST_TARGET}"
ENV EM_CACHE="${EMSDK}/upstream/emscripten/cache"
ENV EMSDK_NODE="${EMSDK}/node/${NODE_VERSION}_64bit/bin/node"
ENV PATH="${EMSDK}:${EMSDK}/upstream/emscripten:${EMSDK}/node/${NODE_VERSION}_64bit/bin:$PATH"
ENV PATH="/${RUST_TARGET}-dev/bin:$PATH"
