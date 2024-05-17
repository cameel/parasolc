#!/usr/bin/env bash
set -euo pipefail

# Use global `solc` by default, but let user specify a different binary by overriding the variable.
SOLC_BINARY="${SOLC_BINARY:-solc}"

# HELPERS

function fail { >&2 echo ERROR: "$@"; exit 1; }

function select_metadata_only {
    jq --indent 4 '.settings.outputSelection = {"*": {"*": ["metadata"]}}'
}

function has_compilation_errors {
    [[ $(jq --raw-output '
        has("errors")
        and ([.errors[] | select(.severity == "error")] | length) > 0
    ') == true ]]
}

function contracts_in_output {
    jq --compact-output '
        [.contracts | paths | select(length == 2)]
        | map({source: .[0], contract: .[1]})[]
    '
}

function selected_outputs_in_input {
    jq --compact-output '.settings.outputSelection | paths | select(length == 2)'
}

function select_contract {
    local source_and_contract_name_json="$1"

    # ASSUMPTION: The input has all sources and contracts selected (*.*).
    # ASSUMPTION: There are no sources named literally `*`.
    jq \
        --indent 4 \
        --argjson selected "$source_and_contract_name_json" '
            .settings.outputSelection.[$selected.source] = .settings.outputSelection."*"
            | .settings.outputSelection.[$selected.source].[$selected.contract] = .settings.outputSelection.[$selected.source]."*"
            | del(.settings.outputSelection."*", .settings.outputSelection.[$selected.source]."*")
        '
}

function remove_null_keys {
    jq --indent 4 '[to_entries[] | select(.value != null)] | from_entries'
}

function merge_output {
    jq --slurp --indent 4 '{
        contracts: [.[].contracts // {} | to_entries] | add | group_by(.key) | map({
            (map(.key) | first): map(.value) | add
        }) | add,
        errors:  [.[].errors]  | add | (if . != null then unique else . end),
        sources: [.[].sources] | add
    }' | remove_null_keys
}

# INPUT VALIDATION

# The script supports only a small subset of solc's CLI:
# - No whitespace in arguments. Properly passing them to subprocesses complicates things.
# - Only Standard JSON and only with input on stdin. That's enough for forge.
# - All files and contracts must be selected for compilation (`*` in outputSelection). For simplicity.

solc_args=()
standard_json_requested=faise
while (( $# > 0 )); do
    [[ ! $1 =~ ' ' ]] || fail "Whitespace in arguments not supported."

    case "$1" in
        --base-path | --allow-paths)
            solc_args+=("$1")
            shift
            if (( $# > 0 )) && [[ ! $1 == -* ]]; then
                [[ ! $1 =~ ' ' ]] || fail "Whitespace in arguments not supported."
                solc_args+=("$1")
                shift
            fi
            ;;
        --standard-json)
            standard_json_requested=true ;&
        -)
            solc_args+=("$1")
            shift ;;
        -*) fail "Unsupported option: '${1}'" ;;
        *) fail "Input files and remappings not supported. All input must be passed via stdin." ;;
    esac
done

[[ $standard_json_requested == true ]] || fail "Only Standard JSON input mode is supported."

input=$(cat)
[[ $(echo "$input" | selected_outputs_in_input) == '["*","*"]' ]] || \
    fail "Only input with all files and contracts selected for compilation is supported."

[[ $(echo "$input" | jq --raw-output '.language') == "Solidity" ]] || \
    fail "Only Solidity input is supported."

# COMPILATION

tmp_dir=$(mktemp -d -t parasolc-XXXXXX)

echo "$input" > "${tmp_dir}/input.json"

# Modify original input to request metadata output only and compile that.
# This is quick and gives us the full list of contracts, including those pulled in via imports.
select_metadata_only < "${tmp_dir}/input.json" \
    | "$SOLC_BINARY" "${solc_args[@]}" \
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
        | '$SOLC_BINARY' ${solc_args[*]} \
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
