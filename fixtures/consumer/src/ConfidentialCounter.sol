// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {FHE, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

/// @dev The `Ownable2StepUpgradeable` inheritance is the load-bearing part of this fixture: it
/// resolves to OZ 5.4, so a host contract source import in the test base would collide here.
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
