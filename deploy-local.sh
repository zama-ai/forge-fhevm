#!/usr/bin/env bash
# =============================================================================
# deploy-local.sh — Fixed-address local FHEVM host deployment
#
# Local deploy is a two-phase workflow:
#   1. Ensure the local artifacts exist for the committed local addresses.
#   2. Materialize those artifacts onto one or more local RPC nodes.
#
# Because the committed addresses already match the canonical local deployment,
# this script never rewrites FHEVMHostAddresses.sol and never runs forge clean.
# A normal forge build is enough to prepare or refresh artifacts when sources
# changed.
#
# Zero-config for local dev: all env vars have hardcoded defaults matching
# the canonical local addresses and mock gateway/signer values.
# Override any var from the calling shell if needed (no .env is loaded).
#
# See --help for CLI flags (--rpc-url, --anvil-port, --skip-build, -v).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source "$SCRIPT_DIR/script/lib/deploy-common.sh"

print_usage() {
    cat <<'EOF'
Usage: ./deploy-local.sh [options]

Deploy the fixed-address local FHEVM stack to one or more local RPC nodes.

Options:
  --rpc-url <url>             Target RPC URL. Repeat to deploy to multiple nodes.
  --anvil-port <port>         Shorthand for http://127.0.0.1:<port>. Repeatable.
  --skip-build                Reuse existing artifacts without running forge build.
  -v, --verbose               Print progress logs.
  -h, --help                  Show this help text.

Notes:
  - If no target is provided, the script uses RPC_URL, then ANVIL_PORT, then 8545.
  - Local deployments use fixed mock gateway and signer defaults, so no .env is required.
  - A single invocation builds once, then deploys to every target in parallel.
EOF
}

log() {
    if is_truthy "${VERBOSE:-0}"; then
        printf '%s\n' "$@"
    fi
}

run_with_captured_output() {
    if is_truthy "${VERBOSE:-0}"; then
        "$@"
        return
    fi

    local output
    if ! output="$("$@" 2>&1)"; then
        printf '%s\n' "$output" >&2
        return 1
    fi
}

require_arg_value() {
    local option_name="$1"
    local option_value="${2:-}"

    if [[ -z "$option_value" || "$option_value" == -* ]]; then
        echo "Error: ${option_name} requires a value" >&2
        exit 1
    fi
}

declare -a TARGET_RPC_URLS=()
SKIP_BUILD="${SKIP_BUILD:-0}"
VERBOSE="${VERBOSE:-0}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rpc-url)
            require_arg_value "$1" "${2:-}"
            TARGET_RPC_URLS+=("$2")
            shift 2
            ;;
        --anvil-port)
            require_arg_value "$1" "${2:-}"
            TARGET_RPC_URLS+=("http://127.0.0.1:$2")
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Error: unknown option: $1" >&2
            print_usage >&2
            exit 1
            ;;
    esac
done

