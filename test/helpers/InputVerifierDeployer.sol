// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {EmptyUUPSProxy} from "@fhevm/host-contracts/contracts/emptyProxy/EmptyUUPSProxy.sol";
import {InputVerifier} from "@fhevm/host-contracts/contracts/InputVerifier.sol";
import {inputVerifierAdd} from "@fhevm/host-contracts/addresses/FHEVMHostAddresses.sol";
import {ExecutorDeployer} from "./ExecutorDeployer.sol";

abstract contract InputVerifierDeployer is ExecutorDeployer {
    InputVerifier internal inputVerifierContract;

    uint256 internal constant MOCK_INPUT_SIGNER_PK = 0x7ec8ada6642fc4ccfb7729bc29c17cf8d21b61abd5642d1db992c0b8672ab901;
    address internal mockInputSigner;

    function _deployInputVerifierStack() internal {
        _deployExecutorStack();

        mockInputSigner = vm.addr(MOCK_INPUT_SIGNER_PK);

        address emptyProxyImpl = address(new EmptyUUPSProxy());
        deployCodeTo(
            "test/helpers/ExecutorDeployer.sol:DeployableERC1967Proxy",
            abi.encode(emptyProxyImpl, abi.encodeCall(EmptyUUPSProxy.initialize, ())),
            inputVerifierAdd
        );
        vm.label(inputVerifierAdd, "InputVerifier Proxy");

        address inputVerifierImpl = address(new InputVerifier());
        vm.label(inputVerifierImpl, "InputVerifier Implementation");

        address[] memory signers = new address[](1);
        signers[0] = mockInputSigner;

        vm.prank(OWNER);
        EmptyUUPSProxy(inputVerifierAdd)
            .upgradeToAndCall(
                inputVerifierImpl,
                abi.encodeCall(
                    InputVerifier.initializeFromEmptyProxy, (inputVerifierAdd, uint64(block.chainid), signers, 1)
                )
            );

        inputVerifierContract = InputVerifier(inputVerifierAdd);
    }
}
