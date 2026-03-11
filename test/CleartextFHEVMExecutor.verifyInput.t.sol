// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {EmptyUUPSProxy} from "@fhevm/host-contracts/contracts/emptyProxy/EmptyUUPSProxy.sol";
import {fhevmExecutorAdd} from "@fhevm/host-contracts/addresses/FHEVMHostAddresses.sol";
import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";
import {CleartextFHEVMExecutor} from "../src/cleartext/CleartextFHEVMExecutor.sol";
import {InputProofTestHelper} from "./helpers/InputProofTestHelper.sol";

contract CleartextFHEVMExecutorVerifyInputTest is InputProofTestHelper {
    address internal constant USER = address(0xA11CE);

    CleartextFHEVMExecutor internal clearExecutor;

    function setUp() public {
        _deployInputVerifierStack();

        address clearExecutorImpl = address(new CleartextFHEVMExecutor());
        vm.prank(OWNER);
        EmptyUUPSProxy(fhevmExecutorAdd).upgradeToAndCall(clearExecutorImpl, bytes(""));

        clearExecutor = CleartextFHEVMExecutor(fhevmExecutorAdd);
    }

    function test_verifyInput_bool_nonzero_cleartext_is_true() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = _inputHandle(2, FheType.Bool, 0, 201, uint64(block.chainid));

        bytes memory extraData = abi.encodePacked(bytes32(uint256(2)));
        bytes memory proof = _proofSingleSigner(handles, USER, address(this), extraData, MOCK_INPUT_SIGNER_PK);

        bytes32 verified = clearExecutor.verifyInput(handles[0], USER, proof, FheType.Bool);

        assertEq(verified, handles[0]);
        assertEq(clearExecutor.plaintexts(verified), 1);
    }

    function test_verifyInput_bool_high_byte_only_cleartext_is_false() public {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = _inputHandle(2, FheType.Bool, 0, 201, uint64(block.chainid));

        bytes memory extraData = abi.encodePacked(bytes32(uint256(0x0100)));
        bytes memory proof = _proofSingleSigner(handles, USER, address(this), extraData, MOCK_INPUT_SIGNER_PK);

        bytes32 verified = clearExecutor.verifyInput(handles[0], USER, proof, FheType.Bool);

        assertEq(verified, handles[0]);
        assertEq(clearExecutor.plaintexts(verified), 0);
    }

    function test_verifyInput_reads_cleartext_for_requested_handle_index() public {
        bytes32[] memory handles = new bytes32[](2);
        handles[0] = _inputHandle(1, FheType.Bool, 0, 201, uint64(block.chainid));
        handles[1] = _inputHandle(0, FheType.Bool, 1, 202, uint64(block.chainid));

        bytes memory extraData = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(0x0100)));
        bytes memory proof = _proofSingleSigner(handles, USER, address(this), extraData, MOCK_INPUT_SIGNER_PK);

        bytes32 verified = clearExecutor.verifyInput(handles[1], USER, proof, FheType.Bool);

        assertEq(verified, handles[1]);
        assertEq(clearExecutor.plaintexts(verified), 0);
    }
}
