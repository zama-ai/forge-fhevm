#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
source "$REPO_ROOT/script/lib/deploy-common.sh"

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
MIRROR_TX_GAS_LIMIT="${MIRROR_TX_GAS_LIMIT:-3000000}"

ADDRESSES_FILE="src/fhevm-host/addresses/FHEVMHostAddresses.sol"
PROXY_ARTIFACT="out/ERC1967Proxy.sol/ERC1967Proxy.json"
EMPTY_PROXY_ARTIFACT="out/EmptyUUPSProxy.sol/EmptyUUPSProxy.json"
EMPTY_PROXY_ACL_ARTIFACT="out/EmptyUUPSProxyACL.sol/EmptyUUPSProxyACL.json"
PAUSER_SET_ARTIFACT="out/PauserSet.sol/PauserSet.json"

ZAMA_ACL="0x50157CFfD6bBFA2DECe204a89ec419c23ef5755D"
ZAMA_EXECUTOR="0xe3a9105a3a932253A70F126eb1E3b589C643dD24"
ZAMA_KMS_VERIFIER="0x901F8942346f7AB3a01F6D7613119Bca447Bb030"
ZAMA_INPUT_VERIFIER="0x4c5859f0F772848b2D91F1D83E2Fe57935348029"
ZAMA_HCU_LIMIT="0x5f3f1dBD7B74C6B46e8c44f98792A1dAf8d69154"
ZAMA_PAUSER_SET="0xb7278A61aa25c888815aFC32Ad3cC52fF24fE575"

ERC1967_IMPL_SLOT="0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
OZ_INITIALIZABLE_SLOT="0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00"
OZ_OWNABLE_SLOT="0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300"

extract_address_constant() {
    local name="$1"
    local result
    result="$(sed -n "s/address constant ${name} = address(\\(0x[0-9A-Fa-f]*\\));/\\1/p" "$ADDRESSES_FILE")"
    if [[ -z "$result" ]]; then
        echo "Error: could not find address constant '${name}' in ${ADDRESSES_FILE}" >&2
        return 1
    fi
    printf '%s\n' "$result"
}

rpc() {
    local method_suffix="$1"
    shift
    cast rpc "${LOCAL_STATE_RPC_NAMESPACE}_${method_suffix}" "$@" --rpc-url "$RPC_URL" >/dev/null
}

slot_value_to_address() {
    local slot_value="$1"
    printf '0x%s\n' "${slot_value:26:40}"
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
        --gas-limit "$MIRROR_TX_GAS_LIMIT" \
        --create "$creation_code" \
        | jq -r '.contractAddress // empty')"
    if [[ -z "$addr" ]]; then
        echo "Error: deploy_raw_contract returned no contractAddress" >&2
        return 1
    fi
    printf '%s\n' "$addr"
}

EMPTY_PROXY_IMPL=""
EMPTY_PROXY_ACL_IMPL=""

ensure_empty_proxy_impls() {
    if [[ -z "$EMPTY_PROXY_IMPL" ]]; then
        EMPTY_PROXY_IMPL="$(deploy_raw_contract "$(artifact_creation_code "$EMPTY_PROXY_ARTIFACT")")"
    fi

    if [[ -z "$EMPTY_PROXY_ACL_IMPL" ]]; then
        EMPTY_PROXY_ACL_IMPL="$(deploy_raw_contract "$(artifact_creation_code "$EMPTY_PROXY_ACL_ARTIFACT")")"
    fi
}

mirror_proxy() {
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
        --gas-limit "$MIRROR_TX_GAS_LIMIT" \
        --private-key "$DEPLOYER_PRIVATE_KEY" \
        --rpc-url "$RPC_URL" \
        >/dev/null
}

for artifact_path in "$PROXY_ARTIFACT" "$EMPTY_PROXY_ARTIFACT" "$EMPTY_PROXY_ACL_ARTIFACT" "$PAUSER_SET_ARTIFACT"; do
    if [[ ! -f "$artifact_path" ]]; then
        echo "Error: artifact not found: $artifact_path" >&2
        exit 1
    fi
done

PROXY_RUNTIME_CODE="$(artifact_runtime_code "$PROXY_ARTIFACT")"
PAUSER_SET_RUNTIME_CODE="$(artifact_runtime_code "$PAUSER_SET_ARTIFACT")"

ACL_ADD="$(extract_address_constant aclAdd)"
EXECUTOR_ADD="$(extract_address_constant fhevmExecutorAdd)"
KMS_VERIFIER_ADD="$(extract_address_constant kmsVerifierAdd)"
INPUT_VERIFIER_ADD="$(extract_address_constant inputVerifierAdd)"
HCU_LIMIT_ADD="$(extract_address_constant hcuLimitAdd)"
PAUSER_SET_ADD="$(extract_address_constant pauserSetAdd)"

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

