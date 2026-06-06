FROM mcr.microsoft.com/devcontainers/python:3.13-bookworm

ARG DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      bats \
      ca-certificates \
      coreutils \
      curl \
      findutils \
      git \
      jq \
      less \
      make \
      perl \
      procps \
      shellcheck \
      shfmt \
      unzip \
    && rm -rf /var/lib/apt/lists/*

COPY .devcontainer/bin/qlmanage /usr/bin/qlmanage
RUN chmod 0755 /usr/bin/qlmanage
