// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ACL} from "@fhevm/host-contracts/contracts/ACL.sol";
import {FHEVMExecutor} from "@fhevm/host-contracts/contracts/FHEVMExecutor.sol";
import {HCULimit} from "@fhevm/host-contracts/contracts/HCULimit.sol";
import {PauserSet} from "@fhevm/host-contracts/contracts/immutable/PauserSet.sol";
import {EmptyUUPSProxy} from "@fhevm/host-contracts/contracts/emptyProxy/EmptyUUPSProxy.sol";
import {EmptyUUPSProxyACL} from "@fhevm/host-contracts/contracts/emptyProxyACL/EmptyUUPSProxyACL.sol";
import {
    aclAdd,
    fhevmExecutorAdd,
    hcuLimitAdd,
    pauserSetAdd
} from "@fhevm/host-contracts/addresses/FHEVMHostAddresses.sol";
import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";
import {PlaintextDBMixin} from "../../src/PlaintextDBMixin.sol";

/**
 * @dev Re-expose OZ proxy constructor so deployCodeTo can find the artifact.
 */
contract DeployableERC1967Proxy is ERC1967Proxy {
    constructor(address implementation, bytes memory data) ERC1967Proxy(implementation, data) {}
}

/**
 * @title ExecutorDeployer
 * @notice Test helper that deploys the real FHEVMExecutor stack at known addresses.
 */
abstract contract ExecutorDeployer is PlaintextDBMixin {
    FHEVMExecutor internal executor;
    ACL internal aclContract;

    address internal constant OWNER = address(0xBEEF);

    function _deployExecutorStack() internal {
        vm.etch(pauserSetAdd, address(new PauserSet()).code);
        vm.label(pauserSetAdd, "PauserSet");

        address emptyProxyAclImpl = address(new EmptyUUPSProxyACL());
        deployCodeTo(
            "test/helpers/ExecutorDeployer.sol:DeployableERC1967Proxy",
            abi.encode(emptyProxyAclImpl, abi.encodeCall(EmptyUUPSProxyACL.initialize, (OWNER))),
            aclAdd
        );
        vm.label(aclAdd, "ACL Proxy");

        address aclImpl = address(new ACL());
        vm.label(aclImpl, "ACL Implementation");

        vm.prank(OWNER);
        EmptyUUPSProxyACL(aclAdd).upgradeToAndCall(aclImpl, abi.encodeCall(ACL.initializeFromEmptyProxy, ()));
        aclContract = ACL(aclAdd);

        address emptyProxyImpl = address(new EmptyUUPSProxy());
        deployCodeTo(
            "test/helpers/ExecutorDeployer.sol:DeployableERC1967Proxy",
            abi.encode(emptyProxyImpl, abi.encodeCall(EmptyUUPSProxy.initialize, ())),
            hcuLimitAdd
        );
        vm.label(hcuLimitAdd, "HCULimit Proxy");

        address hcuLimitImpl = address(new HCULimit());
        vm.label(hcuLimitImpl, "HCULimit Implementation");

        vm.prank(OWNER);
        EmptyUUPSProxy(hcuLimitAdd)
            .upgradeToAndCall(
                hcuLimitImpl, abi.encodeCall(HCULimit.initializeFromEmptyProxy, (20_000_000, 5_000_000, 20_000_000))
            );

        deployCodeTo(
            "test/helpers/ExecutorDeployer.sol:DeployableERC1967Proxy",
            abi.encode(emptyProxyImpl, abi.encodeCall(EmptyUUPSProxy.initialize, ())),
            fhevmExecutorAdd
        );
        vm.label(fhevmExecutorAdd, "FHEVMExecutor Proxy");

        address executorImpl = address(new FHEVMExecutor());
        vm.label(executorImpl, "FHEVMExecutor Implementation");

        vm.prank(OWNER);
        EmptyUUPSProxy(fhevmExecutorAdd)
            .upgradeToAndCall(executorImpl, abi.encodeCall(FHEVMExecutor.initializeFromEmptyProxy, ()));

        executor = FHEVMExecutor(fhevmExecutorAdd);

        vm.recordLogs();
        vm.getRecordedLogs();
    }

    function _trivialEncrypt(uint256 value, FheType toType) internal returns (bytes32) {
        return executor.trivialEncrypt(value, toType);
    }

    function _seedInputPlaintext(bytes32 handle, uint256 value) internal {
        _seedPlaintext(handle, value);
    }
}
