#!/usr/bin/env bash
set -euo pipefail

script_dir="$(dirname "$0")"
PARASOLC_OUTPUT_DIR=${PARASOLC_OUTPUT_DIR:-"${script_dir}/.."}

rm -rf "${PARASOLC_OUTPUT_DIR}/contracts/"
mkdir -p "${PARASOLC_OUTPUT_DIR}/contracts/"
cd "${PARASOLC_OUTPUT_DIR}/contracts/"

git clone --depth=1 https://github.com/OpenZeppelin/openzeppelin-contracts --branch v5.0.2
cd openzeppelin-contracts/
forge install
cd ..

git clone https://github.com/Uniswap/v4-core
cd v4-core/
git checkout d0700ceb251afa48df8cc26d593fe04ee5e6b775 # branch main as of 2024-05-10
forge install
cd ..
