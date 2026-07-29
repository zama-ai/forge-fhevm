// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {FHE, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

/**
 * @dev A consumer contract that uses BOTH fhEVM and OpenZeppelin upgradeable.
 *
 * The `Ownable2StepUpgradeable` inheritance is the load-bearing part of this fixture: it
 * resolves to OZ 5.4, while forge-fhevm's vendored host contracts are built against an older
 * pin. If FhevmTest ever re-imports host contract *source*, the two versions collide in one
 * project-global remapping and this file stops compiling.
 */
contract ConfidentialCounter is ZamaEthereumConfig, Ownable2StepUpgradeable {
    euint64 private _count;

    function add(externalEuint64 value, bytes calldata proof) external {
        euint64 delta = FHE.fromExternal(value, proof);
        _count = FHE.add(_count, delta);
        FHE.allowThis(_count);
        FHE.allow(_count, msg.sender);
    }

    function count() external view returns (euint64) {
        return _count;
    }
}
