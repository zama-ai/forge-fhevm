// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {FhevmTest} from "forge-fhevm/FhevmTest.sol";
import {euint64, externalEuint64} from "encrypted-types/EncryptedTypes.sol";
import {ConfidentialCounter} from "../src/ConfidentialCounter.sol";

/// @dev End-to-end check that a downstream repo can inherit the test base while pinning its own
/// (newer) OpenZeppelin, with the library resolving from an installed dependency directory.
contract ConfidentialCounterTest is FhevmTest {
    ConfidentialCounter internal counter;

    function setUp() public override {
        super.setUp();
        counter = new ConfidentialCounter();
    }

    function test_hostStackIsDeployedAtCanonicalAddresses() public view {
        assertGt(address(_executor).code.length, 0, "executor not deployed");
        assertGt(address(_acl).code.length, 0, "acl not deployed");
        assertGt(address(_inputVerifier).code.length, 0, "input verifier not deployed");
        assertGt(address(_kmsVerifier).code.length, 0, "kms verifier not deployed");
    }

    function test_encryptAddAndDecryptRoundTrip() public {
        (externalEuint64 a, bytes memory aProof) = encryptUint64(7, address(counter));
        counter.add(a, aProof);

        (externalEuint64 b, bytes memory bProof) = encryptUint64(35, address(counter));
        counter.add(b, bProof);

        euint64 total = counter.count();
        assertEq(decrypt(total), 42);
    }
}
