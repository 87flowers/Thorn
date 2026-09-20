.RECIPEPREFIX = >
SUFFIX :=

ZIG_PATH := $(shell ./scripts/download_zig.sh "zig-x86_64-linux-0.17.0-dev.2234+80fe9b2b7" "2f2397ec1465e4260822ab00b3fb9bc78bb1a9bff564260cbf472158f5a04a15")

EXE ?= thorn

all: test
> $(ZIG_PATH)/zig build --release=fast
> mv ./zig-out/bin/thorn $(EXE)

clean:
> rm -r ./.zig-cache ./zig-out

test:
> $(ZIG_PATH)/zig build test

bench: test
> $(ZIG_PATH)/zig build run --release=safe -- bench

.PHONY: all clean test bench
