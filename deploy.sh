#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Two-phase FHEVM host deployment
#
# Phase 1: Compute proxy addresses and write FHEVMHostAddresses.sol
# Phase 2: Deploy proxies, PauserSet, and upgrade to implementations
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
#   BROADCAST (set to "--broadcast" to send live transactions)
#   VERIFY    (set to "--verify" to verify on Etherscan)
#   ETCH_ZAMA_LOCAL_ADDRESSES=1  (after deploy, mirror the stack to Zama localConfig addresses)
#   LOCAL_STATE_RPC_NAMESPACE     (optional override: "anvil" or "hardhat")
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

BROADCAST="${BROADCAST:-}"
VERIFY="${VERIFY:-}"
ETCH_ZAMA_LOCAL_ADDRESSES="${ETCH_ZAMA_LOCAL_ADDRESSES:-0}"

echo "============================================================"
echo "Phase 1: Computing proxy addresses"
echo "============================================================"
forge script script/ComputeAddresses.s.sol \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY"

echo ""
echo "============================================================"
echo "Phase 2: Deploying FHEVM host contracts"
echo "============================================================"
# Clear the compilation cache so forge picks up the rewritten FHEVMHostAddresses.sol.
# Without this, forge reuses the cached artifacts from Phase 1 compilation, which
# were built against the OLD addresses (before vm.writeFile ran).
forge clean
forge_deploy_cmd=(
    forge script script/DeployFHEVMHost.s.sol
    --rpc-url "$RPC_URL"
    --private-key "$DEPLOYER_PRIVATE_KEY"
)

if [[ "$BROADCAST" == "--broadcast" ]]; then
    forge_deploy_cmd+=(--broadcast)
fi

FORGE_BROADCAST_FLAG="$(resolve_forge_broadcast_pacing_flag)"
if [[ -n "$FORGE_BROADCAST_FLAG" ]]; then
    forge_deploy_cmd+=("$FORGE_BROADCAST_FLAG")
fi

if [[ "$VERIFY" == "--verify" ]]; then
    forge_deploy_cmd+=(--verify)
fi

"${forge_deploy_cmd[@]}"

echo ""
echo "Deployment complete."

if is_truthy "$ETCH_ZAMA_LOCAL_ADDRESSES"; then
    if [[ "$BROADCAST" != "--broadcast" ]]; then
        echo "Error: ETCH_ZAMA_LOCAL_ADDRESSES requires BROADCAST=--broadcast so Phase 2 is persisted on-chain." >&2
        exit 1
    fi

    LOCAL_STATE_RPC_NAMESPACE="$(resolve_local_state_rpc_namespace)"
    export LOCAL_STATE_RPC_NAMESPACE

    echo ""
    echo "============================================================"
    echo "Phase 3: Mirroring deployment to Zama localConfig addresses"
    echo "============================================================"
    echo "Using local-state RPC namespace: ${LOCAL_STATE_RPC_NAMESPACE}"

    ./script/etch-zama-addresses.sh

    echo ""
    echo "Zama localConfig addresses updated."
fi
