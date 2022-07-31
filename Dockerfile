FROM golang:1.18

## --------------------------------------
## Authorship
## --------------------------------------

LABEL org.opencontainers.image.authors="sakutz@gmail.com"


## --------------------------------------
## Multi-platform support
## --------------------------------------

ARG TARGETOS
ARG TARGETARCH


## --------------------------------------
## Apt and standard packages
## --------------------------------------

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
    curl jq openssl jq iproute2 iputils-ping tar vim


## --------------------------------------
## Install the docker client
## --------------------------------------

RUN mkdir -p /etc/apt/keyrings && \
    chmod -R 0755 /etc/apt/keyrings && \
    curl -fsSL "https://download.docker.com/linux/debian/gpg" | \
      gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=${TARGETARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/debian \
      $(grep VERSION_CODENAME /etc/os-release | \
      awk -F= '{print $2}') stable" \
      >/etc/apt/sources.list.d/docker.list && \
    apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker-ce-cli


## --------------------------------------
## Install yq since there's no apt pkg
## --------------------------------------

RUN curl -Lo /usr/bin/yq \
    "https://github.com/mikefarah/yq/releases/download/v4.26.1/yq_linux_${TARGETARCH}" && \
    chmod 0755 /usr/bin/yq


## --------------------------------------
## Install kubectl
## --------------------------------------

RUN curl -Lo /usr/bin/kubectl \
  "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${TARGETARCH}/kubectl" && \
  chmod 0755 /usr/bin/kubectl


## --------------------------------------
## Install kind
## --------------------------------------

RUN curl -Lo /usr/bin/kind \
  "https://github.com/kubernetes-sigs/kind/releases/download/v0.14.0/kind-linux-${TARGETARCH}" && \
  chmod 0755 /usr/bin/kind


## --------------------------------------
## Copy in the local project
## --------------------------------------

RUN mkdir /pucr
WORKDIR /pucr
COPY . .


## --------------------------------------
## Build the conversion webhook server
## --------------------------------------

RUN make server


## --------------------------------------
## Enter into a shell
## --------------------------------------

ENV DOCKER_IN_DOCKER=1
ENTRYPOINT ["/bin/bash"]
