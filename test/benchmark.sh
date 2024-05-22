#!/usr/bin/env bash
set -euo pipefail

script_dir="$(dirname "$0")"
cd "$script_dir"

source ../standard-json-utils.sh

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
    echo "| Test                             | JSON | bytecode | solc real time | parasolc real time | solc CPU total | parasolc CPU total | solc CPU sys | parasolc CPU sys |"
    echo "|----------------------------------|-----:|---------:|---------------:|-------------------:|---------------:|-------------------:|-------------:|-----------------:|"
}

function compare_and_report_results {
    local test_name="$1"
    local solc_time_json="$2"
    local parasolc_time_json="$3"
    local solc_json="${4:-}"
    local parasolc_json="${5:-}"

    local json_match='❓' bytecode_match='❓'
    if [[ $solc_json != "" && $parasolc_json != "" ]]; then
        cmp --quiet "$solc_json" "$parasolc_json" && json_match=✅ || json_match=❌
        cmp --quiet \
            <(bytecode_in_output < "$solc_json") \
            <(bytecode_in_output < "$parasolc_json") \
            && bytecode_match=✅ || bytecode_match=❌
    fi

    printf '| %-32s | %5s | %9s | %12s s | %16s s | %12s s | %16s s | %10s s | %14s s |\n' \
        "$test_name" \
        "$json_match" \
        "$bytecode_match" \
        "$(jq '.real | round'      "$solc_time_json")" \
        "$(jq '.real | round'      "$parasolc_time_json")" \
        "$(jq '.user+.sys | round' "$solc_time_json")" \
        "$(jq '.user+.sys | round' "$parasolc_time_json")" \
        "$(jq '.sys | round'       "$solc_time_json")" \
        "$(jq '.sys | round'       "$parasolc_time_json")"
}

function compile_standard_json {
    local compiler="$1"
    local test_name="$2"
    local project_dir="$3"
    local json_output_path="$4"
    local time_output_path="$5"

    local input_json="${project_dir}/${test_name}.json"

    { [[ $compiler == solc ]] && local compiler_path="$SOLC_BINARY"; } || \
        { [[ $compiler == parasolc ]] && local compiler_path=../parasolc.sh; }

    cp "${test_name}.json" "$input_json"
    printf "%s" "${test_name}: ${compiler} | "
    time_to_json_file \
        "$time_output_path" \
        "$compiler_path" --standard-json - --base-path "$project_dir" \
            < "$input_json" \
            | jq --indent 4 --sort-keys \
            > "$json_output_path"
    cat "$time_output_path"
}

function compiler_benchmark {
    local test_name="$1"
    local project_subdir="$2"

    local project_dir="${PARASOLC_OUTPUT_DIR}/contracts/${project_subdir}"
    local output_prefix="${PARASOLC_OUTPUT_DIR}/results/${test_name}"

    compile_standard_json solc     "$test_name" "$project_dir" "${output_prefix}-solc.json"     "${output_prefix}-solc-time.json"
    compile_standard_json parasolc "$test_name" "$project_dir" "${output_prefix}-parasolc.json" "${output_prefix}-parasolc-time.json"
    compare_and_report_results \
        "$test_name" \
        "${output_prefix}-solc-time.json" "${output_prefix}-parasolc-time.json" \
        "${output_prefix}-solc.json"      "${output_prefix}-parasolc.json" \
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

function compile_with_foundry {
    local compiler="$1"
    local test_name="$2"
    local project_dir="$3"
    local time_output_path="$4"

    local solc_path compiler_path
    # Use `command` to make it work with a system-wide `solc` binary as well.
    solc_path=$(realpath "$(command -v "$SOLC_BINARY")")
    { [[ $compiler == solc ]] && compiler_path="$solc_path"; } || \
        { [[ $compiler == parasolc ]] && compiler_path=$(realpath ../parasolc.sh); }

    pushd "${project_dir}" > /dev/null

    echo "${test_name}: solc"
    time_to_json_file "$time_output_path" \
        forge_build "$solc_path" "$compiler_path"
    cat "$time_output_path"

    popd > /dev/null
}

function foundry_benchmark {
    local test_name="$1"
    local project_subdir="$2"

    local output_prefix="${PARASOLC_OUTPUT_DIR}/results/${test_name}"
    local project_dir="${PARASOLC_OUTPUT_DIR}/contracts/${project_subdir}"

    compile_with_foundry solc     "$test_name" "$project_dir" "${output_prefix}-solc-time.json"
    compile_with_foundry parasolc "$test_name" "$project_dir" "${output_prefix}-parasolc-time.json"
    compare_and_report_results \
        "${test_name}" \
        "${output_prefix}-solc-time.json" \
        "${output_prefix}-parasolc-time.json" \
        >> "$report_file"
}

rm -rf "${PARASOLC_OUTPUT_DIR}/results/"
mkdir -p "${PARASOLC_OUTPUT_DIR}/results/"

report_file="${PARASOLC_OUTPUT_DIR}/results/report.md"

report_header > "$report_file"

# Ignore failing diff. We want to see all benchmarks, even if they fail.
# And failures are currently expected due to limitations of the script.

compiler_benchmark oz-erc20 openzeppelin-contracts
compiler_benchmark oz       openzeppelin-contracts

compiler_benchmark uniswap-pool-manager  v4-core
compiler_benchmark uniswap-big-contracts v4-core
compiler_benchmark uniswap               v4-core

foundry_benchmark oz+foundry      openzeppelin-contracts
foundry_benchmark uniswap+foundry v4-core || true # Error (2449): Definition of base has to precede definition of derived contract

cat "$report_file"
