---
title: FhevmTest
description: Abstract base contract for testing FHEVM confidential smart contracts in Foundry.
---

# FhevmTest

Abstract base contract that deploys all FHEVM host contracts and provides helpers for encrypting inputs, decrypting results, and generating EIP-712 proofs.

## Import

```solidity
import {FhevmTest} from "forge-fhevm/FhevmTest.sol";
```

## Usage

Inherit `FhevmTest` in your test contract. The `setUp()` function deploys all FHEVM infrastructure automatically.

```solidity
contract MyTest is FhevmTest {
    function setUp() public override {
        super.setUp();
        // deploy your contracts here
    }

    function test_example() public {
        (externalEuint64 handle, bytes memory proof) = encryptUint64(42, address(this));
        // ...
    }
}
```

## State Variables

### _executor

```solidity
FHEVMExecutor internal _executor;
```

The deployed FHEVMExecutor instance. Processes FHE operations and emits events consumed by the plaintext database.

### _acl

```solidity
ACL internal _acl;
```

The deployed ACL instance. Manages per-handle access control — both transient (within a transaction) and persistent (across transactions).

### _inputVerifier

```solidity
InputVerifier internal _inputVerifier;
```

The deployed InputVerifier instance. Validates EIP-712 signed input proofs. Configured with `MOCK_INPUT_SIGNER` as the single authorized signer (threshold: 1).

### _kmsVerifier

```solidity
KMSVerifier internal _kmsVerifier;
```

The deployed KMSVerifier instance. Validates EIP-712 signed decryption proofs. Configured with `MOCK_KMS_SIGNER` as the single authorized signer (threshold: 1).

### MOCK_INPUT_SIGNER

```solidity
address internal MOCK_INPUT_SIGNER;
```

Address derived from `MOCK_INPUT_SIGNER_PK`. Set during `setUp()`.

### MOCK_KMS_SIGNER

```solidity
address internal MOCK_KMS_SIGNER;
```

Address derived from `MOCK_KMS_SIGNER_PK`. Set during `setUp()`.

## Constants

### MOCK_INPUT_SIGNER_PK

```solidity
uint256 internal constant MOCK_INPUT_SIGNER_PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
```

Private key used to sign input proofs. This is Foundry's default first test account key.

### MOCK_KMS_SIGNER_PK

```solidity
uint256 internal constant MOCK_KMS_SIGNER_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
```

Private key used to sign KMS decryption proofs. This is Foundry's default second test account key.

### EMPTY_EXTRA_DATA

```solidity
bytes internal constant EMPTY_EXTRA_DATA = hex"00";
```

Default extra data bytes appended to EIP-712 proofs.

### DEFAULT_USER_DECRYPT_DURATION_DAYS

```solidity
uint256 internal constant DEFAULT_USER_DECRYPT_DURATION_DAYS = 1;
```

Default validity duration (in days) for user decrypt signatures.

---

## Encryption Functions

All encryption functions return `(externalE*, bytes memory inputProof)`. The two-argument overload uses `address(this)` as the user. The three-argument overload lets you specify an explicit user address.

### encryptBool

```solidity
function encryptBool(bool value, address target)
    internal returns (externalEbool, bytes memory)
```

```solidity
function encryptBool(bool value, address user, address target)
    internal returns (externalEbool, bytes memory)
```

Encrypts a boolean value. Returns an `externalEbool` handle and a signed input proof.

```solidity
(externalEbool handle, bytes memory proof) = encryptBool(true, address(myContract)); // [!code focus]
```

### encryptUint8

```solidity
function encryptUint8(uint8 value, address target)
    internal returns (externalEuint8, bytes memory)
```

```solidity
function encryptUint8(uint8 value, address user, address target)
    internal returns (externalEuint8, bytes memory)
```

Encrypts a `uint8` value.

```solidity
(externalEuint8 handle, bytes memory proof) = encryptUint8(255, address(myContract)); // [!code focus]
```

### encryptUint16

