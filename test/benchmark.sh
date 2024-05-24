#!/usr/bin/env bash
set -euo pipefail

script_dir="$(dirname "$0")"
cd "$script_dir"

PARASOLC_OUTPUT_DIR="${PARASOLC_OUTPUT_DIR:-..}"
export SOLC_BINARY="${SOLC_BINARY:-"${PARASOLC_OUTPUT_DIR}/solc"}"
export SPLIT_METHOD="${SPLIT_METHOD:-naive}"
export ONLY_RELEVANT_SOURCES="${ONLY_RELEVANT_SOURCES:-false}"

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

function report_header {
    echo "| Test                             | JSON | solc real time | parasolc real time | solc CPU total | parasolc CPU total | solc CPU sys | parasolc CPU sys |"
    echo "|----------------------------------|-----:|---------------:|-------------------:|---------------:|-------------------:|-------------:|-----------------:|"
}

function compare_and_report_results {
    local test_name="$1"
    local solc_time_json="$2"
    local parasolc_time_json="$3"
    local solc_json="${4:-}"
    local parasolc_json="${5:-}"

    local json_match='❓'
    if [[ $solc_json != "" && $parasolc_json != "" ]]; then
        cmp --quiet "$solc_json" "$parasolc_json" && json_match=✅ || json_match=❌
    fi

    printf '| %-32s | %5s | %12s s | %16s s | %12s s | %16s s | %10s s | %14s s |\n' \
        "$test_name" \
        "$json_match" \
        "$(jq '.real | round'      "$solc_time_json")" \
        "$(jq '.real | round'      "$parasolc_time_json")" \
        "$(jq '.user+.sys | round' "$solc_time_json")" \
        "$(jq '.user+.sys | round' "$parasolc_time_json")" \
        "$(jq '.sys | round'       "$solc_time_json")" \
        "$(jq '.sys | round'       "$parasolc_time_json")"
}

function execute_test {
    local test_name="$1"
    local project_subdir="$2"

    local project_dir="${PARASOLC_OUTPUT_DIR}/contracts/${project_subdir}"
    local input_json="${project_dir}/${test_name}.json"
    cp "${test_name}.json" "$input_json"

    printf "%s" "${test_name}: solc     | "
    local output_json_solc="${PARASOLC_OUTPUT_DIR}/results/${test_name}-solc.json"
    local output_time_solc="${PARASOLC_OUTPUT_DIR}/results/time-${test_name}-solc.json"
    time_to_json_file \
        "$output_time_solc" \
        "$SOLC_BINARY" --standard-json - --base-path "$project_dir" \
            < "$input_json" \
            | jq --indent 4 --sort-keys \
            > "$output_json_solc"
    cat "$output_time_solc"

    printf "%s" "${test_name}: parasolc | "
    local output_json_parasolc="${PARASOLC_OUTPUT_DIR}/results/${test_name}-parasolc.json"
    local output_time_parasolc="${PARASOLC_OUTPUT_DIR}/results/time-${test_name}-parasolc.json"
    time_to_json_file \
        "$output_time_parasolc" \
        ../parasolc.sh --standard-json - --base-path "$project_dir" \
            < "$input_json" \
            | jq --indent 4 --sort-keys \
            > "$output_json_parasolc"
    cat "$output_time_solc"

    compare_and_report_results \
        "$test_name" \
        "$output_time_solc" "$output_time_parasolc" \
        "$output_json_solc" "$output_json_parasolc" \
        >> "$report_file"
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
    output_dir=$(realpath "${PARASOLC_OUTPUT_DIR}/results/")
    # Use `command` to make it work with a system-wide `solc` binary as well.
    solc_path=$(realpath "$(command -v "$SOLC_BINARY")")
    parasolc_path=$(realpath ../parasolc.sh)
    project_dir="${PARASOLC_OUTPUT_DIR}/contracts/${project_subdir}"

    pushd "${project_dir}" > /dev/null

    echo "${project_subdir}: foundry+solc"
    local output_time_solc="${output_dir}/time-${project_subdir}-foundry+solc.json"
    time_to_json_file "$output_time_solc" forge_build "$solc_path" "$solc_path"
    cat "$output_time_solc"

    echo "${project_subdir}: foundry+parasolc"
    local output_time_parasolc="${output_dir}/time-${project_subdir}-foundry+parasolc.json"
    time_to_json_file "$output_time_parasolc" forge_build  "$solc_path" "$parasolc_path"
    cat "$output_time_parasolc"

    popd > /dev/null

    compare_and_report_results \
        "${project_subdir} + foundry" \
        "$output_time_solc" "$output_time_parasolc" \
        >> "$report_file"
}

rm -rf "${PARASOLC_OUTPUT_DIR}/results/"
mkdir -p "${PARASOLC_OUTPUT_DIR}/results/"

report_file="${PARASOLC_OUTPUT_DIR}/results/report.md"

report_header > "$report_file"

# Ignore failing diff. We want to see all benchmarks, even if they fail.
# And failures are currently expected due to limitations of the script.

execute_test oz-erc20 openzeppelin-contracts
execute_test oz       openzeppelin-contracts

execute_test uniswap-pool-manager  v4-core
execute_test uniswap-big-contracts v4-core
execute_test uniswap               v4-core

foundry_benchmark openzeppelin-contracts
foundry_benchmark v4-core

cat "$report_file"
