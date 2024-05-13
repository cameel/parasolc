#!/usr/bin/env bash
set -euo pipefail

export SOLC_BINARY="${SOLC_BINARY:-solc}"

script_dir="$(dirname "$0")"

function execute_test {
    local test_name="$1"
    local project_subdir="$2"

    local project_dir="../contracts/${project_subdir}"
    local input_json="${project_dir}/${test_name}.json"
    cp "${test_name}.json" "$input_json"

    printf "%s" "${test_name}: solc"
    time \
        "$SOLC_BINARY" --standard-json - --base-path "$project_dir" \
            < "$input_json" \
            | jq --indent 4 --sort-keys \
            > "../results/${test_name}-solc-output.json"

    printf "%s" "${test_name}: parasolc"
    time \
        ../parasolc.sh --standard-json - --base-path "$project_dir" \
            < "$input_json" \
            | jq --indent 4 --sort-keys \
            > "../results/${test_name}-parasolc-output.json"

    diff --brief --report-identical-files \
        "../results/${test_name}-parasolc-output.json" \
        "../results/${test_name}-solc-output.json"
    echo
}

cd "$script_dir"
rm -rf ../results/
mkdir -p ../results/

# Ignore failing diff. We want to see all benchmarks, even if they fail.
# And failures are currently expected due to limitations of the script.

execute_test oz-erc20 openzeppelin-contracts || true
execute_test oz       openzeppelin-contracts || true

execute_test uniswap-pool-manager  v4-core || true
execute_test uniswap-big-contracts v4-core || true
execute_test uniswap               v4-core || true
