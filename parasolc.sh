#!/usr/bin/env bash
set -euo pipefail

script_dir="$(dirname "$0")"

SOLC_BINARY="${SOLC_BINARY:-"${script_dir}/solc"}"
SPLIT_METHOD="${SPLIT_METHOD:-naive}"
ONLY_RELEVANT_SOURCES="${ONLY_RELEVANT_SOURCES:-false}"

source "${script_dir}/standard-json-utils.sh"

# Validates input and command line, filling $INPUT and $SOLC_ARGS
source "${script_dir}/input-validation.sh"

tmp_dir=$(mktemp -d -t parasolc-XXXXXX)
echo "$INPUT" > "${tmp_dir}/input.json"

function strip_irrelevant_sources_if_requested {
    if [[ $ONLY_RELEVANT_SOURCES == true ]]; then
        drop_unselected_sources
    elif [[ $ONLY_RELEVANT_SOURCES == false ]]; then
        cat
    else
        fail "Non-boolean value for ONLY_RELEVANT_SOURCES: ${ONLY_RELEVANT_SOURCES}"
    fi
}

# Modify original input to request metadata output only and compile that.
# This is quick and gives us the full list of contracts, including those pulled in via imports.
select_analysis_outputs < "${tmp_dir}/input.json" \
    | "$SOLC_BINARY" "${SOLC_ARGS[@]}" \
    | jq --indent 4 \
    > "${tmp_dir}/analysis-output.json"

# TODO: Detect missing compilationHints in the output. The compiler does not fail on invalid
# outputs, making the behavior confusing if someone tries an older compiler that does not has this output.
if has_compilation_errors < "${tmp_dir}/analysis-output.json"; then
    cat "${tmp_dir}/analysis-output.json"
    exit 0
fi

if [[ $SPLIT_METHOD == clustered ]]; then
    for cluster_id in $(contracts_in_output < "${tmp_dir}/analysis-output.json" | cluster_ids); do
        select_contracts \
            <(contracts_in_output < "${tmp_dir}/analysis-output.json" | select_cluster "$cluster_id") \
            < "${tmp_dir}/input.json" \
            | strip_irrelevant_sources_if_requested \
            > "${tmp_dir}/partial-input-${cluster_id}.json"
    done
elif [[ $SPLIT_METHOD == naive ]]; then
    i=0
    contracts_in_output < "${tmp_dir}/analysis-output.json" | while IFS= read -r selected_contract_json; do
        select_contract "$selected_contract_json" \
            < "${tmp_dir}/input.json" \
            | strip_irrelevant_sources_if_requested \
            > "${tmp_dir}/partial-input-${i}.json"
        ((++i))
    done
else
    fail "Unknown split method: ${SPLIT_METHOD}"
fi

# Modify original input again, this time to get a full set of inputs, each for a single contract.
# Use xargs to run solc on each of the new inputs in parallel.
# TODO: Use same numbers for input and corresponding output.
subprocess_script="
    pid=\$\$
    '$SOLC_BINARY' ${SOLC_ARGS[*]} < '{}' \
        | jq --indent 4 \
        >> '${tmp_dir}'/partial-output-\${pid}.json
"
find "${tmp_dir}" -name 'partial-input-*.json' \
    | xargs --max-procs=0 --delimiter=$'\n' -I {} bash -c "$subprocess_script"

# Combine the .contracts from each output file. These should not overlap.
cat "${tmp_dir}"/partial-output-*.json \
    | merge_output \
    | tee "${tmp_dir}/combined-output.json"

rm -r "$tmp_dir"
