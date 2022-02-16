ARG VERNEMQ_VERSION="1.12.3"

## build-env ##

FROM erlang:22-alpine AS build-env
ARG VERNEMQ_VERSION

SHELL ["/bin/sh", "-euxo", "pipefail", "-c"]

WORKDIR /vernemq-build

# https://pkgs.alpinelinux.org/packages
RUN apk --no-cache --update --available upgrade && \
    apk add --no-cache \
        git bash curl wget jq ca-certificates \
        build-base autoconf cmake openssl-dev \
        bsd-compat-headers ncurses-libs libstdc++ snappy-dev \
    && \
    git clone -b $VERNEMQ_VERSION https://github.com/vernemq/vernemq.git .
	
RUN wget https://github.com/vernemq/docker-vernemq/raw/$VERNEMQ_VERSION/bin/build.sh -O build.sh && \
    wget https://github.com/vernemq/docker-vernemq/raw/$VERNEMQ_VERSION/bin/vernemq.sh -O vernemq.sh && \
    wget https://github.com/vernemq/docker-vernemq/raw/$VERNEMQ_VERSION/files/vm.args -O vm.args && \
    chmod +x build.sh && \
    chmod +x vernemq.sh

RUN sed -i '/else/i elif [ "$1" = "rpi32" ]; then\n    make rpi32 \n    mv _build\/rpi32\/rel\/vernemq release' build.sh

RUN ARCH=`uname -m` && \
    echo "ARCH=$ARCH" && \
    if [[ $ARCH == "arm"* ]]; then \
        TARGET="rpi32" ; \
    elif [ "$ARCH" == "x86_64" ]; then \
        TARGET="rel" ; \
    else \
        echo "This architecture is (unfortunately) not supported!" && \
        exit 1 ; \
    fi && \
    echo "TARGET=$TARGET" && \
    \
    ./build.sh $TARGET

## Image ##

FROM alpine:3.13

RUN apk --no-cache --update --available upgrade && \
    apk add --no-cache ncurses-libs openssl libstdc++ jq curl bash snappy-dev && \
    addgroup --gid 10000 vernemq && \
    adduser --uid 10000 -H -D -G vernemq -h /vernemq vernemq && \
    install -d -o vernemq -g vernemq /vernemq

# Defaults
ENV DOCKER_VERNEMQ_KUBERNETES_LABEL_SELECTOR="app=vernemq" \
    DOCKER_VERNEMQ_LOG__CONSOLE=console \
    PATH="/vernemq/bin:$PATH"
	
WORKDIR /vernemq

COPY --chown=10000:10000 --from=build-env /vernemq-build/vernemq.sh /usr/sbin/start_vernemq
COPY --chown=10000:10000 --from=build-env /vernemq-build/vm.args /vernemq/etc/vm.args
COPY --chown=10000:10000 --from=build-env /vernemq-build/release /vernemq

RUN \
    ln -s /vernemq/etc /etc/vernemq && \
    ln -s /vernemq/data /var/lib/vernemq && \
    ln -s /vernemq/log /var/log/vernemq

# Ports
# 1883  MQTT
# 8883  MQTT/SSL
# 8080  MQTT WebSockets
# 44053 VerneMQ Message Distribution
# 4369  EPMD - Erlang Port Mapper Daemon
# 8888  Prometheus Metrics
# 9100 9101 9102 9103 9104 9105 9106 9107 9108 9109  Specific Distributed Erlang Port Range

EXPOSE 1883 8883 8080 44053 4369 8888 \
       9100 9101 9102 9103 9104 9105 9106 9107 9108 9109


VOLUME ["/vernemq/log", "/vernemq/data", "/vernemq/etc"]

HEALTHCHECK CMD vernemq ping | grep -q pong

USER vernemq
CMD ["start_vernemq"]
