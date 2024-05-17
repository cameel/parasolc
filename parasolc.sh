#!/usr/bin/env bash
set -euo pipefail

script_dir="$(dirname "$0")"

# Use global `solc` by default, but let user specify a different binary by overriding the variable.
SOLC_BINARY="${SOLC_BINARY:-solc}"

source "${script_dir}/standard-json-utils.sh"

# Validates input and command line, filling $INPUT and $SOLC_ARGS
source "${script_dir}/input-validation.sh"

tmp_dir=$(mktemp -d -t parasolc-XXXXXX)
echo "$INPUT" > "${tmp_dir}/input.json"

# Modify original input to request metadata output only and compile that.
# This is quick and gives us the full list of contracts, including those pulled in via imports.
select_metadata_only < "${tmp_dir}/input.json" \
    | "$SOLC_BINARY" "${SOLC_ARGS[@]}" \
    | jq --indent 4 \
    > "${tmp_dir}/analysis-output.json"

if has_compilation_errors < "${tmp_dir}/analysis-output.json"; then
    cat "${tmp_dir}/analysis-output.json"
    exit 0
fi

# Modify original input again, this time to get a full set of inputs, each for a single contract.
# Use xargs to run solc on each of the new inputs in parallel.
export -f select_contract
subprocess_script="
    pid=\$\$
    select_contract '{}' < '${tmp_dir}/input.json' \
        | '$SOLC_BINARY' ${SOLC_ARGS[*]} \
        | jq --indent 4 \
        >> '${tmp_dir}'/partial-output-\${pid}.json
"
contracts_in_output < "${tmp_dir}/analysis-output.json" \
    | xargs --max-procs=0 --delimiter=$'\n' -I {} bash -c "$subprocess_script"

# Combine the .contracts from each output file. These should not overlap.
cat "${tmp_dir}"/partial-output-*.json \
    | merge_output \
    | tee "${tmp_dir}/combined-output.json"

rm -r "$tmp_dir"
