---
title: Testing Patterns
description: End-to-end patterns for testing confidential contracts with forge-fhevm.
---

# Testing Patterns

This guide shows common patterns for testing FHEVM contracts. Each example is a complete, runnable test.

## Confidential Token: Mint and Check Balance

The most common pattern — encrypt a value, pass it to a contract, and verify the result.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FhevmTest} from "forge-fhevm/FhevmTest.sol";
import {FHE} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

import "encrypted-types/EncryptedTypes.sol";

contract ConfidentialToken is ZamaEthereumConfig {
    mapping(address => euint64) private _balances;

    function mint(externalEuint64 encryptedAmount, bytes calldata inputProof) external {
        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
        euint64 nextBalance = FHE.add(_balances[msg.sender], amount);
        _balances[msg.sender] = nextBalance;

        FHE.allowThis(nextBalance);
        FHE.allow(nextBalance, msg.sender);
    }

    function balanceHandle(address account) external view returns (euint64) {
        return _balances[account];
    }

    function allowBalanceForPublicDecrypt(address account) external {
        FHE.makePubliclyDecryptable(_balances[account]);
    }
}

contract ConfidentialTokenTest is FhevmTest {
    ConfidentialToken token;

    function setUp() public override {
        super.setUp();
        token = new ConfidentialToken();
    }

    function test_mint_setsBalance() public {
        // Encrypt 100 tokens targeting the token contract
        (externalEuint64 amount, bytes memory proof) = encryptUint64(100, address(token));

        // Mint
        token.mint(amount, proof);

        // Read the balance handle and decrypt
        euint64 balance = token.balanceHandle(address(this));
        assertEq(decrypt(balance), 100);
    }
}
```

::: info
Your contract under test must inherit a Zama config (e.g., `ZamaEthereumConfig`) so that `FHE.*` calls route to the correct host contract addresses.
:::

## Public Decrypt with Callback Verification

When your contract verifies decryption proofs on-chain using `FHE.checkSignatures()`:

```solidity
function test_publicDecrypt_withVerification() public {
    // Mint tokens
    (externalEuint64 amount, bytes memory proof) = encryptUint64(100, address(token));
    token.mint(amount, proof);

    // The contract marks the balance as publicly decryptable
    token.allowBalanceForPublicDecrypt(address(this));

    // Decrypt — returns cleartexts + KMS-signed proof
    euint64 balance = token.balanceHandle(address(this));
    bytes32[] memory handles = new bytes32[](1);
    handles[0] = euint64.unwrap(balance);

    (uint256[] memory cleartexts, bytes memory decryptionProof) = publicDecrypt(handles);

    // The proof passes on-chain verification
    FHE.checkSignatures(handles, abi.encode(cleartexts), decryptionProof);

    assertEq(cleartexts[0], 100);
}
```

## User Decrypt Flow

Testing user-facing decryption where a user reads their own confidential balance. The contract grants ACL permissions during business logic (mint, transfer), so you only need to sign and decrypt:

```solidity
function test_userDecrypt_flow() public {
    uint256 constant USER_PK = 0xA11CE;
    address user = vm.addr(USER_PK);

    // Encrypt as the user, targeting the token contract
    (externalEuint64 amount, bytes memory proof) = encryptUint64(222, user, address(token));

    // Mint as the user — the contract calls FHE.allow(balance, user) internally
    vm.prank(user);
    token.mint(amount, proof);

    // Sign a decrypt request and read the balance
    euint64 balance = token.balanceHandle(user);
    bytes memory signature = signUserDecrypt(USER_PK, address(token));
    uint256 cleartext = userDecrypt(euint64.unwrap(balance), user, address(token), signature);

    assertEq(cleartext, 222);
}
```

## Confidential Transfer with Balance Assertions

A complete transfer test showing both sender and recipient balance verification:

```solidity
function test_transfer_updatesBalances() public {
    uint256 constant HOLDER_PK = 0xA11CE;
    uint256 constant RECIPIENT_PK = 0xB0B;
    address holder = vm.addr(HOLDER_PK);
    address recipient = vm.addr(RECIPIENT_PK);

    // Mint 1000 to holder
    (externalEuint64 mintAmt, bytes memory mintProof) = encryptUint64(1000, holder, address(token));
    vm.prank(holder);
    token.mint(mintAmt, mintProof);

    // Transfer 400 from holder to recipient
    (externalEuint64 xferAmt, bytes memory xferProof) = encryptUint64(400, holder, address(token));
    vm.prank(holder);
    token.confidentialTransfer(recipient, xferAmt, xferProof);

    // Assert both balances
    assertEq(_decryptBalance(HOLDER_PK, holder), 600);
    assertEq(_decryptBalance(RECIPIENT_PK, recipient), 400);
}

function _decryptBalance(uint256 pk, address account) internal returns (uint64) {
    bytes memory sig = signUserDecrypt(pk, address(token));
    return uint64(userDecrypt(
        euint64.unwrap(token.confidentialBalanceOf(account)),
        vm.addr(pk),
        address(token),
        sig
    ));
}
```

## Fuzz Testing FHE Arithmetic

forge-fhevm works with Foundry's fuzz testing. The plaintext tracking handles wrapping arithmetic correctly:

```solidity
function test_fheAdd_commutative(uint64 a, uint64 b) public {
    // Encrypt both operands
    (externalEuint64 left, bytes memory leftProof) = encryptUint64(a, address(token));
    (externalEuint64 right, bytes memory rightProof) = encryptUint64(b, address(token));

    // Perform encrypted addition in both orders
    euint64 sumAB = token.addEncrypted(left, leftProof, right, rightProof);
    euint64 sumBA = token.addEncrypted(right, rightProof, left, leftProof);

    // Verify commutativity
    assertEq(decrypt(sumAB), decrypt(sumBA));

    // Verify correctness (wrapping arithmetic)
    uint64 expected;
    unchecked { expected = a + b; }
    assertEq(decrypt(sumAB), expected);
}
```

## Overriding `setUp()`

When you override `setUp()`, always call `super.setUp()` first to ensure the FHEVM host contracts are deployed:

```solidity
contract MyTest is FhevmTest {
    MyContract myContract;

    function setUp() public override {
        super.setUp(); // deploys FHEVM contracts
        myContract = new MyContract();
    }
}
```
