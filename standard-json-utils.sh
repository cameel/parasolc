#!/usr/bin/env bash

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