if [[ ${#TARGET_RPC_URLS[@]} -eq 0 ]]; then
    if [[ -n "${RPC_URL:-}" ]]; then
        TARGET_RPC_URLS+=("$RPC_URL")
    elif [[ -n "${ANVIL_PORT:-}" ]]; then
        TARGET_RPC_URLS+=("http://127.0.0.1:${ANVIL_PORT}")
    else
        TARGET_RPC_URLS+=("http://127.0.0.1:8545")
    fi
fi

# No .env loading: all required vars have local defaults below.
# To override, set env vars in the calling shell before invoking.
: "${DEPLOYER_PRIVATE_KEY:=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}" # Anvil default account private key
: "${DECRYPTION_ADDRESS:=0x5ffdaAB0373E62E2ea2944776209aEf29E631A64}"
: "${INPUT_VERIFICATION_ADDRESS:=0x812b06e1CDCE800494b79fFE4f925A504a9A9810}"
: "${CHAIN_ID_GATEWAY:=10901}"
: "${KMS_SIGNER_PRIVATE_KEY_0:=0x388b7680e4e1afa06efbfd45cdd1fe39f3c6af381df6555a19661f283b97de91}"
: "${PUBLIC_DECRYPTION_THRESHOLD:=1}"
: "${COPROCESSOR_SIGNER_PRIVATE_KEY_0:=0x7ec8ada6642fc4ccfb7729bc29c17cf8d21b61abd5642d1db992c0b8672ab901}"
: "${COPROCESSOR_THRESHOLD:=1}"

DEPLOY_TX_GAS_LIMIT="${DEPLOY_TX_GAS_LIMIT:-8000000}"

PROXY_ARTIFACT="out/ERC1967Proxy.sol/ERC1967Proxy.json"
EMPTY_PROXY_ARTIFACT="out/EmptyUUPSProxy.sol/EmptyUUPSProxy.json"
EMPTY_PROXY_ACL_ARTIFACT="out/EmptyUUPSProxyACL.sol/EmptyUUPSProxyACL.json"
ACL_ARTIFACT="out/ACL.sol/ACL.json"
EXECUTOR_ARTIFACT="out/CleartextFHEVMExecutor.sol/CleartextFHEVMExecutor.json"
KMS_VERIFIER_ARTIFACT="out/KMSVerifier.sol/KMSVerifier.json"
INPUT_VERIFIER_ARTIFACT="out/InputVerifier.sol/InputVerifier.json"
HCU_LIMIT_ARTIFACT="out/HCULimit.sol/HCULimit.json"
PAUSER_SET_ARTIFACT="out/PauserSet.sol/PauserSet.json"

ERC1967_IMPL_SLOT="0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
OZ_INITIALIZABLE_SLOT="0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00"
OZ_OWNABLE_SLOT="0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300"

artifact_value() {
    local artifact_path="$1"
    local jq_path="$2"

    if [[ ! -f "$artifact_path" ]]; then
        echo "Error: artifact not found: $artifact_path" >&2
        echo "Run ./deploy-local.sh without --skip-build to prepare local artifacts." >&2
        exit 1
    fi
    jq -r "$jq_path" "$artifact_path"
}

artifact_runtime_code() {
    artifact_value "$1" '.deployedBytecode.object // .deployedBytecode'
}

artifact_creation_code() {
    artifact_value "$1" '.bytecode.object // .bytecode'
}

rpc() {
    local method_suffix="$1"
    shift
    cast rpc "${LOCAL_STATE_RPC_NAMESPACE}_${method_suffix}" "$@" --rpc-url "$RPC_URL" >/dev/null
}

deploy_raw_contract() {
    local creation_code="$1"
    local addr
    addr="$(cast --json send \
        --rpc-url "$RPC_URL" \
        --private-key "$DEPLOYER_PRIVATE_KEY" \
        --gas-limit "$DEPLOY_TX_GAS_LIMIT" \
        --create "$creation_code" \
        | jq -r '.contractAddress // empty')"
    if [[ -z "$addr" ]]; then
        echo "Error: deploy_raw_contract returned no contractAddress" >&2
        return 1
    fi
    printf '%s\n' "$addr"
}

materialize_proxy() {
    local target="$1"
    local empty_impl="$2"
    local owner="${3:-}"

    rpc setCode "$target" "$PROXY_RUNTIME_CODE"
    rpc setStorageAt "$target" "$ERC1967_IMPL_SLOT" "$(pad_address "$empty_impl")"
    rpc setStorageAt "$target" "$OZ_INITIALIZABLE_SLOT" "0x0000000000000000000000000000000000000000000000000000000000000001"

    if [[ -n "$owner" ]]; then
        rpc setStorageAt "$target" "$OZ_OWNABLE_SLOT" "$(pad_address "$owner")"
    fi
}

upgrade_proxy() {
    local proxy="$1"
    local implementation="$2"
    local init_calldata="$3"

    cast send "$proxy" \
        "upgradeToAndCall(address,bytes)" \
        "$implementation" \
        "$init_calldata" \
        --gas-limit "$DEPLOY_TX_GAS_LIMIT" \
        --private-key "$DEPLOYER_PRIVATE_KEY" \
        --rpc-url "$RPC_URL" \
        >/dev/null
}

ensure_local_artifacts() {
    if is_truthy "$SKIP_BUILD"; then
        log "Skipping forge build (--skip-build)."
        return
    fi

    log "Running forge build..."
    run_with_captured_output forge build
}

load_artifacts() {
    PROXY_RUNTIME_CODE="$(artifact_runtime_code "$PROXY_ARTIFACT")"
    PAUSER_SET_RUNTIME_CODE="$(artifact_runtime_code "$PAUSER_SET_ARTIFACT")"

    if [[ -z "$PROXY_RUNTIME_CODE" || "$PROXY_RUNTIME_CODE" == "null" ]]; then
        echo "Error: could not read ERC1967Proxy runtime bytecode from $PROXY_ARTIFACT" >&2
        exit 1
    fi

    if [[ -z "$PAUSER_SET_RUNTIME_CODE" || "$PAUSER_SET_RUNTIME_CODE" == "null" ]]; then
        echo "Error: could not read PauserSet runtime bytecode from $PAUSER_SET_ARTIFACT" >&2
        exit 1
    fi

    DEPLOYER_ADDRESS="$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")" \
        || { echo "Error: could not derive deployer address from DEPLOYER_PRIVATE_KEY" >&2; exit 1; }
    KMS_SIGNER="$(resolve_signer_address KMS_SIGNER_ADDRESS_0 KMS_SIGNER_PRIVATE_KEY_0)"
    COPROCESSOR_SIGNER="$(resolve_signer_address COPROCESSOR_SIGNER_ADDRESS_0 COPROCESSOR_SIGNER_PRIVATE_KEY_0)"

    EMPTY_PROXY_ACL_CODE="$(artifact_creation_code "$EMPTY_PROXY_ACL_ARTIFACT")"
    EMPTY_PROXY_CODE="$(artifact_creation_code "$EMPTY_PROXY_ARTIFACT")"
    ACL_CODE="$(artifact_creation_code "$ACL_ARTIFACT")"
    EXECUTOR_CODE="$(artifact_creation_code "$EXECUTOR_ARTIFACT")"
    KMS_CODE="$(artifact_creation_code "$KMS_VERIFIER_ARTIFACT")"
    INPUT_VERIFIER_CODE="$(artifact_creation_code "$INPUT_VERIFIER_ARTIFACT")"
    HCU_LIMIT_CODE="$(artifact_creation_code "$HCU_LIMIT_ARTIFACT")"
    INIT_CALLDATA="$(cast calldata "initializeFromEmptyProxy()")"
    KMS_INIT_CALLDATA="$(cast calldata "initializeFromEmptyProxy(address,uint64,address[],uint256)" "$DECRYPTION_ADDRESS" "$CHAIN_ID_GATEWAY" "[$KMS_SIGNER]" "$PUBLIC_DECRYPTION_THRESHOLD")"
    INPUT_VERIFIER_INIT_CALLDATA="$(cast calldata "initializeFromEmptyProxy(address,uint64,address[],uint256)" "$INPUT_VERIFICATION_ADDRESS" "$CHAIN_ID_GATEWAY" "[$COPROCESSOR_SIGNER]" "$COPROCESSOR_THRESHOLD")"
    HCU_LIMIT_INIT_CALLDATA="$(cast calldata "initializeFromEmptyProxy(uint48,uint48,uint48)" "${HCU_CAP_PER_BLOCK:-20000000}" "${MAX_HCU_DEPTH_PER_TX:-5000000}" "${MAX_HCU_PER_TX:-20000000}")"
}

deploy_to_target() {
    local target_rpc_url="$1"

    (
        export RPC_URL="$target_rpc_url"
        if [[ -z "${LOCAL_STATE_RPC_NAMESPACE:-}" ]]; then
            LOCAL_STATE_RPC_NAMESPACE="$(resolve_local_state_rpc_namespace)"
        fi
        export LOCAL_STATE_RPC_NAMESPACE

        log "Deploying to ${RPC_URL} (${LOCAL_STATE_RPC_NAMESPACE})..."

        local empty_proxy_acl_impl
        local empty_proxy_impl
        local acl_impl
        local executor_impl
        local kms_impl
        local input_verifier_impl
        local hcu_limit_impl

        empty_proxy_acl_impl="$(deploy_raw_contract "$EMPTY_PROXY_ACL_CODE")"
        empty_proxy_impl="$(deploy_raw_contract "$EMPTY_PROXY_CODE")"
        acl_impl="$(deploy_raw_contract "$ACL_CODE")"
        executor_impl="$(deploy_raw_contract "$EXECUTOR_CODE")"
        kms_impl="$(deploy_raw_contract "$KMS_CODE")"
        input_verifier_impl="$(deploy_raw_contract "$INPUT_VERIFIER_CODE")"
        hcu_limit_impl="$(deploy_raw_contract "$HCU_LIMIT_CODE")"

        materialize_proxy "$ACL_ADD" "$empty_proxy_acl_impl" "$DEPLOYER_ADDRESS"
        upgrade_proxy "$ACL_ADD" "$acl_impl" "$INIT_CALLDATA"
        log "ACL deployed at $ACL_ADD"

        materialize_proxy "$EXECUTOR_ADD" "$empty_proxy_impl"
        upgrade_proxy "$EXECUTOR_ADD" "$executor_impl" "$INIT_CALLDATA"
        log "FHEVMExecutor deployed at $EXECUTOR_ADD"

        materialize_proxy "$KMS_VERIFIER_ADD" "$empty_proxy_impl"
        upgrade_proxy "$KMS_VERIFIER_ADD" "$kms_impl" "$KMS_INIT_CALLDATA"
        log "KMSVerifier deployed at $KMS_VERIFIER_ADD"

        materialize_proxy "$INPUT_VERIFIER_ADD" "$empty_proxy_impl"
        upgrade_proxy "$INPUT_VERIFIER_ADD" "$input_verifier_impl" "$INPUT_VERIFIER_INIT_CALLDATA"
        log "InputVerifier deployed at $INPUT_VERIFIER_ADD"

        materialize_proxy "$HCU_LIMIT_ADD" "$empty_proxy_impl"
        upgrade_proxy "$HCU_LIMIT_ADD" "$hcu_limit_impl" "$HCU_LIMIT_INIT_CALLDATA"
        log "HCULimit deployed at $HCU_LIMIT_ADD"

        rpc setCode "$PAUSER_SET_ADD" "$PAUSER_SET_RUNTIME_CODE"

        if [[ -n "${PAUSER_ADDRESS_0:-}" ]]; then
            local pauser_slot
            pauser_slot="$(cast index address "$PAUSER_ADDRESS_0" 0)"
            rpc setStorageAt "$PAUSER_SET_ADD" "$pauser_slot" "0x0000000000000000000000000000000000000000000000000000000000000001"
        fi

        log "PauserSet deployed at $PAUSER_SET_ADD"
        log "Done: ${RPC_URL}"
    )
}

ACL_ADD="$(extract_address_constant_from_file aclAdd)"
EXECUTOR_ADD="$(extract_address_constant_from_file fhevmExecutorAdd)"
KMS_VERIFIER_ADD="$(extract_address_constant_from_file kmsVerifierAdd)"
INPUT_VERIFIER_ADD="$(extract_address_constant_from_file inputVerifierAdd)"
HCU_LIMIT_ADD="$(extract_address_constant_from_file hcuLimitAdd)"
PAUSER_SET_ADD="$(extract_address_constant_from_file pauserSetAdd)"

ensure_local_artifacts
load_artifacts

declare -a DEPLOY_PIDS=()
for target_rpc_url in "${TARGET_RPC_URLS[@]}"; do
    deploy_to_target "$target_rpc_url" &
    DEPLOY_PIDS+=("$!")
done

status=0
for pid in "${DEPLOY_PIDS[@]}"; do
    if ! wait "$pid"; then
        status=1
    fi
done

exit "$status"
