// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {EmptyUUPSProxy} from "@fhevm/host-contracts/contracts/emptyProxy/EmptyUUPSProxy.sol";
import {KMSVerifier} from "@fhevm/host-contracts/contracts/KMSVerifier.sol";
import {kmsVerifierAdd} from "@fhevm/host-contracts/addresses/FHEVMHostAddresses.sol";
import {InputVerifierDeployer} from "./InputVerifierDeployer.sol";

/// @notice Test deployer for real KMSVerifier wiring with deterministic mock signer configuration.
abstract contract KMSVerifierDeployer is InputVerifierDeployer {
    KMSVerifier internal kmsVerifierContract;

    uint256 internal constant MOCK_KMS_SIGNER_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    address internal mockKmsSigner;

    /// @notice Deploys and initializes the real KMSVerifier stack at canonical test addresses.
    /// @dev Deploys the empty proxy, upgrades to KMSVerifier implementation, and configures one mock signer.
    function _deployKMSVerifierStack() internal {
        _deployInputVerifierStack();

        mockKmsSigner = vm.addr(MOCK_KMS_SIGNER_PK);

        address emptyProxyImpl = address(new EmptyUUPSProxy());
        deployCodeTo(
            "test/helpers/ExecutorDeployer.sol:DeployableERC1967Proxy",
            abi.encode(emptyProxyImpl, abi.encodeCall(EmptyUUPSProxy.initialize, ())),
            kmsVerifierAdd
        );
        vm.label(kmsVerifierAdd, "KMSVerifier Proxy");

        address kmsVerifierImpl = address(new KMSVerifier());
        vm.label(kmsVerifierImpl, "KMSVerifier Implementation");

        address[] memory signers = new address[](1);
        signers[0] = mockKmsSigner;

        vm.prank(OWNER);
        EmptyUUPSProxy(kmsVerifierAdd)
            .upgradeToAndCall(
                kmsVerifierImpl,
                abi.encodeCall(
                    KMSVerifier.initializeFromEmptyProxy, (kmsVerifierAdd, uint64(block.chainid), signers, 1)
                )
            );

        kmsVerifierContract = KMSVerifier(kmsVerifierAdd);
    }
}
