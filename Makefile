.RECIPEPREFIX = >
SUFFIX :=

ZIG_PATH := $(shell /usr/bin/env bash ./scripts/download_zig.sh "zig-x86_64-linux-0.17.0" "1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026")

EXE ?= thorn

all:
> $(ZIG_PATH)/zig build --release=fast
> mv ./zig-out/bin/thorn $(EXE)

clean:
> rm -r ./.zig-cache ./zig-out

test:
> $(ZIG_PATH)/zig build --release=safe test

bench:
> $(ZIG_PATH)/zig build run --release=safe -- bench

.PHONY: all clean test bench
