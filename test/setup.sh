#!/usr/bin/env bash
set -euo pipefail

script_dir="$(dirname "$0")"

output_dir="${1:-"$script_dir/.."}"
(( $# <= 1 )) || fail "Usage: test/setup.sh [OUTPUT_DIR]"

rm -rf "${output_dir}/contracts/"
mkdir -p "${output_dir}/contracts/"
cd "${output_dir}/contracts/"

git clone --depth=1 https://github.com/OpenZeppelin/openzeppelin-contracts --branch v5.0.2
cd openzeppelin-contracts/
forge install
cd ..

git clone https://github.com/Uniswap/v4-core
cd v4-core/
git checkout d0700ceb251afa48df8cc26d593fe04ee5e6b775 # branch main as of 2024-05-10
forge install
cd ..

# NOTE: Intentionally using the old v1 release. It takes much longer to compile so it's better for benchmarking.
git clone --depth=1 https://github.com/ProjectOpenSea/seaport --branch 1
cd seaport/
forge config --fix
forge install
find . -name '*.sol' -type f -print0 | xargs -0 sed -i -E -e 's/pragma solidity [^;]+;/pragma solidity *;/'
cd ..