```solidity
function encryptUint16(uint16 value, address target)
    internal returns (externalEuint16, bytes memory)
```

```solidity
function encryptUint16(uint16 value, address user, address target)
    internal returns (externalEuint16, bytes memory)
```

Encrypts a `uint16` value.

```solidity
(externalEuint16 handle, bytes memory proof) = encryptUint16(1_337, address(myContract)); // [!code focus]
```

### encryptUint32

```solidity
function encryptUint32(uint32 value, address target)
    internal returns (externalEuint32, bytes memory)
```

```solidity
function encryptUint32(uint32 value, address user, address target)
    internal returns (externalEuint32, bytes memory)
```

Encrypts a `uint32` value.

```solidity
(externalEuint32 handle, bytes memory proof) = encryptUint32(91_337, address(myContract)); // [!code focus]
```

### encryptUint64

```solidity
function encryptUint64(uint64 value, address target)
    internal returns (externalEuint64, bytes memory)
```

```solidity
function encryptUint64(uint64 value, address user, address target)
    internal returns (externalEuint64, bytes memory)
```

Encrypts a `uint64` value.

```solidity
(externalEuint64 handle, bytes memory proof) = encryptUint64(42, address(myContract)); // [!code focus]
```

### encryptUint128

```solidity
function encryptUint128(uint128 value, address target)
    internal returns (externalEuint128, bytes memory)
```

```solidity
function encryptUint128(uint128 value, address user, address target)
    internal returns (externalEuint128, bytes memory)
```

Encrypts a `uint128` value.

```solidity
(externalEuint128 handle, bytes memory proof) = encryptUint128(type(uint128).max, address(myContract)); // [!code focus]
```

### encryptUint256

```solidity
function encryptUint256(uint256 value, address target)
    internal returns (externalEuint256, bytes memory)
```

```solidity
function encryptUint256(uint256 value, address user, address target)
    internal returns (externalEuint256, bytes memory)
```

Encrypts a `uint256` value.

```solidity
(externalEuint256 handle, bytes memory proof) = encryptUint256(type(uint256).max, address(myContract)); // [!code focus]
```

### encryptAddress

```solidity
function encryptAddress(address value, address target)
    internal returns (externalEaddress, bytes memory)
```

```solidity
function encryptAddress(address value, address user, address target)
    internal returns (externalEaddress, bytes memory)
```

Encrypts an address value. Internally cast to `uint160` and stored as `FheType.Uint160`.

```solidity
(externalEaddress handle, bytes memory proof) = encryptAddress(address(0xA11CE), address(myContract)); // [!code focus]
```

---

## Decryption Functions

### decrypt

```solidity
function decrypt(bytes32 handle) internal returns (uint256)
```

Low-level decrypt. Processes pending events, then returns the raw `uint256` plaintext for the given handle.

```solidity
uint256 raw = decrypt(someHandle); // [!code focus]
```

---

### decrypt (typed overloads)

Typed overloads that return the correct Solidity type:

```solidity
function decrypt(ebool value) internal returns (bool)
function decrypt(euint8 value) internal returns (uint8)
function decrypt(euint16 value) internal returns (uint16)
function decrypt(euint32 value) internal returns (uint32)
function decrypt(euint64 value) internal returns (uint64)
function decrypt(euint128 value) internal returns (uint128)
function decrypt(euint256 value) internal returns (uint256)
function decrypt(eaddress value) internal returns (address)
```

```solidity
uint64 balance = decrypt(encryptedBalance); // [!code focus]
```

---

### publicDecrypt

```solidity
function publicDecrypt(bytes32[] memory handles)
    internal
    returns (uint256[] memory cleartexts, bytes memory decryptionProof)
```

Decrypts multiple handles with ACL verification. Every handle must be ACL-allowed for public decryption (`_acl.allowForDecryption`). Returns the cleartext values and a KMS-signed decryption proof verifiable by `KMSVerifier` and `FHE.checkSignatures()`.

Reverts with `HandleNotAllowedForPublicDecryption(bytes32 handle)` if any handle lacks permission.

