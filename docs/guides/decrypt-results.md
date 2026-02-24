---
title: Decrypt Results
description: Three decryption modes for reading encrypted values in tests.
---

# Decrypt Results

forge-fhevm provides three decryption modes, each matching a different production decryption flow. Choose the one that matches your contract's pattern.

| Mode | Function | Use When |
|------|----------|----------|
| [Low-level](#low-level-decrypt) | `decrypt()` | Quick test assertions on any handle |
| [Public decrypt](#public-decrypt) | `publicDecrypt()` | Contract uses the `FHE.checkSignatures()` callback pattern |
| [User decrypt](#user-decrypt) | `userDecrypt()` | User-facing decryption (e.g., reading your own balance) |

## Low-Level Decrypt

The simplest mode. Call `decrypt()` on any encrypted handle to get the plaintext. No ACL checks, no proofs — a direct lookup for quick test assertions.

```solidity
// After some contract interaction that produces an encrypted result...
euint64 balance = token.confidentialBalanceOf(address(this));
uint64 value = decrypt(balance);
assertEq(value, 100);
```

### Typed Overloads

`decrypt()` has typed overloads for every encrypted type. Each returns the corresponding Solidity type:

```solidity
bool    result = decrypt(myEbool);
uint8   result = decrypt(myEuint8);
uint16  result = decrypt(myEuint16);
uint32  result = decrypt(myEuint32);
uint64  result = decrypt(myEuint64);
uint128 result = decrypt(myEuint128);
uint256 result = decrypt(myEuint256);
address result = decrypt(myEaddress);
```

There is also a raw `decrypt(bytes32 handle)` overload that returns `uint256`.

## Public Decrypt

Use `publicDecrypt()` when your contract uses the callback pattern with `FHE.checkSignatures()`. This mode returns both the cleartext values and a valid KMS-signed proof that passes on-chain verification.

### Example

Your contract exposes a function that marks a handle for public decryption (via `FHE.makePubliclyDecryptable()`), and another that verifies the proof on-chain:

```solidity
// Mint tokens
(externalEuint64 amount, bytes memory proof) = encryptUint64(100, address(token));
token.mint(amount, proof);

// The contract marks the balance as publicly decryptable
token.allowBalanceForPublicDecrypt(address(this));

// Decrypt — returns cleartexts + a KMS-signed proof
euint64 balance = token.balanceHandle(address(this));
bytes32[] memory handles = new bytes32[](1);
handles[0] = euint64.unwrap(balance);

(uint256[] memory cleartexts, bytes memory decryptionProof) = publicDecrypt(handles);
assertEq(cleartexts[0], 100);

// The proof passes on-chain verification
token.verifyPublicDecrypt(handles, abi.encode(cleartexts), decryptionProof);
```

::: warning
`publicDecrypt()` reverts with `HandleNotAllowedForPublicDecryption` if the contract hasn't called `FHE.makePubliclyDecryptable()` on the handle.
:::

### Batching Multiple Handles

You can decrypt multiple handles of different types in a single call:

```solidity
bytes32[] memory handles = new bytes32[](3);
handles[0] = euint16.unwrap(smallValue);
handles[1] = euint64.unwrap(mediumValue);
handles[2] = euint256.unwrap(largeValue);

(uint256[] memory cleartexts, bytes memory proof) = publicDecrypt(handles);
// cleartexts[0], cleartexts[1], cleartexts[2] — all as uint256
```

## User Decrypt

Use `userDecrypt()` when testing the user-facing decryption flow — for example, a user reading their own confidential balance. This mirrors the production pattern where a user signs an EIP-712 request to prove they're authorized to decrypt.

### How ACL Permissions Work

In a well-designed confidential contract, ACL permissions are granted as part of the business logic. For example, when a token contract processes a mint or transfer, it calls `FHE.allow(balance, owner)` to grant the owner persistent access to their balance handle. You don't need to grant permissions manually in your tests — the contract does it for you.

### Example

```solidity
uint256 constant HOLDER_PK = 0xA11CE;
address holder = vm.addr(HOLDER_PK);

// Encrypt and mint — the token contract grants ACL to the holder internally
(externalEuint64 amount, bytes memory proof) = encryptUint64(1000, holder, address(token));
vm.prank(holder);
token.mint(amount, proof);

// Sign a decrypt request and read the balance
euint64 balance = token.confidentialBalanceOf(holder);
bytes memory signature = signUserDecrypt(HOLDER_PK, address(token));
uint256 cleartext = userDecrypt(euint64.unwrap(balance), holder, address(token), signature);

assertEq(cleartext, 1000);
```

The two steps from the test writer's perspective are:

1. **`signUserDecrypt(privateKey, contractAddress)`** — produces the EIP-712 signature
2. **`userDecrypt(handle, user, contract, signature)`** — verifies ACL + signature, returns the plaintext

### Helper Pattern

For tests that decrypt frequently, extract a helper:

```solidity
function _decryptBalance(uint256 pk, address account) internal returns (uint64) {
    bytes memory sig = signUserDecrypt(pk, address(token));
    return uint64(userDecrypt(
        euint64.unwrap(token.confidentialBalanceOf(account)),
        vm.addr(pk),
        address(token),
        sig
    ));
}

// Then in tests:
assertEq(_decryptBalance(HOLDER_PK, holder), 600);
assertEq(_decryptBalance(RECIPIENT_PK, recipient), 400);
```

### `signUserDecrypt` Overloads

The simple overload signs for a single contract using `block.timestamp` and a 1-day duration:

```solidity
bytes memory sig = signUserDecrypt(userPk, contractAddress);
```

The full overload gives you control over all parameters:

```solidity
address[] memory contracts = new address[](2);
contracts[0] = address(tokenA);
contracts[1] = address(tokenB);

bytes memory sig = signUserDecrypt(
    userPk,
    contracts,
    block.timestamp,    // startTimestamp
    7                   // durationDays
);
```

### Error Cases

`userDecrypt()` enforces the same validation as the production flow:

| Error | Cause |
|-------|-------|
| `UserAddressEqualsContractAddress` | `userAddress == contractAddress` |
| `UserNotAuthorizedForDecrypt` | User lacks **persistent** ACL permission (the contract didn't call `FHE.allow`) |
| `ContractNotAuthorizedForDecrypt` | Contract lacks **persistent** ACL permission (the contract didn't call `FHE.allowThis`) |
| `InvalidUserDecryptSignature` | Signature doesn't match `userAddress` or is malformed |
