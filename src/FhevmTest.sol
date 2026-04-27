// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {ACL} from "@fhevm/host-contracts/contracts/ACL.sol";
import {HCULimit} from "@fhevm/host-contracts/contracts/HCULimit.sol";
import {InputVerifier} from "@fhevm/host-contracts/contracts/InputVerifier.sol";
import {KMSVerifier} from "@fhevm/host-contracts/contracts/KMSVerifier.sol";
import {PauserSet} from "@fhevm/host-contracts/contracts/immutable/PauserSet.sol";
import {EmptyUUPSProxy} from "@fhevm/host-contracts/contracts/emptyProxy/EmptyUUPSProxy.sol";
import {EmptyUUPSProxyACL} from "@fhevm/host-contracts/contracts/emptyProxyACL/EmptyUUPSProxyACL.sol";
import {IERC7984ERC20Wrapper} from "@openzeppelin/confidential-contracts/interfaces/IERC7984ERC20Wrapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    aclAdd,
    fhevmExecutorAdd,
    hcuLimitAdd,
    inputVerifierAdd,
    kmsVerifierAdd,
    pauserSetAdd
} from "@fhevm/host-contracts/addresses/FHEVMHostAddresses.sol";
import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";
import {FHEVMExecutor} from "@fhevm/host-contracts/contracts/FHEVMExecutor.sol";
import {DeployableERC1967Proxy} from "./DeployableERC1967Proxy.sol";
import {PlaintextDBMixin} from "./PlaintextDBMixin.sol";
import {InputProofHelper} from "./InputProofHelper.sol";
import {KMSDecryptionProofHelper} from "./KMSDecryptionProofHelper.sol";
import {UserDecryptHelper} from "./UserDecryptHelper.sol";
import {CleartextArithmetic} from "./cleartext/CleartextArithmetic.sol";
import {HCULimitNoDepthCap} from "./HCULimitNoDepthCap.sol";

import {
    ebool,
    euint8,
    euint16,
    euint32,
    euint64,
    euint128,
    euint256,
    eaddress,
    externalEbool,
    externalEuint8,
    externalEuint16,
    externalEuint32,
    externalEuint64,
    externalEuint128,
    externalEuint256,
    externalEaddress
} from "encrypted-types/EncryptedTypes.sol";

