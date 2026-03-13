// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {FhevmTest} from "../src/FhevmTest.sol";
import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";

import {
    externalEbool,
    externalEuint8,
    externalEuint16,
    externalEuint32,
    externalEuint64,
    externalEuint128,
    externalEuint256,
    externalEaddress
} from "encrypted-types/EncryptedTypes.sol";

contract FhevmTestEncryptTest is FhevmTest {
    function test_internalEncrypt_bool_nonzero_normalizesStoredPlaintext() public {
        (bytes32 handle,) = _encrypt(2, FheType.Bool, address(this), address(this));
        assertEq(_plaintexts[handle], 1);
    }

    function test_internalEncrypt_bool_high_byte_only_normalizesToFalse() public {
        (bytes32 handle,) = _encrypt(0x0100, FheType.Bool, address(this), address(this));
        assertEq(_plaintexts[handle], 0);
    }

    function test_encryptUint64_returnsValidHandle() public {
        (externalEuint64 handle, bytes memory proof) = encryptUint64(42, address(this));

        assertNotEq(externalEuint64.unwrap(handle), bytes32(0));
        assertGt(proof.length, 0);
    }

    function test_encryptUint64_handleHasCorrectType() public {
        (externalEuint64 handle,) = encryptUint64(42, address(this));

        assertEq(uint8(externalEuint64.unwrap(handle)[30]), uint8(FheType.Uint64));
    }

    function test_encryptUint64_storesPlaintextInExecutor() public {
        (externalEuint64 handle,) = encryptUint64(42, address(this));

        assertEq(_plaintexts[externalEuint64.unwrap(handle)], 42);
    }

    function test_encryptUint64_proofVerifiableByInputVerifier() public {
        (externalEuint64 handle, bytes memory proof) = encryptUint64(42, address(this));

        bytes32 verified = _executor.verifyInput(externalEuint64.unwrap(handle), address(this), proof, FheType.Uint64);
        assertEq(verified, externalEuint64.unwrap(handle));
    }

    function test_encryptBool_works() public {
        (externalEbool handle, bytes memory proof) = encryptBool(true, address(this));
        assertEq(uint8(externalEbool.unwrap(handle)[30]), uint8(FheType.Bool));
        assertEq(_plaintexts[externalEbool.unwrap(handle)], 1);
        assertEq(
            _executor.verifyInput(externalEbool.unwrap(handle), address(this), proof, FheType.Bool),
            externalEbool.unwrap(handle)
        );
    }

    function test_encryptUint8_works() public {
        (externalEuint8 handle, bytes memory proof) = encryptUint8(13, address(this));
        assertEq(uint8(externalEuint8.unwrap(handle)[30]), uint8(FheType.Uint8));
        assertEq(_plaintexts[externalEuint8.unwrap(handle)], 13);
        assertEq(
            _executor.verifyInput(externalEuint8.unwrap(handle), address(this), proof, FheType.Uint8),
            externalEuint8.unwrap(handle)
        );
    }

    function test_encryptUint16_works() public {
        (externalEuint16 handle, bytes memory proof) = encryptUint16(513, address(this));
        assertEq(uint8(externalEuint16.unwrap(handle)[30]), uint8(FheType.Uint16));
        assertEq(_plaintexts[externalEuint16.unwrap(handle)], 513);
        assertEq(
            _executor.verifyInput(externalEuint16.unwrap(handle), address(this), proof, FheType.Uint16),
            externalEuint16.unwrap(handle)
        );
    }

    function test_encryptUint32_works() public {
        (externalEuint32 handle, bytes memory proof) = encryptUint32(91_337, address(this));
        assertEq(uint8(externalEuint32.unwrap(handle)[30]), uint8(FheType.Uint32));
        assertEq(_plaintexts[externalEuint32.unwrap(handle)], 91_337);
        assertEq(
            _executor.verifyInput(externalEuint32.unwrap(handle), address(this), proof, FheType.Uint32),
            externalEuint32.unwrap(handle)
        );
    }

    function test_encryptUint128_works() public {
        uint128 value = type(uint128).max - 7;
        (externalEuint128 handle, bytes memory proof) = encryptUint128(value, address(this));
        assertEq(uint8(externalEuint128.unwrap(handle)[30]), uint8(FheType.Uint128));
        assertEq(_plaintexts[externalEuint128.unwrap(handle)], value);
        assertEq(
            _executor.verifyInput(externalEuint128.unwrap(handle), address(this), proof, FheType.Uint128),
            externalEuint128.unwrap(handle)
        );
    }

    function test_encryptUint256_works() public {
        uint256 value = type(uint256).max - 5;
        (externalEuint256 handle, bytes memory proof) = encryptUint256(value, address(this));
        assertEq(uint8(externalEuint256.unwrap(handle)[30]), uint8(FheType.Uint256));
        assertEq(_plaintexts[externalEuint256.unwrap(handle)], value);
        assertEq(
            _executor.verifyInput(externalEuint256.unwrap(handle), address(this), proof, FheType.Uint256),
            externalEuint256.unwrap(handle)
        );
    }

    function test_encryptAddress_works() public {
        address value = address(0xA11CE);
        (externalEaddress handle, bytes memory proof) = encryptAddress(value, address(this));

        assertEq(uint8(externalEaddress.unwrap(handle)[30]), uint8(FheType.Uint160));
        assertEq(_plaintexts[externalEaddress.unwrap(handle)], uint256(uint160(value)));
        assertEq(
            _executor.verifyInput(externalEaddress.unwrap(handle), address(this), proof, FheType.Uint160),
            externalEaddress.unwrap(handle)
        );
    }

    function test_encrypt_withExplicitUserAndContract() public {
        address user = address(0xA11CE);
        address target = address(0xBEEF);

        (externalEuint64 handle, bytes memory proof) = encryptUint64(777, user, target);

        vm.prank(target);
        bytes32 verified = _executor.verifyInput(externalEuint64.unwrap(handle), user, proof, FheType.Uint64);

        assertEq(verified, externalEuint64.unwrap(handle));
    }

    function test_encrypt_differentNoncesProduceDifferentHandles() public {
        (externalEuint64 first,) = encryptUint64(123, address(this));
        (externalEuint64 second,) = encryptUint64(123, address(this));

        assertNotEq(externalEuint64.unwrap(first), externalEuint64.unwrap(second));
    }
}
