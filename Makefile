# Execute whole rules in one shell invocation (instead a separete shell for every line) and fail on first error
.ONESHELL:
.SHELLFLAGS += -euo pipefail

SOLC_BINARY ?= solc

.PHONY: all benchmark clean

all: benchmark

contracts/: test/setup.sh
	test/setup.sh

benchmark: contracts/ test/benchmark.sh
	SOLC_BINARY="$(SOLC_BINARY)" test/benchmark.sh

clean:
	rm -rf results/ contracts/
