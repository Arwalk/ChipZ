VERSION 0.6
FROM ubuntu:20.04

ARG ZIG_VERSION=0.9.1
RUN apt-get update && apt-get install wget -y

env-linux:
    ENV TZ=Europe/Paris
    RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezon
    RUN apt-get install -y libsdl2-dev tar xz-utils build-essential
    WORKDIR /zig
    RUN wget "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-$(uname -p)-${ZIG_VERSION}.tar.xz"
    RUN tar -xf zig-linux-$(uname -p)-${ZIG_VERSION}.tar.xz
    RUN chmod +x zig-linux-$(uname -p)-${ZIG_VERSION}/zig
    RUN ln -s /zig/zig-linux-$(uname -p)-${ZIG_VERSION}/zig /bin/zig
    RUN ln -s /usr/lib/$(uname -p)-linux-gnu/libSDL2.so /usr/lib/libSDL2.so
    WORKDIR /src
    COPY --dir demo_files /src/
    COPY --dir src /src/
    COPY --dir tests /src/
    COPY build.zig /src/build.zig

build-test-linux:
    FROM +env-linux
    RUN zig build test

build-bin-linux:
    FROM +env-linux
    RUN zig build
    SAVE ARTIFACT zig-output/chipz

build-linux:
    BUILD +build-test-linux
    BUILD +build-bin-linux
    SAVE ARTIFACT +build-bin-linux/chipz