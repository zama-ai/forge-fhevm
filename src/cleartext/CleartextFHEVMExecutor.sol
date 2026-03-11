// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {FHEVMExecutor} from "../fhevm-host/contracts/FHEVMExecutor.sol";
import {FheType} from "../fhevm-host/contracts/shared/FheType.sol";
import {CleartextArithmetic} from "./CleartextArithmetic.sol";
import {FheTypeBitWidth} from "./FheTypeBitWidth.sol";

/// @notice Cleartext executor variant for deployments backed by a cleartext service.
/// @dev Extends the symbolic executor with a plaintext mirror for local/dev integrations.
///      Unlike the base host contracts, `verifyInput` expects the `inputProof` extra-data section
///      to append one 32-byte cleartext per handle, in the same order as the encoded handles:
///      `numHandles || numSigners || handles || signatures || cleartexts`.
///      This cleartext suffix is a deployment-specific convention consumed only by this contract.
contract CleartextFHEVMExecutor is FHEVMExecutor {
    /// @dev Handle to cleartext value mapping for local testing.
    mapping(bytes32 => uint256) public plaintexts;

    function fheAdd(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheAdd(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheAdd(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheSub(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheSub(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheSub(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheMul(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheMul(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheMul(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheDiv(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheDiv(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheDiv(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheRem(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheRem(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheRem(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheBitAnd(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheBitAnd(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheBitAnd(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheBitOr(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheBitOr(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheBitOr(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheBitXor(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheBitXor(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheBitXor(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheShl(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheShl(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheShl(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheShr(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheShr(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheShr(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheRotl(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheRotl(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheRotl(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheRotr(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheRotr(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheRotr(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheEq(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheEq(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheEq(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheNe(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheNe(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheNe(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheGe(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheGe(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheGe(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheGt(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheGt(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheGt(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheLe(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheLe(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheLe(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheLt(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheLt(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheLt(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheMin(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheMin(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheMin(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheMax(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) public override returns (bytes32 result) {
        result = super.fheMax(lhs, rhs, scalarByte);
        plaintexts[result] =
            CleartextArithmetic.fheMax(plaintexts[lhs], _rhsValue(rhs, scalarByte), uint8(_typeOf(lhs)), scalarByte);
    }

    function fheNeg(bytes32 ct) public override returns (bytes32 result) {
        result = super.fheNeg(ct);
        plaintexts[result] = CleartextArithmetic.fheNeg(plaintexts[ct], uint8(_typeOf(ct)));
    }

    function fheNot(bytes32 ct) public override returns (bytes32 result) {
        result = super.fheNot(ct);
        plaintexts[result] = CleartextArithmetic.fheNot(plaintexts[ct], uint8(_typeOf(ct)));
    }

    function fheIfThenElse(bytes32 control, bytes32 ifTrue, bytes32 ifFalse) public override returns (bytes32 result) {
        result = super.fheIfThenElse(control, ifTrue, ifFalse);
        plaintexts[result] =
            CleartextArithmetic.fheIfThenElse(plaintexts[control], plaintexts[ifTrue], plaintexts[ifFalse]);
    }

    function cast(bytes32 ct, FheType toType) public override returns (bytes32 result) {
        result = super.cast(ct, toType);
        plaintexts[result] = CleartextArithmetic.fheCast(plaintexts[ct], uint8(toType));
    }

    function trivialEncrypt(uint256 pt, FheType toType) public override returns (bytes32 result) {
        result = super.trivialEncrypt(pt, toType);
        plaintexts[result] = CleartextArithmetic.normalizePlaintextToType(pt, uint8(toType));
    }

    /// @notice Verifies an input handle and mirrors its cleartext into `plaintexts`.
    /// @dev The underlying `InputVerifier` still authenticates the canonical prefix
    ///      `numHandles || numSigners || handles || signatures || extraData`.
    ///      In cleartext mode, this executor additionally interprets `extraData` as a packed
    ///      sequence of 32-byte cleartexts, aligned with the `handles` array order.
    ///      A companion cleartext service is expected to append those values when building proofs.
    function verifyInput(bytes32 inputHandle, address userAddress, bytes memory inputProof, FheType inputType)
        public
        override
        returns (bytes32 result)
    {
        result = super.verifyInput(inputHandle, userAddress, inputProof, inputType);

        if (inputProof.length < 2) {
            return result;
        }

        uint8 numHandles = uint8(inputProof[0]);
        uint8 numSigners = uint8(inputProof[1]);
        uint256 cleartextStart = 2 + uint256(numHandles) * 32 + uint256(numSigners) * 65;

        if (inputProof.length < cleartextStart + 32) {
            return result;
        }

        for (uint8 i = 0; i < numHandles; i++) {
            uint256 handleOffset = 2 + uint256(i) * 32;
            bytes32 handleInProof;
            assembly {
                handleInProof := mload(add(add(inputProof, 32), handleOffset))
            }

            if (handleInProof == inputHandle) {
                uint256 cleartextOffset = cleartextStart + uint256(i) * 32;
                if (inputProof.length < cleartextOffset + 32) {
                    break;
                }

                uint256 cleartext;
                assembly {
                    cleartext := mload(add(add(inputProof, 32), cleartextOffset))
                }
                plaintexts[result] = CleartextArithmetic.normalizePlaintextToType(cleartext, uint8(inputType));
                break;
            }
        }
    }

    function _generateRand(FheType randType, bytes16 seed) internal override returns (bytes32 result) {
        result = super._generateRand(randType, seed);
        plaintexts[result] = CleartextArithmetic.rand(seed, FheTypeBitWidth.bitWidthForType(uint8(randType)));
    }

    function _generateRandBounded(uint256 upperBound, FheType randType, bytes16 seed)
        internal
        override
        returns (bytes32 result)
    {
        result = super._generateRandBounded(upperBound, randType, seed);
        plaintexts[result] = CleartextArithmetic.randBounded(seed, upperBound);
    }

    function _rhsValue(bytes32 rhs, bytes1 scalarByte) private view returns (uint256) {
        return (scalarByte == 0x01) ? uint256(rhs) : plaintexts[rhs];
    }
}
