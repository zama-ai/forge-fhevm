// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";
import {InputProofTestHelper} from "./helpers/InputProofTestHelper.sol";

contract FHEVMExecutorVerifyInputIntegrationTest is InputProofTestHelper {
    address internal constant USER = address(0xA11CE);
    address internal constant ALICE = address(0xB0B);
    address internal constant BOB = address(0xC0B);
    bytes internal constant EXTRA_DATA = hex"00";

    function setUp() public {
        _deployInputVerifierStack();
    }

    function test_integration_verifyInput_grantsTransientPermission() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = _inputHandle(42, FheType.Uint8, 0, 100, uint64(block.chainid));
        _seedInputPlaintext(handles[0], 42);
        bytes memory proof = _proofSingleSigner(handles, USER, address(this), EXTRA_DATA, MOCK_INPUT_SIGNER_PK);

        bytes32 verified = executor.verifyInput(handles[0], USER, proof, FheType.Uint8);
        assertEq(verified, handles[0]);
        assertTrue(aclContract.allowedTransient(verified, address(this)));
    }

    function test_integration_verifyInput_thenFheAdd() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = _inputHandle(10, FheType.Uint16, 0, 101, uint64(block.chainid));
        _seedInputPlaintext(handles[0], 10);
        bytes memory proof = _proofSingleSigner(handles, USER, address(this), EXTRA_DATA, MOCK_INPUT_SIGNER_PK);

        bytes32 verified = executor.verifyInput(handles[0], USER, proof, FheType.Uint16);
        bytes32 rhs = executor.trivialEncrypt(5, FheType.Uint16);
        bytes32 sum = executor.fheAdd(verified, rhs, bytes1(0x00));

        assertEq(_readPlaintext(sum), 15);
    }

    function test_integration_verifyInput_batchHandles() public {
        bytes32[] memory handles = new bytes32[](3);
        handles[0] = _inputHandle(1, FheType.Uint8, 0, 102, uint64(block.chainid));
        handles[1] = _inputHandle(2, FheType.Uint8, 1, 102, uint64(block.chainid));
        handles[2] = _inputHandle(3, FheType.Uint8, 2, 102, uint64(block.chainid));

        _seedInputPlaintext(handles[0], 1);
        _seedInputPlaintext(handles[1], 2);
        _seedInputPlaintext(handles[2], 3);

        bytes memory proof = _proofSingleSigner(handles, USER, address(this), EXTRA_DATA, MOCK_INPUT_SIGNER_PK);

        assertEq(executor.verifyInput(handles[0], USER, proof, FheType.Uint8), handles[0]);
        assertEq(executor.verifyInput(handles[2], USER, proof, FheType.Uint8), handles[2]);
    }

    function test_integration_verifyInput_differentCallers() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = _inputHandle(8, FheType.Uint32, 0, 103, uint64(block.chainid));
        _seedInputPlaintext(handles[0], 8);
        bytes memory proof = _proofSingleSigner(handles, USER, BOB, EXTRA_DATA, MOCK_INPUT_SIGNER_PK);

        vm.prank(BOB);
        bytes32 verified = executor.verifyInput(handles[0], USER, proof, FheType.Uint32);
        assertEq(verified, handles[0]);
        assertTrue(aclContract.allowedTransient(handles[0], BOB));
    }

    function test_integration_verifyInput_proofCaching() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = _inputHandle(13, FheType.Uint64, 0, 104, uint64(block.chainid));
        _seedInputPlaintext(handles[0], 13);
        bytes memory proof = _proofSingleSigner(handles, USER, address(this), EXTRA_DATA, MOCK_INPUT_SIGNER_PK);

        assertEq(executor.verifyInput(handles[0], USER, proof, FheType.Uint64), handles[0]);
        assertEq(executor.verifyInput(handles[0], USER, proof, FheType.Uint64), handles[0]);
    }

    function test_integration_verifyInput_thenAllowPersistent() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = _inputHandle(31, FheType.Uint128, 0, 105, uint64(block.chainid));
        _seedInputPlaintext(handles[0], 31);
        bytes memory proof = _proofSingleSigner(handles, USER, address(this), EXTRA_DATA, MOCK_INPUT_SIGNER_PK);

        bytes32 verified = executor.verifyInput(handles[0], USER, proof, FheType.Uint128);
        aclContract.allow(verified, ALICE);

        assertTrue(aclContract.persistAllowed(verified, ALICE));
    }
}
