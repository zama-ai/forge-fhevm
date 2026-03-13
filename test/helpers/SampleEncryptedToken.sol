// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {FHE} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

import {euint64, externalEuint64} from "encrypted-types/EncryptedTypes.sol";

contract SampleEncryptedToken is ZamaEthereumConfig {
    mapping(address => euint64) private _balances;

    function mint(externalEuint64 encryptedAmount, bytes calldata inputProof) external {
        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
        euint64 nextBalance = FHE.add(_balances[msg.sender], amount);
        _balances[msg.sender] = nextBalance;

        FHE.allowThis(nextBalance);
        FHE.allow(nextBalance, msg.sender);
    }

    function addEncrypted(
        externalEuint64 lhs,
        bytes calldata lhsInputProof,
        externalEuint64 rhs,
        bytes calldata rhsInputProof
    ) external returns (euint64) {
        euint64 left = FHE.fromExternal(lhs, lhsInputProof);
        euint64 right = FHE.fromExternal(rhs, rhsInputProof);
        euint64 sum = FHE.add(left, right);

        FHE.allowThis(sum);
        FHE.allow(sum, msg.sender);

        return sum;
    }

    function balanceHandle(address account) external view returns (euint64) {
        return _balances[account];
    }

    function allowBalanceForPublicDecrypt(address account) external {
        FHE.makePubliclyDecryptable(_balances[account]);
    }

    function verifyPublicDecrypt(
        bytes32[] memory handlesList,
        bytes memory abiEncodedCleartexts,
        bytes memory decryptionProof
    ) external {
        FHE.checkSignatures(handlesList, abiEncodedCleartexts, decryptionProof);
    }
}
