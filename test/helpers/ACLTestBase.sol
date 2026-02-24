// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";
import {IPauserSet} from "@fhevm/host-contracts/contracts/interfaces/IPauserSet.sol";
import {pauserSetAdd} from "@fhevm/host-contracts/addresses/FHEVMHostAddresses.sol";
import {ExecutorDeployer} from "./ExecutorDeployer.sol";

abstract contract ACLTestBase is ExecutorDeployer {
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CHARLIE = address(0xC4A3);

    function _createHandleWithPersistentPermission(uint256 value, FheType fheType, address account)
        internal
        returns (bytes32 handle)
    {
        handle = _trivialEncrypt(value, fheType);
        aclContract.allow(handle, account);
    }

    function _createHandleTransientOnly(uint256 value, FheType fheType) internal returns (bytes32 handle) {
        handle = _trivialEncrypt(value, fheType);
    }

    function _mockPauserSetIsPauser(address pauser, bool isPauser) internal {
        vm.mockCall(pauserSetAdd, abi.encodeCall(IPauserSet.isPauser, (pauser)), abi.encode(isPauser));
    }
}
