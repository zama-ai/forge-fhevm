// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {FhevmTest} from "../src/FhevmTest.sol";
import {SampleEncryptedToken} from "./helpers/SampleEncryptedToken.sol";
import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";

import "encrypted-types/EncryptedTypes.sol";

contract FhevmTestIntegrationTest is FhevmTest {
    uint256 internal constant USER_PK = 0xA11CE;

    function test_integration_mintAndPublicDecrypt() public {
        SampleEncryptedToken token = new SampleEncryptedToken();

        (externalEuint64 amount, bytes memory inputProof) = encryptUint64(100, address(token));
        token.mint(amount, inputProof);

        euint64 balance = token.balanceHandle(address(this));
        token.allowBalanceForPublicDecrypt(address(this));

        bytes32[] memory handles = new bytes32[](1);
        handles[0] = euint64.unwrap(balance);

        (uint256[] memory cleartexts, bytes memory decryptionProof) = publicDecrypt(handles);
        token.verifyPublicDecrypt(handles, abi.encode(cleartexts), decryptionProof);

        assertEq(cleartexts[0], 100);
    }

    function test_integration_mintAndUserDecrypt() public {
        SampleEncryptedToken token = new SampleEncryptedToken();
        address user = vm.addr(USER_PK);

        (externalEuint64 amount, bytes memory inputProof) = encryptUint64(222, user, address(token));

        vm.prank(user);
        token.mint(amount, inputProof);

        euint64 balance = token.balanceHandle(user);
        bytes memory signature = signUserDecrypt(USER_PK, address(token));

        uint256 clear = userDecrypt(euint64.unwrap(balance), user, address(token), signature);
        assertEq(clear, 222);
    }

    function test_integration_fheAddCommutative_fuzz(uint64 a, uint64 b) public {
        SampleEncryptedToken token = new SampleEncryptedToken();

        (externalEuint64 left, bytes memory leftProof) = encryptUint64(a, address(token));
        (externalEuint64 right, bytes memory rightProof) = encryptUint64(b, address(token));

        euint64 sumAB = token.addEncrypted(left, leftProof, right, rightProof);
        euint64 sumBA = token.addEncrypted(right, rightProof, left, leftProof);

        bytes32[] memory handlesAB = new bytes32[](1);
        handlesAB[0] = euint64.unwrap(sumAB);
        _acl.allowForDecryption(handlesAB);

        bytes32[] memory handlesBA = new bytes32[](1);
        handlesBA[0] = euint64.unwrap(sumBA);
        _acl.allowForDecryption(handlesBA);

        (uint256[] memory clearAB,) = publicDecrypt(handlesAB);
        (uint256[] memory clearBA,) = publicDecrypt(handlesBA);

        uint64 expected;
        unchecked {
            expected = a + b;
        }
        assertEq(clearAB[0], clearBA[0]);
        assertEq(clearAB[0], expected);
    }

    function test_integration_contractUnderTestInheritsZamaConfig() public {
        SampleEncryptedToken token = new SampleEncryptedToken();

        assertEq(token.confidentialProtocolId(), type(uint256).max);
    }
}