ACL_IMPL="$(slot_value_to_address "$(cast storage "$ACL_ADD" "$ERC1967_IMPL_SLOT" --rpc-url "$RPC_URL")")"
EXECUTOR_IMPL="$(slot_value_to_address "$(cast storage "$EXECUTOR_ADD" "$ERC1967_IMPL_SLOT" --rpc-url "$RPC_URL")")"
KMS_IMPL="$(slot_value_to_address "$(cast storage "$KMS_VERIFIER_ADD" "$ERC1967_IMPL_SLOT" --rpc-url "$RPC_URL")")"
INPUT_VERIFIER_IMPL="$(slot_value_to_address "$(cast storage "$INPUT_VERIFIER_ADD" "$ERC1967_IMPL_SLOT" --rpc-url "$RPC_URL")")"
HCU_LIMIT_IMPL="$(slot_value_to_address "$(cast storage "$HCU_LIMIT_ADD" "$ERC1967_IMPL_SLOT" --rpc-url "$RPC_URL")")"

echo "Mirroring deployed host contracts to Zama localConfig addresses..."

if [[ "$(to_lower "$ACL_ADD")" != "$(to_lower "$ZAMA_ACL")" ]]; then
    ensure_empty_proxy_impls
    mirror_proxy "$ZAMA_ACL" "$EMPTY_PROXY_ACL_IMPL" "$DEPLOYER_ADDRESS"
    upgrade_proxy "$ZAMA_ACL" "$ACL_IMPL" "$(cast calldata "initializeFromEmptyProxy()")"
    echo "ACL mirrored at $ZAMA_ACL"
fi

if [[ "$(to_lower "$EXECUTOR_ADD")" != "$(to_lower "$ZAMA_EXECUTOR")" ]]; then
    ensure_empty_proxy_impls
    mirror_proxy "$ZAMA_EXECUTOR" "$EMPTY_PROXY_IMPL"
    upgrade_proxy "$ZAMA_EXECUTOR" "$EXECUTOR_IMPL" "$(cast calldata "initializeFromEmptyProxy()")"
    echo "FHEVMExecutor mirrored at $ZAMA_EXECUTOR"
fi

if [[ "$(to_lower "$KMS_VERIFIER_ADD")" != "$(to_lower "$ZAMA_KMS_VERIFIER")" ]]; then
    ensure_empty_proxy_impls
    mirror_proxy "$ZAMA_KMS_VERIFIER" "$EMPTY_PROXY_IMPL"
    upgrade_proxy \
        "$ZAMA_KMS_VERIFIER" \
        "$KMS_IMPL" \
        "$(cast calldata "initializeFromEmptyProxy(address,uint64,address[],uint256)" "$DECRYPTION_ADDRESS" "$CHAIN_ID_GATEWAY" "[$KMS_SIGNER]" "$PUBLIC_DECRYPTION_THRESHOLD")"
    echo "KMSVerifier mirrored at $ZAMA_KMS_VERIFIER"
fi

if [[ "$(to_lower "$INPUT_VERIFIER_ADD")" != "$(to_lower "$ZAMA_INPUT_VERIFIER")" ]]; then
    ensure_empty_proxy_impls
    mirror_proxy "$ZAMA_INPUT_VERIFIER" "$EMPTY_PROXY_IMPL"
    upgrade_proxy \
        "$ZAMA_INPUT_VERIFIER" \
        "$INPUT_VERIFIER_IMPL" \
        "$(cast calldata "initializeFromEmptyProxy(address,uint64,address[],uint256)" "$INPUT_VERIFICATION_ADDRESS" "$CHAIN_ID_GATEWAY" "[$COPROCESSOR_SIGNER]" "$COPROCESSOR_THRESHOLD")"
    echo "InputVerifier mirrored at $ZAMA_INPUT_VERIFIER"
fi

if [[ "$(to_lower "$HCU_LIMIT_ADD")" != "$(to_lower "$ZAMA_HCU_LIMIT")" ]]; then
    ensure_empty_proxy_impls
    mirror_proxy "$ZAMA_HCU_LIMIT" "$EMPTY_PROXY_IMPL"
    upgrade_proxy "$ZAMA_HCU_LIMIT" "$HCU_LIMIT_IMPL" "$(cast calldata "initializeFromEmptyProxy()")"
    echo "HCULimit mirrored at $ZAMA_HCU_LIMIT"
fi

if [[ "$(to_lower "$PAUSER_SET_ADD")" != "$(to_lower "$ZAMA_PAUSER_SET")" ]]; then
    rpc setCode "$ZAMA_PAUSER_SET" "$PAUSER_SET_RUNTIME_CODE"

    if [[ -n "${PAUSER_ADDRESS_0:-}" ]]; then
        PAUSER_SLOT="$(cast index address "$PAUSER_ADDRESS_0" 0)"
        rpc setStorageAt "$ZAMA_PAUSER_SET" "$PAUSER_SLOT" "0x0000000000000000000000000000000000000000000000000000000000000001"
    fi

    echo "PauserSet mirrored at $ZAMA_PAUSER_SET"
fi

echo "Zama localConfig mirroring complete."
