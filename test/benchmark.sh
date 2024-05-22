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
