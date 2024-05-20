#!/usr/bin/env bash

function fail { >&2 echo ERROR: "$@"; exit 1; }

function select_analysis_outputs {
    # Always include 'metadata' so that we still get some output if the compiler does not support 'compilationHints'.
    jq --indent 4 '.settings.outputSelection = {"*": {"*": ["compilationHints", "metadata"]}}'
}

function has_compilation_errors {
    [[ $(jq --raw-output '
        has("errors")
        and ([.errors[] | select(.severity == "error")] | length) > 0
    ') == true ]]
}

function contracts_in_output {
    jq --compact-output '
        .contracts
        | to_entries
        | map({source: .key} + (.value | to_entries[]))
        | map({
            source: .source,
            contract: .key,
            cluster: .value.compilationHints.bytecodeDependencyCluster
        })[]
    '
}

function cluster_ids {
    jq '.cluster'
}

function select_cluster {
    local cluster_id="$1"

    jq --slurp --compact-output ".[] | select(.cluster == ${cluster_id})"
}

function selected_outputs_in_input {
    jq --compact-output '.settings.outputSelection | paths | select(length == 2)'
}

function select_contract {
    local source_and_contract_name_json="$1"

    select_contracts <(echo "$source_and_contract_name_json")
}

function drop_unselected_sources {
    jq --indent 4 '
        .sources = (
            .settings.outputSelection as $outputSelection
            | .sources
            | with_entries(select(.key | in($outputSelection)))
        )
    '
}

function select_contracts {
    local arg_file="$1"

    # ASSUMPTION: The input has all sources and contracts selected (*.*).
    # ASSUMPTION: There are no sources named literally `*`.
    output=$(cat)
    while IFS= read -r source_and_contract_name_json; do
        output=$(
            echo "$output" \
                | jq \
                    --argjson selected "$source_and_contract_name_json" \
                    '.settings.outputSelection.[$selected.source].[$selected.contract] = .settings.outputSelection."*"."*"'
        )
    done < "$arg_file"

    echo "$output" | jq --indent 4 'del(.settings.outputSelection."*")'
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
