# Execute whole rules in one shell invocation (instead a separete shell for every line) and fail on first error
.ONESHELL:
.SHELLFLAGS += -euo pipefail

MAKEFILE_DIR := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
OUTPUT_DIR ?= $(MAKEFILE_DIR)
SOLC_BINARY ?= $(OUTPUT_DIR)/solc

.PHONY: all benchmark clean

all: benchmark

$(OUTPUT_DIR)/contracts/: test/setup.sh
	test/setup.sh "$(OUTPUT_DIR)"

benchmark: $(OUTPUT_DIR)/contracts/ test/benchmark.sh
	test/benchmark.sh "$(SOLC_BINARY)" "$(OUTPUT_DIR)"

$(OUTPUT_DIR)/solidity/: compilation-hints-output-with-bytecode-dependency-clusters.patch
	cd "$(OUTPUT_DIR)"
	rm -rf solidity/
	git clone https://github.com/ethereum/solidity --branch "v0.8.26" --depth 1
	cd solidity/
	git apply --verbose ../compilation-hints-output-with-bytecode-dependency-clusters.patch

solc: $(OUTPUT_DIR)/solidity/
	cd "$(OUTPUT_DIR)/solidity/"
	export CMAKE_OPTIONS="-DUSE_Z3=OFF -DUSE_CVC4=OFF -DSOLC_STATIC_STDLIBS=ON"
	scripts/ci/build.sh parasolc
	strip build/solc/solc

	mv build/solc/solc ../
	chmod +x ../solc

clean:
	rm -rf "$(OUTPUT_DIR)/solidity/" "$(OUTPUT_DIR)/results/" "$(OUTPUT_DIR)/contracts/"
