---
title: UserDecryptHelper
description: Library for computing EIP-712 user decrypt request digests.
---

# UserDecryptHelper

Library that computes EIP-712 domain separators and typed-data digests for user-facing decryption requests.

You typically don't need this library directly — [`FhevmTest.signUserDecrypt`](/api/fhevm-test#signuserdecrypt) calls it internally. Use it when you need custom signature construction or want to verify signatures manually.

## Import

```solidity
import {UserDecryptHelper} from "forge-fhevm/UserDecryptHelper.sol";
```

## Functions

### computeUserDecryptDomainSeparator

```solidity
function computeUserDecryptDomainSeparator(
    uint256 chainId,
    address verifyingContract
) internal pure returns (bytes32)
```

Computes the EIP-712 domain separator for user decrypt requests. Uses `"Decryption"` as the domain name and `"1"` as the version.

#### chainId

`uint256`

The chain ID for the domain.

#### verifyingContract

`address`

The KMSVerifier contract address (user decrypt signatures are verified against the KMSVerifier domain).

```solidity
bytes32 domain = UserDecryptHelper.computeUserDecryptDomainSeparator( // [!code focus]
    block.chainid, kmsVerifierAdd // [!code focus]
); // [!code focus]
```

---

### computeUserDecryptDigest

```solidity
function computeUserDecryptDigest(
    bytes memory publicKey,
    address[] memory contractAddresses,
    uint256 startTimestamp,
    uint256 durationDays,
    bytes memory extraData,
    bytes32 domainSeparator
) internal pure returns (bytes32)
```

Computes the EIP-712 typed-data digest for a user decrypt request. This is the digest the user signs to authorize decryption of their encrypted values held by specific contracts.

#### publicKey

`bytes memory`

The user's public key, typically `abi.encodePacked(userAddress)`.

#### contractAddresses

`address[] memory`

The contract addresses authorized to participate in the decryption.

#### startTimestamp

`uint256`

Signature validity start time (Unix timestamp).

#### durationDays

`uint256`

Signature validity duration in days.

#### extraData

`bytes memory`

Additional bytes included in the signature. Use `EMPTY_EXTRA_DATA` (`hex"00"`) for the default.

#### domainSeparator

`bytes32`

The EIP-712 domain separator from [`computeUserDecryptDomainSeparator`](#computeuserdecryptdomainseparator).

```solidity
address user = vm.addr(USER_PK);
address[] memory contracts = new address[](1);
contracts[0] = address(token);

bytes32 domain = UserDecryptHelper.computeUserDecryptDomainSeparator(block.chainid, kmsVerifierAdd);
bytes32 digest = UserDecryptHelper.computeUserDecryptDigest( // [!code focus]
    abi.encodePacked(user), contracts, block.timestamp, 1, EMPTY_EXTRA_DATA, domain // [!code focus]
); // [!code focus]
```

## Constants

### EIP712_DOMAIN_TYPEHASH

```solidity
bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
```

### USER_DECRYPT_REQUEST_TYPEHASH

```solidity
bytes32 internal constant USER_DECRYPT_REQUEST_TYPEHASH = keccak256(
    "UserDecryptRequestVerification(bytes publicKey,address[] contractAddresses,uint256 startTimestamp,uint256 durationDays,bytes extraData)"
);
```
