#!/usr/bin/env bash

load_dotenv_if_present() {
    local env_file="${1:-.env}"

    if [[ -f "$env_file" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "$env_file"
        set +a
    fi
}

require_env_vars() {
    local var_name
    for var_name in "$@"; do
        if [[ -z "${!var_name:-}" ]]; then
            echo "Error: ${var_name} is required" >&2
            return 1
        fi
    done
}

require_one_of() {
    local description="$1"
    shift

    local var_name
    for var_name in "$@"; do
        if [[ -n "${!var_name:-}" ]]; then
            return 0
        fi
    done

    echo "Error: set ${description}" >&2
    return 1
}

is_truthy() {
    case "${1:-}" in
        1|true|TRUE|True|yes|YES|on|ON)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

detect_rpc_client() {
    cast client --rpc-url "$RPC_URL" 2>/dev/null | tr '[:upper:]' '[:lower:]'
}

resolve_local_state_rpc_namespace() {
    if [[ -n "${LOCAL_STATE_RPC_NAMESPACE:-}" ]]; then
        case "$LOCAL_STATE_RPC_NAMESPACE" in
            anvil|hardhat)
                printf '%s\n' "$LOCAL_STATE_RPC_NAMESPACE"
                return 0
                ;;
            *)
                echo "Error: LOCAL_STATE_RPC_NAMESPACE must be 'anvil' or 'hardhat'" >&2
                return 1
                ;;
        esac
    fi

    local client
    client="$(detect_rpc_client)"

    if [[ "$client" == *anvil* ]]; then
        printf '%s\n' "anvil"
        return 0
    fi

    if [[ "$client" == *hardhat* ]]; then
        printf '%s\n' "hardhat"
        return 0
    fi

    echo "Error: could not detect a supported local RPC backend from \`cast client\` output: ${client:-<empty>}" >&2
    echo "Set LOCAL_STATE_RPC_NAMESPACE=anvil or LOCAL_STATE_RPC_NAMESPACE=hardhat explicitly." >&2
    return 1
}

resolve_forge_broadcast_pacing_flag() {
    if [[ -n "${FORGE_BROADCAST_PACING:-}" ]]; then
        case "$FORGE_BROADCAST_PACING" in
            slow)
                printf '%s\n' "--slow"
                return 0
                ;;
            fast)
                printf '%s\n' ""
                return 0
                ;;
            *)
                echo "Error: FORGE_BROADCAST_PACING must be 'slow' or 'fast'" >&2
                return 1
                ;;
        esac
    fi

    local client
    client="$(detect_rpc_client)"

    if [[ "$client" == *hardhat* ]]; then
        printf '%s\n' "--slow"
        return 0
    fi

    printf '%s\n' ""
}

resolve_signer_address() {
    local addr_var="$1"
    local pk_var="$2"

    if [[ -n "${!addr_var:-}" ]]; then
        printf '%s\n' "${!addr_var}"
        return 0
    fi

    cast wallet address --private-key "${!pk_var}" 2>/dev/null
}

to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

pad_address() {
    local address_value="${1#0x}"
    printf '0x%064s\n' "$address_value" | tr ' ' '0'
}