abstract contract FhevmTest is PlaintextDBMixin {
    error HandleNotAllowedForPublicDecryption(bytes32 handle);
    error UserAddressEqualsContractAddress();
    error UserNotAuthorizedForDecrypt(bytes32 handle, address userAddress);
    error ContractNotAuthorizedForDecrypt(bytes32 handle, address contractAddress);
    error InvalidUserDecryptSignature();

    uint256 internal constant MOCK_INPUT_SIGNER_PK = 0x7ec8ada6642fc4ccfb7729bc29c17cf8d21b61abd5642d1db992c0b8672ab901;
    uint256 internal constant MOCK_KMS_SIGNER_PK = 0x388b7680e4e1afa06efbfd45cdd1fe39f3c6af381df6555a19661f283b97de91;

    bytes internal constant EMPTY_EXTRA_DATA = hex"00";
    uint256 internal constant DEFAULT_USER_DECRYPT_DURATION_DAYS = 1;
    address internal constant PROXY_OWNER = address(0xBEEF);
    string internal constant ERC1967_PROXY_ARTIFACT = "DeployableERC1967Proxy.sol:DeployableERC1967Proxy";
    FHEVMExecutor internal _executor;
    ACL internal _acl;
    InputVerifier internal _inputVerifier;
    KMSVerifier internal _kmsVerifier;

    address internal mockInputSigner;
    address internal mockKmsSigner;

    uint256 private _encryptNonce;

    function setUp() public virtual {
        vm.chainId(31337);
        mockInputSigner = vm.addr(MOCK_INPUT_SIGNER_PK);
        mockKmsSigner = vm.addr(MOCK_KMS_SIGNER_PK);
        _deployAllContracts();

        vm.recordLogs();
        vm.getRecordedLogs();
    }

    /// @notice Funds `user` with wrapper underlying and wraps `amount` into confidential tokens.
    /// @dev This is the confidential-token equivalent of Foundry's `deal`.
    function dealConfidential(IERC7984ERC20Wrapper wrapper, address user, uint256 amount) internal {
        IERC20 underlyingToken = IERC20(wrapper.underlying());
        deal(address(underlyingToken), user, underlyingToken.balanceOf(user) + amount);

        vm.startPrank(user);
        underlyingToken.approve(address(wrapper), type(uint256).max);
        wrapper.wrap(user, amount);
        vm.stopPrank();
    }

    /// @notice Relaxes only the sequential HCU depth cap for subsequent FHE operations.
    /// @dev Keeps the host contract's total per-transaction HCU accounting enabled, but swaps
    /// the HCULimit implementation behind the test proxy for a variant that no longer reverts
    /// on deep handle chains. This is useful for end-to-end tests whose orchestration is heavier
    /// than the individual production calls they are trying to validate.
    function disableHCUDepthLimit() internal {
        address relaxedHcuLimit = address(new HCULimitNoDepthCap());
        vm.prank(PROXY_OWNER);
        EmptyUUPSProxy(payable(hcuLimitAdd)).upgradeToAndCall(relaxedHcuLimit, "");
    }

    /// @notice Encrypts a boolean for the given target contract.
    /// @param value The clear boolean value to encrypt.
    /// @param target The contract expected to call `FHE.fromExternal`.
    /// @return handle External encrypted boolean handle and input proof.
    function encryptBool(bool value, address target) internal returns (externalEbool, bytes memory) {
        return encryptBool(value, address(this), target);
    }

    /// @notice Encrypts a boolean for an explicit user/target pair.
    /// @param value The clear boolean value to encrypt.
    /// @param user The user embedded in the input proof authorization.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptBool(bool value, address user, address target) internal returns (externalEbool, bytes memory) {
        (bytes32 handle, bytes memory inputProof) = _encrypt(value ? 1 : 0, FheType.Bool, user, target);
        return (externalEbool.wrap(handle), inputProof);
    }

    /// @notice Encrypts an 8-bit unsigned integer for the given target contract.
    /// @param value The clear uint8 value to encrypt.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint8(uint8 value, address target) internal returns (externalEuint8, bytes memory) {
        return encryptUint8(value, address(this), target);
    }

    /// @notice Encrypts an 8-bit unsigned integer for an explicit user/target pair.
    /// @param value The clear uint8 value to encrypt.
    /// @param user The user embedded in the input proof authorization.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint8(uint8 value, address user, address target) internal returns (externalEuint8, bytes memory) {
        (bytes32 handle, bytes memory inputProof) = _encrypt(value, FheType.Uint8, user, target);
        return (externalEuint8.wrap(handle), inputProof);
    }

    /// @notice Encrypts a 16-bit unsigned integer for the given target contract.
    /// @param value The clear uint16 value to encrypt.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint16(uint16 value, address target) internal returns (externalEuint16, bytes memory) {
        return encryptUint16(value, address(this), target);
    }

    /// @notice Encrypts a 16-bit unsigned integer for an explicit user/target pair.
    /// @param value The clear uint16 value to encrypt.
    /// @param user The user embedded in the input proof authorization.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint16(uint16 value, address user, address target)
        internal
        returns (externalEuint16, bytes memory)
    {
        (bytes32 handle, bytes memory inputProof) = _encrypt(value, FheType.Uint16, user, target);
        return (externalEuint16.wrap(handle), inputProof);
    }

    /// @notice Encrypts a 32-bit unsigned integer for the given target contract.
    /// @param value The clear uint32 value to encrypt.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint32(uint32 value, address target) internal returns (externalEuint32, bytes memory) {
        return encryptUint32(value, address(this), target);
    }

    /// @notice Encrypts a 32-bit unsigned integer for an explicit user/target pair.
    /// @param value The clear uint32 value to encrypt.
    /// @param user The user embedded in the input proof authorization.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint32(uint32 value, address user, address target)
        internal
        returns (externalEuint32, bytes memory)
    {
        (bytes32 handle, bytes memory inputProof) = _encrypt(value, FheType.Uint32, user, target);
        return (externalEuint32.wrap(handle), inputProof);
    }

    /// @notice Encrypts a 64-bit unsigned integer for the given target contract.
    /// @param value The clear uint64 value to encrypt.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint64(uint64 value, address target) internal returns (externalEuint64, bytes memory) {
        return encryptUint64(value, address(this), target);
    }

    /// @notice Encrypts a 64-bit unsigned integer for an explicit user/target pair.
    /// @param value The clear uint64 value to encrypt.
    /// @param user The user embedded in the input proof authorization.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint64(uint64 value, address user, address target)
        internal
        returns (externalEuint64, bytes memory)
    {
        (bytes32 handle, bytes memory inputProof) = _encrypt(value, FheType.Uint64, user, target);
        return (externalEuint64.wrap(handle), inputProof);
    }

    /// @notice Encrypts a 128-bit unsigned integer for the given target contract.
    /// @param value The clear uint128 value to encrypt.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint128(uint128 value, address target) internal returns (externalEuint128, bytes memory) {
        return encryptUint128(value, address(this), target);
    }

    /// @notice Encrypts a 128-bit unsigned integer for an explicit user/target pair.
    /// @param value The clear uint128 value to encrypt.
    /// @param user The user embedded in the input proof authorization.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint128(uint128 value, address user, address target)
        internal
        returns (externalEuint128, bytes memory)
    {
        (bytes32 handle, bytes memory inputProof) = _encrypt(value, FheType.Uint128, user, target);
        return (externalEuint128.wrap(handle), inputProof);
    }

    /// @notice Encrypts a 256-bit unsigned integer for the given target contract.
    /// @param value The clear uint256 value to encrypt.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint256(uint256 value, address target) internal returns (externalEuint256, bytes memory) {
        return encryptUint256(value, address(this), target);
    }

    /// @notice Encrypts a 256-bit unsigned integer for an explicit user/target pair.
    /// @param value The clear uint256 value to encrypt.
    /// @param user The user embedded in the input proof authorization.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint256(uint256 value, address user, address target)
        internal
        returns (externalEuint256, bytes memory)
    {
        (bytes32 handle, bytes memory inputProof) = _encrypt(value, FheType.Uint256, user, target);
        return (externalEuint256.wrap(handle), inputProof);
    }

    /// @notice Encrypts an address value for the given target contract.
    /// @param value The clear address value to encrypt.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptAddress(address value, address target) internal returns (externalEaddress, bytes memory) {
        return encryptAddress(value, address(this), target);
    }

    /// @notice Encrypts an address value for an explicit user/target pair.
    /// @param value The clear address value to encrypt.
    /// @param user The user embedded in the input proof authorization.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptAddress(address value, address user, address target)
        internal
        returns (externalEaddress, bytes memory)
    {
        (bytes32 handle, bytes memory inputProof) = _encrypt(uint256(uint160(value)), FheType.Uint160, user, target);
        return (externalEaddress.wrap(handle), inputProof);
    }

    /// @notice Decrypts handles that were marked as publicly decryptable and returns a KMS-style proof.
    /// @param handles The encrypted handles to decrypt.
    /// @return cleartexts The cleartext values in the same order as `handles`.
    /// @return decryptionProof Encoded decryption proof signed by the configured mock KMS signer.
    function publicDecrypt(bytes32[] memory handles)
        internal
        returns (uint256[] memory cleartexts, bytes memory decryptionProof)
    {
        _processNewLogs();
        cleartexts = new uint256[](handles.length);
        for (uint256 i = 0; i < handles.length; i++) {
            if (!_acl.isAllowedForDecryption(handles[i])) {
                revert HandleNotAllowedForPublicDecryption(handles[i]);
            }
            cleartexts[i] = _plaintexts[handles[i]];
        }

        bytes memory abiEncodedCleartexts = abi.encode(cleartexts);
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            _kmsVerifier.eip712Domain();
        bytes32 domainSeparator =
            KMSDecryptionProofHelper.computeKMSDecryptionDomainSeparator(name, version, chainId, verifyingContract);
        bytes32 digest = KMSDecryptionProofHelper.computeDecryptionDigest(
            handles, abiEncodedCleartexts, EMPTY_EXTRA_DATA, domainSeparator
        );

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signDigest(MOCK_KMS_SIGNER_PK, digest);
        decryptionProof = KMSDecryptionProofHelper.assembleDecryptionProof(signatures, EMPTY_EXTRA_DATA);
    }

    /// @notice Decrypts a single handle for a user after persistent ACL checks and user signature verification.
    /// @param handle The encrypted handle to decrypt.
    /// @param userAddress The user authorizing this decrypt request.
    /// @param contractAddress The contract context included in the signed request.
    /// @param userSignature EIP-712 signature produced by `signUserDecrypt`.
    /// @return The decrypted cleartext value from the mock executor.
    function userDecrypt(bytes32 handle, address userAddress, address contractAddress, bytes memory userSignature)
        internal
        returns (uint256)
    {
        _processNewLogs();

        if (userAddress == contractAddress) {
            revert UserAddressEqualsContractAddress();
        }

        if (!_acl.persistAllowed(handle, userAddress)) {
            revert UserNotAuthorizedForDecrypt(handle, userAddress);
        }

        if (!_acl.persistAllowed(handle, contractAddress)) {
            revert ContractNotAuthorizedForDecrypt(handle, contractAddress);
        }

        address[] memory contractAddresses = new address[](1);
        contractAddresses[0] = contractAddress;
        bytes32 domainSeparator = UserDecryptHelper.computeUserDecryptDomainSeparator(block.chainid, kmsVerifierAdd);
        bytes32 digest = UserDecryptHelper.computeUserDecryptDigest(
            abi.encodePacked(userAddress),
            contractAddresses,
            block.timestamp,
            DEFAULT_USER_DECRYPT_DURATION_DAYS,
            EMPTY_EXTRA_DATA,
            domainSeparator
        );

        (uint8 v, bytes32 r, bytes32 s) = _decodeSignature(userSignature);
        address recoveredSigner = ecrecover(digest, v, r, s);
        if (recoveredSigner == address(0) || recoveredSigner != userAddress) {
            revert InvalidUserDecryptSignature();
        }

        return _plaintexts[handle];
    }

    /// @notice Reads a cleartext value by handle from the local plaintext database.
    function decrypt(bytes32 handle) internal returns (uint256) {
        _processNewLogs();
        return _plaintexts[handle];
    }

    /// @notice Decrypts an encrypted boolean.
    /// @param value The encrypted boolean handle.
    /// @return The decrypted boolean.
    function decrypt(ebool value) internal returns (bool) {
        return decrypt(ebool.unwrap(value)) != 0;
    }

    /// @notice Decrypts an encrypted 8-bit unsigned integer.
    /// @param value The encrypted uint8 handle.
    /// @return The decrypted uint8 value.
    function decrypt(euint8 value) internal returns (uint8) {
        return uint8(decrypt(euint8.unwrap(value)));
    }

    /// @notice Decrypts an encrypted 16-bit unsigned integer.
    /// @param value The encrypted uint16 handle.
    /// @return The decrypted uint16 value.
    function decrypt(euint16 value) internal returns (uint16) {
        return uint16(decrypt(euint16.unwrap(value)));
    }

    /// @notice Decrypts an encrypted 32-bit unsigned integer.
    /// @param value The encrypted uint32 handle.
    /// @return The decrypted uint32 value.
    function decrypt(euint32 value) internal returns (uint32) {
        return uint32(decrypt(euint32.unwrap(value)));
    }

    /// @notice Decrypts an encrypted 64-bit unsigned integer.
    /// @param value The encrypted uint64 handle.
    /// @return The decrypted uint64 value.
    function decrypt(euint64 value) internal returns (uint64) {
        return uint64(decrypt(euint64.unwrap(value)));
    }

    /// @notice Decrypts an encrypted 128-bit unsigned integer.
    /// @param value The encrypted uint128 handle.
    /// @return The decrypted uint128 value.
    function decrypt(euint128 value) internal returns (uint128) {
        return uint128(decrypt(euint128.unwrap(value)));
    }

    /// @notice Decrypts an encrypted 256-bit unsigned integer.
    /// @param value The encrypted uint256 handle.
    /// @return The decrypted uint256 value.
    function decrypt(euint256 value) internal returns (uint256) {
        return decrypt(euint256.unwrap(value));
    }

    /// @notice Decrypts an encrypted address.
    /// @param value The encrypted address handle.
    /// @return The decrypted address.
    function decrypt(eaddress value) internal returns (address) {
        return address(uint160(decrypt(eaddress.unwrap(value))));
    }

    /// @notice Builds a KMS-signed decryption proof for callback-style decryption flows.
    /// @dev Unlike `publicDecrypt`, this does NOT check ACL permissions. Use it when the contract
    ///      under test expects `(cleartext, proof)` callback arguments rather than on-chain decryption.
    /// @param handles The encrypted handles being decrypted.
    /// @param abiEncodedCleartexts ABI-encoded cleartext values matching the on-chain verification encoding.
    /// @return proof The assembled decryption proof bytes.
    function buildDecryptionProof(bytes32[] memory handles, bytes memory abiEncodedCleartexts)
        internal
        view
        returns (bytes memory proof)
    {
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            _kmsVerifier.eip712Domain();
        bytes32 domainSeparator =
            KMSDecryptionProofHelper.computeKMSDecryptionDomainSeparator(name, version, chainId, verifyingContract);
        bytes32 digest = KMSDecryptionProofHelper.computeDecryptionDigest(
            handles, abiEncodedCleartexts, EMPTY_EXTRA_DATA, domainSeparator
        );

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signDigest(MOCK_KMS_SIGNER_PK, digest);
        proof = KMSDecryptionProofHelper.assembleDecryptionProof(signatures, EMPTY_EXTRA_DATA);
    }

    /// @notice Builds a KMS-signed decryption proof for a single handle.
    /// @param handle The encrypted handle being decrypted.
    /// @param abiEncodedCleartext ABI-encoded cleartext value matching the on-chain verification encoding.
    /// @return proof The assembled decryption proof bytes.
    function buildDecryptionProof(bytes32 handle, bytes memory abiEncodedCleartext)
        internal
        view
        returns (bytes memory proof)
    {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = handle;
        proof = buildDecryptionProof(handles, abiEncodedCleartext);
    }

    /// @notice Signs a default user decrypt request for a single contract using current block timestamp.
    /// @param userPk Private key used for EIP-712 signing.
    /// @param contractAddress The single contract allowed by the signed request.
    /// @return signature `r || s || v` encoded signature bytes.
    function signUserDecrypt(uint256 userPk, address contractAddress) internal view returns (bytes memory signature) {
        address[] memory contractAddresses = new address[](1);
        contractAddresses[0] = contractAddress;
        return signUserDecrypt(userPk, contractAddresses, block.timestamp, DEFAULT_USER_DECRYPT_DURATION_DAYS);
    }

    /// @notice Signs a custom user decrypt request.
    /// @param userPk Private key used for EIP-712 signing.
    /// @param contractAddresses Allowlisted contracts embedded in the request digest.
    /// @param startTimestamp Start time embedded in the request digest.
    /// @param durationDays Duration (in days) embedded in the request digest.
    /// @return signature `r || s || v` encoded signature bytes.
    function signUserDecrypt(
        uint256 userPk,
        address[] memory contractAddresses,
        uint256 startTimestamp,
        uint256 durationDays
    ) internal view returns (bytes memory signature) {
        address userAddress = vm.addr(userPk);
        bytes32 domainSeparator = UserDecryptHelper.computeUserDecryptDomainSeparator(block.chainid, kmsVerifierAdd);
        bytes32 digest = UserDecryptHelper.computeUserDecryptDigest(
            abi.encodePacked(userAddress),
            contractAddresses,
            startTimestamp,
            durationDays,
            EMPTY_EXTRA_DATA,
            domainSeparator
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _deployAllContracts() internal {
        _deployPauserSet();
        _deployACL();
        _deployHCULimit();
        _deployRealExecutor();
        _deployInputVerifier();
        _deployKMSVerifier();

        _executor = FHEVMExecutor(fhevmExecutorAdd);
        _acl = ACL(aclAdd);
        _inputVerifier = InputVerifier(inputVerifierAdd);
        _kmsVerifier = KMSVerifier(kmsVerifierAdd);
    }

    function _deployPauserSet() internal {
        vm.etch(pauserSetAdd, address(new PauserSet()).code);
    }

    function _deployACL() internal {
        address emptyProxyAclImpl = address(new EmptyUUPSProxyACL());

        deployCodeTo(
            ERC1967_PROXY_ARTIFACT,
            abi.encode(emptyProxyAclImpl, abi.encodeCall(EmptyUUPSProxyACL.initialize, (PROXY_OWNER))),
            aclAdd
        );

        address aclImpl = address(new ACL());
        vm.prank(PROXY_OWNER);
        EmptyUUPSProxyACL(aclAdd).upgradeToAndCall(aclImpl, abi.encodeCall(ACL.initializeFromEmptyProxy, ()));
    }

    function _deployHCULimit() internal {
        address emptyProxyImpl = address(new EmptyUUPSProxy());

        deployCodeTo(
            ERC1967_PROXY_ARTIFACT,
            abi.encode(emptyProxyImpl, abi.encodeCall(EmptyUUPSProxy.initialize, ())),
            hcuLimitAdd
        );

        address hcuLimitImpl = address(new HCULimit());
        vm.prank(PROXY_OWNER);
        EmptyUUPSProxy(hcuLimitAdd)
            .upgradeToAndCall(
                hcuLimitImpl, abi.encodeCall(HCULimit.initializeFromEmptyProxy, (20_000_000, 5_000_000, 20_000_000))
            );
    }

    function _deployRealExecutor() internal {
        address emptyProxyImpl = address(new EmptyUUPSProxy());

        deployCodeTo(
            ERC1967_PROXY_ARTIFACT,
            abi.encode(emptyProxyImpl, abi.encodeCall(EmptyUUPSProxy.initialize, ())),
            fhevmExecutorAdd
        );

        address executorImpl = address(new FHEVMExecutor());
        vm.prank(PROXY_OWNER);
        EmptyUUPSProxy(fhevmExecutorAdd)
            .upgradeToAndCall(executorImpl, abi.encodeCall(FHEVMExecutor.initializeFromEmptyProxy, ()));
    }

    function _deployInputVerifier() internal {
        address emptyProxyImpl = address(new EmptyUUPSProxy());

        deployCodeTo(
            ERC1967_PROXY_ARTIFACT,
            abi.encode(emptyProxyImpl, abi.encodeCall(EmptyUUPSProxy.initialize, ())),
            inputVerifierAdd
        );

        address inputVerifierImpl = address(new InputVerifier());
        address[] memory signers = new address[](1);
        signers[0] = mockInputSigner;

        vm.prank(PROXY_OWNER);
        EmptyUUPSProxy(inputVerifierAdd)
            .upgradeToAndCall(
                inputVerifierImpl,
                abi.encodeCall(
                    InputVerifier.initializeFromEmptyProxy, (inputVerifierAdd, uint64(block.chainid), signers, 1)
                )
            );
    }

    function _deployKMSVerifier() internal {
        address emptyProxyImpl = address(new EmptyUUPSProxy());

        deployCodeTo(
            ERC1967_PROXY_ARTIFACT,
            abi.encode(emptyProxyImpl, abi.encodeCall(EmptyUUPSProxy.initialize, ())),
            kmsVerifierAdd
        );

        address kmsVerifierImpl = address(new KMSVerifier());
        address[] memory signers = new address[](1);
        signers[0] = mockKmsSigner;

        vm.prank(PROXY_OWNER);
        EmptyUUPSProxy(kmsVerifierAdd)
            .upgradeToAndCall(
                kmsVerifierImpl,
                abi.encodeCall(
                    KMSVerifier.initializeFromEmptyProxy, (kmsVerifierAdd, uint64(block.chainid), signers, 1)
                )
            );
    }

    function _encrypt(uint256 value, FheType fheType, address user, address target)
        internal
        returns (bytes32 handle, bytes memory inputProof)
    {
        _encryptNonce += 1;

        bytes memory ciphertext = abi.encodePacked(keccak256(abi.encodePacked(value, uint8(fheType), _encryptNonce)));
        handle = InputProofHelper.computeInputHandle(ciphertext, 0, fheType, aclAdd, uint64(block.chainid));

        _plaintexts[handle] = CleartextArithmetic.normalizePlaintextToType(value, uint8(fheType));

        bytes32[] memory handles = new bytes32[](1);
        handles[0] = handle;

        bytes32 domainSeparator = InputProofHelper.computeInputVerifierDomainSeparator(inputVerifierAdd, block.chainid);
        bytes32 digest = InputProofHelper.computeInputVerificationDigest(
            handles, user, target, block.chainid, EMPTY_EXTRA_DATA, domainSeparator
        );

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signDigest(MOCK_INPUT_SIGNER_PK, digest);
        inputProof = InputProofHelper.assembleInputProof(handles, signatures, EMPTY_EXTRA_DATA);
    }

    function _decodeSignature(bytes memory signature) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        if (signature.length != 65) {
            revert InvalidUserDecryptSignature();
        }

        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        if (v < 27) {
            v += 27;
        }
        if (v != 27 && v != 28) {
            revert InvalidUserDecryptSignature();
        }
    }

    function _signDigest(uint256 signerPk, bytes32 digest) internal pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        signature = abi.encodePacked(r, s, v);
    }
}
