#!/usr/bin/env bash
# =============================================================================
# deploy-local.sh — Fixed-address local FHEVM host deployment
#
# Uses the committed addresses from FHEVMHostAddresses.sol, recompiles the
# host contracts against those addresses, then materializes proxies/code
# directly at those addresses on a local RPC backend.
#
# Required env vars:
#   DEPLOYER_PRIVATE_KEY
#   RPC_URL
#   DECRYPTION_ADDRESS
#   INPUT_VERIFICATION_ADDRESS
#   CHAIN_ID_GATEWAY
#   KMS_SIGNER_ADDRESS_0 or KMS_SIGNER_PRIVATE_KEY_0
#   PUBLIC_DECRYPTION_THRESHOLD
#   COPROCESSOR_SIGNER_ADDRESS_0 or COPROCESSOR_SIGNER_PRIVATE_KEY_0
#   COPROCESSOR_THRESHOLD
#
# Optional:
#   PAUSER_ADDRESS_0
#   LOCAL_STATE_RPC_NAMESPACE (optional override: "anvil" or "hardhat")
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source "$SCRIPT_DIR/script/lib/deploy-common.sh"

load_dotenv_if_present ".env"

require_env_vars \
    DEPLOYER_PRIVATE_KEY \
    RPC_URL \
    DECRYPTION_ADDRESS \
    INPUT_VERIFICATION_ADDRESS \
    CHAIN_ID_GATEWAY \
    PUBLIC_DECRYPTION_THRESHOLD \
    COPROCESSOR_THRESHOLD

require_one_of "KMS_SIGNER_ADDRESS_0 or KMS_SIGNER_PRIVATE_KEY_0" KMS_SIGNER_ADDRESS_0 KMS_SIGNER_PRIVATE_KEY_0
require_one_of \
    "COPROCESSOR_SIGNER_ADDRESS_0 or COPROCESSOR_SIGNER_PRIVATE_KEY_0" \
    COPROCESSOR_SIGNER_ADDRESS_0 \
    COPROCESSOR_SIGNER_PRIVATE_KEY_0

LOCAL_STATE_RPC_NAMESPACE="$(resolve_local_state_rpc_namespace)"
DEPLOY_TX_GAS_LIMIT="${DEPLOY_TX_GAS_LIMIT:-8000000}"
export LOCAL_STATE_RPC_NAMESPACE

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

rpc() {
    local method_suffix="$1"
    shift
    cast rpc "${LOCAL_STATE_RPC_NAMESPACE}_${method_suffix}" "$@" --rpc-url "$RPC_URL" >/dev/null
}

artifact_value() {
    local artifact_path="$1"
    local jq_path="$2"

    jq -r "$jq_path" "$artifact_path"
}

artifact_runtime_code() {
    artifact_value "$1" '.deployedBytecode.object // .deployedBytecode'
}

