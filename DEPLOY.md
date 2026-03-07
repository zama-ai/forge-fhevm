# FHEVM Host Deployment

Deploys the cleartext FHEVM host contracts using Forge scripts.

## Overview

The deployment uses a **two-phase approach** to work around Solidity's compile-time address baking:

1. **Compute** — predict all proxy addresses from the deployer's nonce, write them into `FHEVMHostAddresses.sol`
2. **Deploy** — `forge clean` to bust the cache, then deploy proxies, PauserSet, implementations, and upgrade

## Contracts deployed

| Contract | Role |
|---|---|
| `ACL` | Access control list for encrypted handles |
| `CleartextFHEVMExecutor` | Cleartext FHE executor (local/testing) |
| `KMSVerifier` | Verifies KMS decryption signatures |
| `InputVerifier` | Verifies coprocessor input signatures |
| `HCULimit` | Homomorphic compute unit limiter |
| `PauserSet` | Immutable pauser registry |

## Setup

```bash
cd forge-fhevm
forge soldeer install   # install dependencies (first time only)
cp .env.example .env
# fill in .env
```

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `DEPLOYER_PRIVATE_KEY` | yes | Deployer private key |
| `RPC_URL` | yes | RPC endpoint |
| `DECRYPTION_ADDRESS` | yes | Gateway `Decryption` proxy — EIP-712 verifying contract for `KMSVerifier` |
| `INPUT_VERIFICATION_ADDRESS` | yes | Gateway `InputVerification` proxy — EIP-712 verifying contract for `InputVerifier` |
| `CHAIN_ID_GATEWAY` | yes | Chain ID of the gateway chain |
| `PUBLIC_DECRYPTION_THRESHOLD` | yes | Minimum KMS signatures required |
| `COPROCESSOR_THRESHOLD` | yes | Minimum coprocessor signatures required |
| `KMS_SIGNER_ADDRESS_0` | yes* | KMS node signing address |
| `KMS_SIGNER_PRIVATE_KEY_0` | yes* | KMS node private key (address derived automatically) |
| `COPROCESSOR_SIGNER_ADDRESS_0` | yes* | Coprocessor signing address |
| `COPROCESSOR_SIGNER_PRIVATE_KEY_0` | yes* | Coprocessor private key (address derived automatically) |
| `PAUSER_ADDRESS_0` | no | Address to grant pauser role |
| `BROADCAST` | no | Set to `--broadcast` to send live transactions |
| `VERIFY` | no | Set to `--verify` to verify on Etherscan |

\* Supply either the address or the private key for each signer — address takes precedence if both are set.

## Deploy

```bash
./deploy.sh
```

For a live broadcast:

```bash
BROADCAST=--broadcast ./deploy.sh
```

## How it works

### Address pre-computation

Each proxy is deployed as `impl + ERC1967Proxy`, consuming two nonces. Starting from the deployer's nonce `N` at script start:

| Nonce | Contract | Address constant |
|---|---|---|
| N+1 | ACL proxy | `aclAdd` |
| N+3 | FHEVMExecutor proxy | `fhevmExecutorAdd` |
| N+5 | KMSVerifier proxy | `kmsVerifierAdd` |
| N+7 | InputVerifier proxy | `inputVerifierAdd` |
| N+9 | HCULimit proxy | `hcuLimitAdd` |
| N+10 | PauserSet | `pauserSetAdd` |

`ComputeAddresses.s.sol` writes these into `FHEVMHostAddresses.sol` before compilation, so implementation contracts can import them as `address constant`.

### Upgrade pattern

Each proxy starts as an `EmptyUUPSProxy` (initialized to version 1). After `PauserSet` is deployed, each proxy is upgraded via `upgradeToAndCall` to its real implementation, which calls `initializeFromEmptyProxy` — gated by `onlyFromEmptyProxy` (requires initialized version == 1).
