# Execute whole rules in one shell invocation (instead a separete shell for every line) and fail on first error
.ONESHELL:
.SHELLFLAGS += -euo pipefail

SOLC_BINARY ?= solc

.PHONY: all benchmark clean

all: benchmark

contracts/: test/setup.sh
	test/setup.sh

benchmark: contracts/ test/benchmark.sh
	SOLC_BINARY="$(SOLC_BINARY)" SPLIT_METHOD=naive     test/benchmark.sh
	SOLC_BINARY="$(SOLC_BINARY)" SPLIT_METHOD=clustered test/benchmark.sh

solc: compilation-hints-output-with-bytecode-dependency-clusters.patch
	git clone https://github.com/ethereum/solidity --branch "v0.8.26" --depth 1
	cd solidity/
	git apply --verbose ../compilation-hints-output-with-bytecode-dependency-clusters.patch

	export CMAKE_OPTIONS="-DUSE_Z3=OFF -DUSE_CVC4=OFF -DSOLC_STATIC_STDLIBS=ON"
	scripts/ci/build.sh parasolc
	strip build/solc/solc

	mv build/solc/solc ../
	chmod +x ../solc

clean:
	rm -rf solidity/ results/ contracts/