artifact_creation_code() {
    artifact_value "$1" '.bytecode.object // .bytecode'
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

echo "============================================================"
echo "Phase 1: Reading committed host addresses"
echo "============================================================"
ACL_ADD="$(extract_address_constant_from_file aclAdd)"
EXECUTOR_ADD="$(extract_address_constant_from_file fhevmExecutorAdd)"
KMS_VERIFIER_ADD="$(extract_address_constant_from_file kmsVerifierAdd)"
INPUT_VERIFIER_ADD="$(extract_address_constant_from_file inputVerifierAdd)"
HCU_LIMIT_ADD="$(extract_address_constant_from_file hcuLimitAdd)"
PAUSER_SET_ADD="$(extract_address_constant_from_file pauserSetAdd)"

echo ""
echo "============================================================"
echo "Phase 2: Rebuilding contracts for fixed local addresses"
echo "============================================================"
forge clean
forge build

echo ""
echo "============================================================"
echo "Phase 3: Deploying fixed-address local host stack"
echo "============================================================"
echo "Using local-state RPC namespace: ${LOCAL_STATE_RPC_NAMESPACE}"

for artifact_path in \
    "$PROXY_ARTIFACT" \
    "$EMPTY_PROXY_ARTIFACT" \
    "$EMPTY_PROXY_ACL_ARTIFACT" \
    "$ACL_ARTIFACT" \
    "$EXECUTOR_ARTIFACT" \
    "$KMS_VERIFIER_ARTIFACT" \
    "$INPUT_VERIFIER_ARTIFACT" \
    "$HCU_LIMIT_ARTIFACT" \
    "$PAUSER_SET_ARTIFACT"; do
    if [[ ! -f "$artifact_path" ]]; then
        echo "Error: artifact not found: $artifact_path" >&2
        exit 1
    fi
done

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

echo "Deploying freshly compiled implementations for committed local addresses..."

EMPTY_PROXY_ACL_CODE="$(artifact_creation_code "$EMPTY_PROXY_ACL_ARTIFACT")"
EMPTY_PROXY_CODE="$(artifact_creation_code "$EMPTY_PROXY_ARTIFACT")"
ACL_CODE="$(artifact_creation_code "$ACL_ARTIFACT")"
EXECUTOR_CODE="$(artifact_creation_code "$EXECUTOR_ARTIFACT")"
KMS_CODE="$(artifact_creation_code "$KMS_VERIFIER_ARTIFACT")"
INPUT_VERIFIER_CODE="$(artifact_creation_code "$INPUT_VERIFIER_ARTIFACT")"
HCU_LIMIT_CODE="$(artifact_creation_code "$HCU_LIMIT_ARTIFACT")"

EMPTY_PROXY_ACL_IMPL="$(deploy_raw_contract "$EMPTY_PROXY_ACL_CODE")"
EMPTY_PROXY_IMPL="$(deploy_raw_contract "$EMPTY_PROXY_CODE")"
ACL_IMPL="$(deploy_raw_contract "$ACL_CODE")"
EXECUTOR_IMPL="$(deploy_raw_contract "$EXECUTOR_CODE")"
KMS_IMPL="$(deploy_raw_contract "$KMS_CODE")"
INPUT_VERIFIER_IMPL="$(deploy_raw_contract "$INPUT_VERIFIER_CODE")"
HCU_LIMIT_IMPL="$(deploy_raw_contract "$HCU_LIMIT_CODE")"

INIT_CALLDATA="$(cast calldata "initializeFromEmptyProxy()")"

materialize_proxy "$ACL_ADD" "$EMPTY_PROXY_ACL_IMPL" "$DEPLOYER_ADDRESS"
upgrade_proxy "$ACL_ADD" "$ACL_IMPL" "$INIT_CALLDATA"
echo "ACL deployed at $ACL_ADD"

materialize_proxy "$EXECUTOR_ADD" "$EMPTY_PROXY_IMPL"
upgrade_proxy "$EXECUTOR_ADD" "$EXECUTOR_IMPL" "$INIT_CALLDATA"
echo "FHEVMExecutor deployed at $EXECUTOR_ADD"

materialize_proxy "$KMS_VERIFIER_ADD" "$EMPTY_PROXY_IMPL"
upgrade_proxy \
    "$KMS_VERIFIER_ADD" \
    "$KMS_IMPL" \
    "$(cast calldata "initializeFromEmptyProxy(address,uint64,address[],uint256)" "$DECRYPTION_ADDRESS" "$CHAIN_ID_GATEWAY" "[$KMS_SIGNER]" "$PUBLIC_DECRYPTION_THRESHOLD")"
echo "KMSVerifier deployed at $KMS_VERIFIER_ADD"

materialize_proxy "$INPUT_VERIFIER_ADD" "$EMPTY_PROXY_IMPL"
upgrade_proxy \
    "$INPUT_VERIFIER_ADD" \
    "$INPUT_VERIFIER_IMPL" \
    "$(cast calldata "initializeFromEmptyProxy(address,uint64,address[],uint256)" "$INPUT_VERIFICATION_ADDRESS" "$CHAIN_ID_GATEWAY" "[$COPROCESSOR_SIGNER]" "$COPROCESSOR_THRESHOLD")"
echo "InputVerifier deployed at $INPUT_VERIFIER_ADD"

materialize_proxy "$HCU_LIMIT_ADD" "$EMPTY_PROXY_IMPL"
upgrade_proxy "$HCU_LIMIT_ADD" "$HCU_LIMIT_IMPL" "$INIT_CALLDATA"
echo "HCULimit deployed at $HCU_LIMIT_ADD"

rpc setCode "$PAUSER_SET_ADD" "$PAUSER_SET_RUNTIME_CODE"

if [[ -n "${PAUSER_ADDRESS_0:-}" ]]; then
    PAUSER_SLOT="$(cast index address "$PAUSER_ADDRESS_0" 0)"
    rpc setStorageAt "$PAUSER_SET_ADD" "$PAUSER_SLOT" "0x0000000000000000000000000000000000000000000000000000000000000001"
fi

echo "PauserSet deployed at $PAUSER_SET_ADD"

echo ""
echo "Local fixed-address deployment complete."
