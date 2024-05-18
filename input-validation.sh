#!/usr/bin/env bash

# parasolc supports only a small subset of solc's CLI:
# - No whitespace in arguments. Properly passing them to subprocesses complicates things.
# - Only Standard JSON and only with input on stdin. That's enough for forge.
# - All files and contracts must be selected for compilation (`*` in outputSelection). For simplicity.

SOLC_ARGS=()
INPUT=$(cat)

if [[ $* == --version ]]; then
    "${SOLC_BINARY}" --version
    exit 0
fi

standard_json_requested=faise
while (( $# > 0 )); do
    [[ ! $1 =~ ' ' ]] || fail "Whitespace in arguments not supported."

    case "$1" in
        --base-path | --allow-paths)
            SOLC_ARGS+=("$1")
            shift
            if (( $# > 0 )) && [[ ! $1 == -* ]]; then
                [[ ! $1 =~ ' ' ]] || fail "Whitespace in arguments not supported."
                SOLC_ARGS+=("$1")
                shift
            fi
            ;;
        --standard-json)
            standard_json_requested=true ;&
        -)
            SOLC_ARGS+=("$1")
            shift ;;
        -*) fail "Unsupported option: '${1}'" ;;
        *) fail "Input files and remappings not supported. All input must be passed via stdin." ;;
    esac
done

[[ $standard_json_requested == true ]] || fail "Only Standard JSON input mode is supported."
unset standard_json_requested

[[ $(echo "$INPUT" | selected_outputs_in_input) == '["*","*"]' ]] || \
    fail "Only input with all files and contracts selected for compilation is supported."

[[ $(echo "$INPUT" | jq --raw-output '.language') == "Solidity" ]] || \
    fail "Only Solidity input is supported."