```solidity
bytes32[] memory handles = new bytes32[](1);
handles[0] = euint64.unwrap(balance);

(uint256[] memory cleartexts, bytes memory proof) = publicDecrypt(handles); // [!code focus]
```

---

### userDecrypt

```solidity
function userDecrypt(
    bytes32 handle,
    address userAddress,
    address contractAddress,
    bytes memory userSignature
) internal returns (uint256)
```

Full user-decrypt flow with strict validation. Processes pending events, then enforces:

- `userAddress != contractAddress`
- Both addresses have **persistent** ACL permission (transient is not sufficient)
- The EIP-712 signature is valid for `userAddress`

Returns the plaintext value.

#### handle

`bytes32`

The encrypted handle to decrypt.

#### userAddress

`address`

The user requesting decryption. Must have persistent ACL permission and must have produced the signature.

#### contractAddress

`address`

The contract holding the encrypted value. Must have persistent ACL permission.

#### userSignature

`bytes memory`

EIP-712 signature from the user, generated via [`signUserDecrypt`](#signuserdecrypt).

```solidity
uint256 cleartext = userDecrypt( // [!code focus]
    euint64.unwrap(balance), user, address(token), signature // [!code focus]
); // [!code focus]
```

#### Errors

| Error | Cause |
|-------|-------|
| `HandleNotAllowedForPublicDecryption(bytes32)` | Handle not allowed in ACL for public decryption |
| `UserAddressEqualsContractAddress()` | `userAddress == contractAddress` |
| `UserNotAuthorizedForDecrypt(bytes32, address)` | User lacks persistent ACL permission |
| `ContractNotAuthorizedForDecrypt(bytes32, address)` | Contract lacks persistent ACL permission |
| `InvalidUserDecryptSignature()` | Signature doesn't recover to `userAddress` |

---

## Proof Helpers

### buildDecryptionProof

```solidity
function buildDecryptionProof(
    bytes32[] memory handles,
    bytes memory abiEncodedCleartexts
) internal view returns (bytes memory proof)
```

Builds a KMS-signed decryption proof for multiple handles. Does **not** check ACL permissions — use this for callback-style flows where you provide the cleartext and proof directly.

```solidity
bytes memory proof = buildDecryptionProof(handles, abi.encode(clear0, clear1)); // [!code focus]
```

---

```solidity
function buildDecryptionProof(
    bytes32 handle,
    bytes memory abiEncodedCleartext
) internal view returns (bytes memory proof)
```

Single-handle convenience overload.

```solidity
bytes memory proof = buildDecryptionProof(handle, abi.encode(cleartext)); // [!code focus]
```

---

### signUserDecrypt

```solidity
function signUserDecrypt(uint256 userPk, address contractAddress)
    internal view returns (bytes memory signature)
```

Signs a user decrypt request for a single contract. Uses `block.timestamp` as the start time and `DEFAULT_USER_DECRYPT_DURATION_DAYS` (1 day) as the duration.

```solidity
bytes memory sig = signUserDecrypt(USER_PK, address(myContract)); // [!code focus]
```

---

```solidity
function signUserDecrypt(
    uint256 userPk,
    address[] memory contractAddresses,
    uint256 startTimestamp,
    uint256 durationDays
) internal view returns (bytes memory signature)
```

Full overload with explicit contract list, start time, and duration. Computes the EIP-712 domain separator for the KMSVerifier, builds the typed-data digest via [`UserDecryptHelper`](/api/user-decrypt-helper), and signs with `vm.sign()`.

#### userPk

`uint256`

The user's private key.

#### contractAddresses

`address[] memory`

Contract addresses authorized in the decrypt request.

#### startTimestamp

`uint256`

Signature validity start time (Unix timestamp).

#### durationDays

`uint256`

Signature validity duration in days.

```solidity
address[] memory contracts = new address[](1);
contracts[0] = address(token);
bytes memory sig = signUserDecrypt(USER_PK, contracts, block.timestamp, 7); // [!code focus]
```
