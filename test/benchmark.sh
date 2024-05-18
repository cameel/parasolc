#!/usr/bin/env bash
set -euo pipefail

export SOLC_BINARY="${SOLC_BINARY:-solc}"

script_dir="$(dirname "$0")"

function time_to_json_file
{
    local output_file="$1"
    local cmd=("${@:2}")

    # $TIMEFORMAT is the format used by built-in `time`. Description is in `man bash`.
    local original_timeformat="${TIMEFORMAT:-}"
    TIMEFORMAT='{"real": %R, "user": %U, "sys": %S}'

    # We temporarily use descriptors 3 and 4 to preserve stdout and stderr of the original command.
    # This allows us to store `time`'s own stderr in a file. Then we restore initial descriptors.
    {
        {
            time { "${cmd[@]}" 1>&3 2>&4; }
        } 2> "$output_file"
    } 3>&1 4>&2

    # Restore original format so that it does not spill outside of the function.
    TIMEFORMAT="$original_timeformat"
}

function execute_test {
    local test_name="$1"
    local project_subdir="$2"

    local project_dir="../contracts/${project_subdir}"
    local input_json="${project_dir}/${test_name}.json"
    cp "${test_name}.json" "$input_json"

    printf "%s" "${test_name}: solc"
    time_to_json_file \
        "../results/time-${test_name}-solc.json" \
        "$SOLC_BINARY" --standard-json - --base-path "$project_dir" \
            < "$input_json" \
            | jq --indent 4 --sort-keys \
            > "../results/${test_name}-solc-output.json"
    jq . "../results/time-${test_name}-solc.json"

    printf "%s" "${test_name}: parasolc"
    time_to_json_file \
        "../results/time-${test_name}-parasolc.json" \
        ../parasolc.sh --standard-json - --base-path "$project_dir" \
            < "$input_json" \
            | jq --indent 4 --sort-keys \
            > "../results/${test_name}-parasolc-output.json"
    jq . "../results/time-${test_name}-parasolc.json"

    diff --brief --report-identical-files \
        "../results/${test_name}-parasolc-output.json" \
        "../results/${test_name}-solc-output.json"
    echo
}

function forge_build {
    local solc_path="$1"
    local wrapper_path="$2"

    SOLC_BINARY="$solc_path" \
    forge build \
        --use "$wrapper_path" \
        --optimize \
        --via-ir \
        --evm-version cancun \
        --offline \
        --no-cache
}

function foundry_benchmark {
    local project_subdir="$1"

    local output_dir solc_path parasolc_path project_dir
    output_dir=$(realpath ../results/)
    # Use `command` to make it work with a system-wide `solc` binary as well.
    solc_path=$(realpath "$(command -v "$SOLC_BINARY")")
    parasolc_path=$(realpath ../parasolc.sh)
    project_dir="../contracts/${project_subdir}"

    pushd "${project_dir}" > /dev/null

    echo "${project_subdir}: foundry+solc"
    time_to_json_file "${output_dir}/time-${project_subdir}-foundry+solc.json" forge_build "$solc_path" "$solc_path"
    jq . "${output_dir}/time-${project_subdir}-foundry+solc.json"

    echo "${project_subdir}: foundry+parasolc"
    time_to_json_file "${output_dir}/time-${project_subdir}-foundry+parasolc.json" forge_build  "$solc_path" "$parasolc_path"
    jq . "${output_dir}/time-${project_subdir}-foundry+parasolc.json"

    popd > /dev/null
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

foundry_benchmark openzeppelin-contracts || true
foundry_benchmark v4-core                || true
