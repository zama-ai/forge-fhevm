// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {Vm} from "forge-std/Vm.sol";
import {FhevmTest} from "../src/FhevmTest.sol";
import {KMSDecryptionProofHelper} from "../src/KMSDecryptionProofHelper.sol";
import {FoundryERC7984Mock} from "./helpers/FoundryERC7984Mock.sol";

import {FHE, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {fhevmExecutorAdd} from "@fhevm/host-contracts/addresses/FHEVMHostAddresses.sol";
import {IERC7984} from "@openzeppelin/confidential-contracts/interfaces/IERC7984.sol";
import {IERC7984ERC20Wrapper} from "@openzeppelin/confidential-contracts/interfaces/IERC7984ERC20Wrapper.sol";
import {IERC7984Rwa} from "@openzeppelin/confidential-contracts/interfaces/IERC7984Rwa.sol";
import {ERC7984} from "@openzeppelin/confidential-contracts/token/ERC7984/ERC7984.sol";
import {ERC7984ReceiverMock} from "@openzeppelin/confidential-contracts/mocks/token/ERC7984ReceiverMock.sol";

contract ERC7984Test is FhevmTest {
    uint256 internal constant HOLDER_PK = 0xA11CE;
    uint256 internal constant RECIPIENT_PK = 0xB0B;
    uint256 internal constant OPERATOR_PK = 0x0DE;
    uint256 internal constant THIRD_PARTY_PK = 0xCAFE;

    string internal constant NAME = "ConfidentialFungibleToken";
    string internal constant SYMBOL = "CFT";
    string internal constant URI = "https://example.com/metadata";

    FoundryERC7984Mock internal token;
    ERC7984ReceiverMock internal receiver;

    address internal holder;
    address internal recipient;
    address internal operator;
    address internal thirdParty;

    function setUp() public override {
        super.setUp();

        holder = vm.addr(HOLDER_PK);
        recipient = vm.addr(RECIPIENT_PK);
        operator = vm.addr(OPERATOR_PK);
        thirdParty = vm.addr(THIRD_PARTY_PK);

        vm.prank(holder);
        token = new FoundryERC7984Mock(NAME, SYMBOL, URI);
        receiver = new ERC7984ReceiverMock();

        _mintWithInput(holder, holder, 1000);
    }

    function test_constructor_setsName() public view {
        assertEq(token.name(), NAME);
    }

    function test_constructor_setsSymbol() public view {
        assertEq(token.symbol(), SYMBOL);
    }

    function test_constructor_setsContractURI() public view {
        assertEq(token.contractURI(), URI);
    }

    function test_constructor_decimalsIs6() public view {
        assertEq(token.decimals(), 6);
    }

    function test_erc165_supportsERC7984Interface() public view {
        assertTrue(token.supportsInterface(type(IERC7984).interfaceId));
    }

    function test_erc165_doesNotSupportERC7984ERC20Wrapper() public view {
        assertFalse(token.supportsInterface(type(IERC7984ERC20Wrapper).interfaceId));
    }

    function test_erc165_doesNotSupportERC7984RWA() public view {
        assertFalse(token.supportsInterface(type(IERC7984Rwa).interfaceId));
    }

    function test_erc165_doesNotSupportInvalidInterfaceId() public view {
        assertFalse(token.supportsInterface(0xffffffff));
    }

    function test_confidentialBalanceOf_ownerCanDecrypt() public {
        assertEq(_decryptBalance(HOLDER_PK, holder), 1000);
    }

    function test_confidentialBalanceOf_nonOwnerCannotDecrypt() public {
        euint64 balance = token.confidentialBalanceOf(holder);
        bytes32 handle = euint64.unwrap(balance);
        bytes memory signature = signUserDecrypt(THIRD_PARTY_PK, address(token));

        vm.expectRevert(abi.encodeWithSelector(FhevmTest.UserNotAuthorizedForDecrypt.selector, handle, thirdParty));
        this.callUserDecrypt(handle, thirdParty, address(token), signature);
    }

    function test_confidentialTotalSupply_initialOwnerCanDecrypt() public {
        assertEq(_decryptTotalSupply(HOLDER_PK), 1000);
    }

    function test_confidentialTotalSupply_nonOwnerCannotDecrypt() public {
        bytes32 handle = euint64.unwrap(token.confidentialTotalSupply());
        bytes memory signature = signUserDecrypt(THIRD_PARTY_PK, address(token));

        vm.expectRevert(abi.encodeWithSelector(FhevmTest.UserNotAuthorizedForDecrypt.selector, handle, thirdParty));
        this.callUserDecrypt(handle, thirdParty, address(token), signature);
    }

    function test_mint_toNewUser() public {
        _mintWithInput(holder, recipient, 1000);

        assertEq(_decryptBalance(RECIPIENT_PK, recipient), 1000);
        assertEq(_decryptTotalSupply(HOLDER_PK), 2000);
    }

    function test_mint_toExistingUser() public {
        _mintWithInput(holder, holder, 1000);

        assertEq(_decryptBalance(HOLDER_PK, holder), 2000);
        assertEq(_decryptTotalSupply(HOLDER_PK), 2000);
    }

    function testFuzz_mint_toExistingUser(uint64 amount) public {
        vm.assume(amount <= type(uint64).max - 1000);
        _mintWithInput(holder, holder, amount);

        assertEq(_decryptBalance(HOLDER_PK, holder), uint256(1000) + amount);
        assertEq(_decryptTotalSupply(HOLDER_PK), uint256(1000) + amount);
    }

    function test_mint_revertsOnZeroAddress() public {
        (externalEuint64 amount, bytes memory proof) = encryptUint64(400, holder, address(token));

        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(ERC7984.ERC7984InvalidReceiver.selector, address(0)));
        token.$_mint(address(0), amount, proof);
    }

    function test_burn_withSufficientBalance() public {
        _burnWithInput(holder, holder, 400);

        assertEq(_decryptBalance(HOLDER_PK, holder), 600);
        assertEq(_decryptTotalSupply(HOLDER_PK), 600);
    }

    function test_burn_withInsufficientBalance() public {
        _burnWithInput(holder, holder, 1100);

        assertEq(_decryptBalance(HOLDER_PK, holder), 1000);
        assertEq(_decryptTotalSupply(HOLDER_PK), 1000);
    }

    function testFuzz_burn_amount(uint64 amount) public {
        _burnWithInput(holder, holder, amount);

        uint256 expected = amount <= 1000 ? uint256(1000) - amount : 1000;
        assertEq(_decryptBalance(HOLDER_PK, holder), expected);
        assertEq(_decryptTotalSupply(HOLDER_PK), expected);
    }

    function test_burn_revertsOnZeroAddress() public {
        (externalEuint64 amount, bytes memory proof) = encryptUint64(400, holder, address(token));

        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(ERC7984.ERC7984InvalidSender.selector, address(0)));
        token.$_burn(address(0), amount, proof);
    }

    function test_transfer_asSender_sufficientBalance() public {
        _transferWithInput(holder, holder, recipient, 400);

        assertEq(_decryptBalance(HOLDER_PK, holder), 600);
        assertEq(_decryptBalance(RECIPIENT_PK, recipient), 400);
    }

    function test_transfer_asSender_insufficientBalance() public {
        _transferWithInput(holder, holder, recipient, 1100);

        assertEq(_decryptBalance(HOLDER_PK, holder), 1000);
        assertEq(_decryptBalance(RECIPIENT_PK, recipient), 0);
    }

    function testFuzz_transfer_asSender_amount(uint64 amount) public {
        _transferWithInput(holder, holder, recipient, amount);

        uint256 expectedHolderBalance = amount <= 1000 ? uint256(1000) - amount : 1000;
        uint256 expectedRecipientBalance = amount <= 1000 ? amount : 0;
        assertEq(_decryptBalance(HOLDER_PK, holder), expectedHolderBalance);
        assertEq(_decryptBalance(RECIPIENT_PK, recipient), expectedRecipientBalance);
    }

    function test_transfer_asSender_revertsNoBalance() public {
        (externalEuint64 amount, bytes memory proof) = encryptUint64(100, recipient, address(token));

        vm.prank(recipient);
        vm.expectRevert(abi.encodeWithSelector(ERC7984.ERC7984ZeroBalance.selector, recipient));
        token.confidentialTransfer(holder, amount, proof);
    }

    function test_transfer_asSender_revertsToZeroAddress() public {
        (externalEuint64 amount, bytes memory proof) = encryptUint64(100, holder, address(token));

        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(ERC7984.ERC7984InvalidReceiver.selector, address(0)));
        token.confidentialTransfer(address(0), amount, proof);
    }

    function test_transferFrom_asOperator_revertsWithoutApproval() public {
        (externalEuint64 amount, bytes memory proof) = encryptUint64(100, operator, address(token));

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(ERC7984.ERC7984UnauthorizedSpender.selector, holder, operator));
        token.confidentialTransferFrom(holder, recipient, amount, proof);
    }

    function test_isOperator_selfAlwaysTrue() public view {
        assertTrue(token.isOperator(holder, holder));
        assertTrue(token.isOperator(operator, operator));
    }

    function test_setOperator_emitsEventAndEnablesOperator() public {
        uint48 until = uint48(block.timestamp + 100);

        vm.expectEmit(address(token));
        emit IERC7984.OperatorSet(holder, operator, until);

        vm.prank(holder);
        token.setOperator(operator, until);

        assertTrue(token.isOperator(holder, operator));
    }

    function test_isOperator_respectsExpiryWindow() public {
        uint48 until = uint48(block.timestamp + 100);

        vm.prank(holder);
        token.setOperator(operator, until);

        vm.warp(until);
        assertTrue(token.isOperator(holder, operator));

        vm.warp(until + 1);
        assertFalse(token.isOperator(holder, operator));
    }

    function test_transferFrom_asOperator_succeeds() public {
        _setOperatorApproval();

        (externalEuint64 amount, bytes memory proof) = encryptUint64(100, operator, address(token));
        vm.prank(operator);
        token.confidentialTransferFrom(holder, recipient, amount, proof);
    }

    function test_transferFrom_asOperator_sufficientBalance() public {
        _setOperatorApproval();

        (externalEuint64 amount, bytes memory proof) = encryptUint64(400, operator, address(token));
        vm.prank(operator);
        token.confidentialTransferFrom(holder, recipient, amount, proof);

        assertEq(_decryptBalance(HOLDER_PK, holder), 600);
        assertEq(_decryptBalance(RECIPIENT_PK, recipient), 400);
    }

    function test_transferFrom_asOperator_insufficientBalance() public {
        _setOperatorApproval();

        (externalEuint64 amount, bytes memory proof) = encryptUint64(1100, operator, address(token));
        vm.prank(operator);
        token.confidentialTransferFrom(holder, recipient, amount, proof);

        assertEq(_decryptBalance(HOLDER_PK, holder), 1000);
        assertEq(_decryptBalance(RECIPIENT_PK, recipient), 0);
    }

    function test_transferFromAndCall_asOperator_revertsWithoutApproval() public {
        (externalEuint64 amount, bytes memory proof) = encryptUint64(100, operator, address(token));

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(ERC7984.ERC7984UnauthorizedSpender.selector, holder, operator));
        token.confidentialTransferFromAndCall(holder, recipient, amount, proof, hex"");
    }

    function test_transferFromAndCall_asOperator_succeeds() public {
        _setOperatorApproval();

        (externalEuint64 amount, bytes memory proof) = encryptUint64(100, operator, address(token));
        vm.prank(operator);
        token.confidentialTransferFromAndCall(holder, recipient, amount, proof, hex"");
    }

    function test_transferFromAndCall_asOperator_sufficientBalance() public {
        _setOperatorApproval();

        (externalEuint64 amount, bytes memory proof) = encryptUint64(400, operator, address(token));
        vm.prank(operator);
        token.confidentialTransferFromAndCall(holder, recipient, amount, proof, hex"");

        assertEq(_decryptBalance(HOLDER_PK, holder), 600);
        assertEq(_decryptBalance(RECIPIENT_PK, recipient), 400);
    }

    function test_transferFromAndCall_asOperator_insufficientBalance() public {
        _setOperatorApproval();

        (externalEuint64 amount, bytes memory proof) = encryptUint64(1100, operator, address(token));
        vm.prank(operator);
        token.confidentialTransferFromAndCall(holder, recipient, amount, proof, hex"");

        assertEq(_decryptBalance(HOLDER_PK, holder), 1000);
        assertEq(_decryptBalance(RECIPIENT_PK, recipient), 0);
    }

    function test_transferEvent_emitsWithFromToAmount() public {
        _processNewLogs();
        vm.recordLogs();
        _transferWithInput(holder, holder, recipient, 400);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log[] memory tokenLogs = _filterLogsByAddress(logs, address(token));
        assertEq(tokenLogs.length, 1);
        assertEq(address(uint160(uint256(tokenLogs[0].topics[1]))), holder);
        assertEq(address(uint160(uint256(tokenLogs[0].topics[2]))), recipient);
        assertTrue(uint256(tokenLogs[0].topics[3]) != 0);
    }

    function test_transferEvent_senderCanDecryptAmount() public {
        _processNewLogs();
        vm.recordLogs();
        _transferWithInput(holder, holder, recipient, 400);

        euint64 transferAmount = _getTransferAmountHandle(vm.getRecordedLogs());
        assertEq(_decryptHandle(HOLDER_PK, holder, transferAmount), 400);
    }

    function test_transferEvent_recipientCanDecryptAmount() public {
        _processNewLogs();
        vm.recordLogs();
        _transferWithInput(holder, holder, recipient, 400);

        euint64 transferAmount = _getTransferAmountHandle(vm.getRecordedLogs());
        assertEq(_decryptHandle(RECIPIENT_PK, recipient, transferAmount), 400);
    }

    function test_transferEvent_thirdPartyCannotDecryptAmount() public {
        _processNewLogs();
        vm.recordLogs();
        _transferWithInput(holder, holder, recipient, 400);

        euint64 transferAmount = _getTransferAmountHandle(vm.getRecordedLogs());
        bytes32 handle = euint64.unwrap(transferAmount);
        bytes memory signature = signUserDecrypt(THIRD_PARTY_PK, address(token));

        vm.expectRevert(abi.encodeWithSelector(FhevmTest.UserNotAuthorizedForDecrypt.selector, handle, thirdParty));
        this.callUserDecrypt(handle, thirdParty, address(token), signature);
    }

    function test_transferEvent_asOperator_senderCanDecryptAmount() public {
        _setOperatorApproval();
        (externalEuint64 amount, bytes memory proof) = encryptUint64(400, operator, address(token));

        _processNewLogs();
        vm.recordLogs();
        vm.prank(operator);
        token.confidentialTransferFrom(holder, recipient, amount, proof);

        euint64 transferAmount = _getTransferAmountHandle(vm.getRecordedLogs());
        assertEq(_decryptHandle(HOLDER_PK, holder, transferAmount), 400);
    }

    function test_transferEvent_asOperator_recipientCanDecryptAmount() public {
        _setOperatorApproval();
        (externalEuint64 amount, bytes memory proof) = encryptUint64(400, operator, address(token));

        _processNewLogs();
        vm.recordLogs();
        vm.prank(operator);
        token.confidentialTransferFrom(holder, recipient, amount, proof);

        euint64 transferAmount = _getTransferAmountHandle(vm.getRecordedLogs());
        assertEq(_decryptHandle(RECIPIENT_PK, recipient, transferAmount), 400);
    }

    function test_transferEvent_asOperator_thirdPartyCannotDecryptAmount() public {
        _setOperatorApproval();
        (externalEuint64 amount, bytes memory proof) = encryptUint64(400, operator, address(token));

        _processNewLogs();
        vm.recordLogs();
        vm.prank(operator);
        token.confidentialTransferFrom(holder, recipient, amount, proof);

        euint64 transferAmount = _getTransferAmountHandle(vm.getRecordedLogs());
        bytes32 handle = euint64.unwrap(transferAmount);
        bytes memory signature = signUserDecrypt(THIRD_PARTY_PK, address(token));

        vm.expectRevert(abi.encodeWithSelector(FhevmTest.UserNotAuthorizedForDecrypt.selector, handle, thirdParty));
        this.callUserDecrypt(handle, thirdParty, address(token), signature);
    }

    /// @dev External trampoline around internal `userDecrypt` so tests can target reverts via `vm.expectRevert`.
    function callUserDecrypt(bytes32 handle, address user, address contractAddress, bytes memory userSignature)
        external
        returns (uint256)
    {
        return userDecrypt(handle, user, contractAddress, userSignature);
    }

    function test_internalTransfer_revertsFromZeroAddress() public {
        (externalEuint64 amount, bytes memory proof) = encryptUint64(100, holder, address(token));

        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(ERC7984.ERC7984InvalidSender.selector, address(0)));
        token.$_transfer(address(0), recipient, amount, proof);
    }

    function test_transferHandle_fullBalance() public {
        euint64 balanceHandle = token.confidentialBalanceOf(holder);

        vm.prank(holder);
        token.confidentialTransfer(recipient, balanceHandle);

        assertEq(_decryptBalance(RECIPIENT_PK, recipient), 1000);
    }

    function test_transferHandle_otherUserBalance_reverts() public {
        _mintWithInput(holder, recipient, 100);
        euint64 recipientBalance = token.confidentialBalanceOf(recipient);

        vm.prank(holder);
        vm.expectRevert(
            abi.encodeWithSelector(ERC7984.ERC7984UnauthorizedUseOfEncryptedAmount.selector, recipientBalance, holder)
        );
        token.confidentialTransfer(recipient, recipientBalance);
    }

    function test_transferAndCallHandle_fullBalance() public {
        euint64 balanceHandle = token.confidentialBalanceOf(holder);

        vm.prank(holder);
        token.confidentialTransferAndCall(recipient, balanceHandle, hex"");

        assertEq(_decryptBalance(RECIPIENT_PK, recipient), 1000);
    }

    function test_transferAndCallHandle_otherUserBalance_reverts() public {
        _mintWithInput(holder, recipient, 100);
        euint64 recipientBalance = token.confidentialBalanceOf(recipient);

        vm.prank(holder);
        vm.expectRevert(
            abi.encodeWithSelector(ERC7984.ERC7984UnauthorizedUseOfEncryptedAmount.selector, recipientBalance, holder)
        );
        token.confidentialTransferAndCall(recipient, recipientBalance, hex"");
    }

    function test_transferFromHandle_fullBalance() public {
        _setOperatorApproval();

        euint64 holderBalance = token.confidentialBalanceOf(holder);
        _allowHandle(holder, holderBalance, operator);

        vm.prank(operator);
        token.confidentialTransferFrom(holder, recipient, holderBalance);

        assertEq(_decryptBalance(RECIPIENT_PK, recipient), 1000);
    }

    function test_transferFromHandle_otherUserBalance_reverts() public {
        _mintWithInput(holder, recipient, 100);
        euint64 recipientBalance = token.confidentialBalanceOf(recipient);

        vm.prank(holder);
        vm.expectRevert(
            abi.encodeWithSelector(ERC7984.ERC7984UnauthorizedUseOfEncryptedAmount.selector, recipientBalance, holder)
        );
        token.confidentialTransferFrom(holder, recipient, recipientBalance);
    }

    function test_transferFromHandle_revertsWithoutApproval() public {
        _setOperatorApproval();
        vm.prank(holder);
        token.$_setOperator(holder, operator, 0);

        euint64 holderBalance = token.confidentialBalanceOf(holder);
        _allowHandle(holder, holderBalance, operator);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(ERC7984.ERC7984UnauthorizedSpender.selector, holder, operator));
        token.confidentialTransferFrom(holder, recipient, holderBalance);
    }

    function test_transferFromAndCallHandle_fullBalance() public {
        _setOperatorApproval();

        euint64 holderBalance = token.confidentialBalanceOf(holder);
        _allowHandle(holder, holderBalance, operator);

        vm.prank(operator);
        token.confidentialTransferFromAndCall(holder, recipient, holderBalance, hex"");

        assertEq(_decryptBalance(RECIPIENT_PK, recipient), 1000);
    }

    function test_transferFromAndCallHandle_otherUserBalance_reverts() public {
        _mintWithInput(holder, recipient, 100);
        euint64 recipientBalance = token.confidentialBalanceOf(recipient);

        vm.prank(holder);
        vm.expectRevert(
            abi.encodeWithSelector(ERC7984.ERC7984UnauthorizedUseOfEncryptedAmount.selector, recipientBalance, holder)
        );
        token.confidentialTransferFromAndCall(holder, recipient, recipientBalance, hex"");
    }

    function test_transferFromAndCallHandle_revertsWithoutApproval() public {
        _setOperatorApproval();
        vm.prank(holder);
        token.$_setOperator(holder, operator, 0);

        euint64 holderBalance = token.confidentialBalanceOf(holder);
        _allowHandle(holder, holderBalance, operator);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(ERC7984.ERC7984UnauthorizedSpender.selector, holder, operator));
        token.confidentialTransferFromAndCall(holder, recipient, holderBalance, hex"");
    }

    function test_callback_success() public {
        _transferAndCallWithInput(holder, holder, address(receiver), 1000, abi.encode(uint8(1)));

        assertEq(_decryptBalance(HOLDER_PK, holder), 0);
    }

    function test_callback_failure() public {
        _transferAndCallWithInput(holder, holder, address(receiver), 1000, abi.encode(uint8(0)));

        assertEq(_decryptBalance(HOLDER_PK, holder), 1000);
    }

    function test_callback_revertWithoutReason() public {
        (externalEuint64 amount, bytes memory proof) = encryptUint64(1000, holder, address(token));

        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(ERC7984.ERC7984InvalidReceiver.selector, address(receiver)));
        token.confidentialTransferAndCall(address(receiver), amount, proof, hex"");
    }

    function test_callback_customError() public {
        (externalEuint64 amount, bytes memory proof) = encryptUint64(1000, holder, address(token));

        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(ERC7984ReceiverMock.InvalidInput.selector, uint8(2)));
        token.confidentialTransferAndCall(address(receiver), amount, proof, abi.encode(uint8(2)));
    }

    function test_callback_toEOA() public {
        _transferAndCallWithInput(holder, holder, recipient, 1000, hex"");

        assertEq(_decryptBalance(RECIPIENT_PK, recipient), 1000);
    }

    function test_transferWithInput_operatorPath() public {
        _setOperatorApproval();
        _transferWithInput(operator, holder, recipient, 400);

        assertEq(_decryptBalance(HOLDER_PK, holder), 600);
        assertEq(_decryptBalance(RECIPIENT_PK, recipient), 400);
    }

    function test_transferAndCallWithInput_operatorPath() public {
        _setOperatorApproval();
        _transferAndCallWithInput(operator, holder, address(receiver), 1000, abi.encode(uint8(1)));

        assertEq(_decryptBalance(HOLDER_PK, holder), 0);
    }

    function test_callback_events() public {
        _processNewLogs();
        vm.recordLogs();
        _transferAndCallWithInput(holder, holder, address(receiver), 1000, abi.encode(uint8(0)));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _ingestExecutorLogs(logs);
        Vm.Log[] memory tokenLogs = _filterLogsByAddress(logs, address(token));
        assertEq(tokenLogs.length, 2);

        assertEq(address(uint160(uint256(tokenLogs[0].topics[1]))), holder);
        assertEq(address(uint160(uint256(tokenLogs[0].topics[2]))), address(receiver));

        assertEq(address(uint160(uint256(tokenLogs[1].topics[1]))), address(receiver));
        assertEq(address(uint160(uint256(tokenLogs[1].topics[2]))), holder);

        euint64 outbound = euint64.wrap(tokenLogs[0].topics[3]);
        euint64 refund = euint64.wrap(tokenLogs[1].topics[3]);

        assertEq(_decryptHandle(HOLDER_PK, holder, outbound), 1000);
        assertEq(_decryptHandle(HOLDER_PK, holder, refund), 1000);
    }

    function test_disclose_userBalance() public {
        euint64 holderBalance = token.confidentialBalanceOf(holder);

        vm.expectEmit(address(token));
        emit ERC7984.AmountDiscloseRequested(holderBalance, holder);

        vm.prank(holder);
        token.requestDiscloseEncryptedAmount(holderBalance);

        (uint64 cleartext, bytes memory proof) = _publicDecryptForDisclose(holderBalance);

        vm.expectEmit(address(token));
        emit IERC7984.AmountDisclosed(holderBalance, cleartext);

        vm.prank(holder);
        token.discloseEncryptedAmount(holderBalance, cleartext, proof);
    }

    function test_disclose_transactionAmount() public {
        _processNewLogs();
        vm.recordLogs();
        _transferWithInput(holder, holder, recipient, 400);
        euint64 transferAmount = _getTransferAmountHandle(vm.getRecordedLogs());

        vm.expectEmit(address(token));
        emit ERC7984.AmountDiscloseRequested(transferAmount, recipient);

        vm.prank(recipient);
        token.requestDiscloseEncryptedAmount(transferAmount);

        (uint64 cleartext, bytes memory proof) = _publicDecryptForDisclose(transferAmount);

        vm.expectEmit(address(token));
        emit IERC7984.AmountDisclosed(transferAmount, cleartext);

        vm.prank(holder);
        token.discloseEncryptedAmount(transferAmount, cleartext, proof);
    }

    function test_disclose_otherUserBalance_reverts() public {
        euint64 holderBalance = token.confidentialBalanceOf(holder);

        vm.prank(recipient);
        vm.expectRevert(
            abi.encodeWithSelector(ERC7984.ERC7984UnauthorizedUseOfEncryptedAmount.selector, holderBalance, recipient)
        );
        token.requestDiscloseEncryptedAmount(holderBalance);
    }

    function test_disclose_invalidSignature_reverts() public {
        euint64 holderBalance = token.confidentialBalanceOf(holder);

        vm.prank(holder);
        token.requestDiscloseEncryptedAmount(holderBalance);

        vm.prank(holder);
        vm.expectRevert(FHE.EmptyDecryptionProof.selector);
        token.discloseEncryptedAmount(holderBalance, 0, hex"");
    }

    /// @notice Mints `amount` confidential tokens to `to` using an encrypted input generated by `signer`.
    /// @param signer Account used to produce the encrypted input proof.
    /// @param to Recipient address for minted tokens.
    /// @param amount Cleartext amount to encrypt and mint.
    function _mintWithInput(address signer, address to, uint64 amount) internal {
        (externalEuint64 extAmount, bytes memory proof) = encryptUint64(amount, signer, address(token));
        vm.prank(signer);
        token.$_mint(to, extAmount, proof);
    }

    /// @notice Burns `amount` confidential tokens from `from` using an encrypted input generated by `signer`.
    /// @param signer Account used to produce the encrypted input proof.
    /// @param from Account whose balance is reduced.
    /// @param amount Cleartext amount to encrypt and burn.
    function _burnWithInput(address signer, address from, uint64 amount) internal {
        (externalEuint64 extAmount, bytes memory proof) = encryptUint64(amount, signer, address(token));
        vm.prank(signer);
        token.$_burn(from, extAmount, proof);
    }

    /// @notice Executes a confidential transfer using encrypted input, routing to transfer or transferFrom.
    /// @param encryptor Account used to produce the encrypted input proof.
    /// @param from Token sender for the transfer operation.
    /// @param to Token recipient for the transfer operation.
    /// @param amount Cleartext amount to encrypt and transfer.
    function _transferWithInput(address encryptor, address from, address to, uint64 amount) internal {
        (externalEuint64 extAmount, bytes memory proof) = encryptUint64(amount, encryptor, address(token));
        address caller = from == encryptor ? from : encryptor;

        vm.prank(caller);
        if (from == encryptor) {
            token.confidentialTransfer(to, extAmount, proof);
        } else {
            token.confidentialTransferFrom(from, to, extAmount, proof);
        }
    }

    /// @notice Executes a confidential transfer-and-call using encrypted input.
    /// @param signer Account used to produce the encrypted input proof.
    /// @param from Token sender for the transfer operation.
    /// @param to Recipient contract or EOA.
    /// @param amount Cleartext amount to encrypt and transfer.
    /// @param data Callback payload forwarded to the recipient.
    function _transferAndCallWithInput(address signer, address from, address to, uint64 amount, bytes memory data)
        internal
    {
        (externalEuint64 extAmount, bytes memory proof) = encryptUint64(amount, signer, address(token));
        address caller = from == signer ? from : signer;

        vm.prank(caller);
        if (from == signer) {
            token.confidentialTransferAndCall(to, extAmount, proof, data);
        } else {
            token.confidentialTransferFromAndCall(from, to, extAmount, proof, data);
        }
    }

    /// @notice Decrypts the confidential balance of `account` using the provided private key.
    /// @param pk Private key used to sign user decrypt authorization.
    /// @param account Account whose encrypted balance is decrypted.
    /// @return Decrypted `uint64` balance.
    function _decryptBalance(uint256 pk, address account) internal returns (uint64) {
        return _decryptHandle(pk, account, token.confidentialBalanceOf(account));
    }

    /// @notice Decrypts confidential total supply using the provided private key.
    /// @param pk Private key used to sign user decrypt authorization.
    /// @return Decrypted `uint64` total supply.
    function _decryptTotalSupply(uint256 pk) internal returns (uint64) {
        return _decryptHandle(pk, vm.addr(pk), token.confidentialTotalSupply());
    }

    /// @notice Decrypts a specific encrypted handle for `user` with a user-decrypt signature from `pk`.
    /// @param pk Private key used to sign user decrypt authorization.
    /// @param user Authorized user address for decryption.
    /// @param handle Encrypted `euint64` handle to decrypt.
    /// @return Decrypted `uint64` cleartext value.
    function _decryptHandle(uint256 pk, address user, euint64 handle) internal returns (uint64) {
        bytes memory signature = signUserDecrypt(pk, address(token));
        return uint64(userDecrypt(euint64.unwrap(handle), user, address(token), signature));
    }

    function _publicDecryptForDisclose(euint64 handle)
        internal
        returns (uint64 cleartext, bytes memory decryptionProof)
    {
        bytes32 handleRaw = euint64.unwrap(handle);
        if (!_acl.isAllowedForDecryption(handleRaw)) {
            revert HandleNotAllowedForPublicDecryption(handleRaw);
        }

        bytes32[] memory handles = new bytes32[](1);
        handles[0] = handleRaw;

        _processNewLogs();
        cleartext = uint64(_plaintexts[handles[0]]);
        bytes memory cleartextMemory = abi.encode(cleartext);

        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            _kmsVerifier.eip712Domain();
        bytes32 domainSeparator =
            KMSDecryptionProofHelper.computeKMSDecryptionDomainSeparator(name, version, chainId, verifyingContract);
        bytes32 digest = KMSDecryptionProofHelper.computeDecryptionDigest(
            handles, cleartextMemory, EMPTY_EXTRA_DATA, domainSeparator
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(MOCK_KMS_SIGNER_PK, digest);
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = abi.encodePacked(r, s, v);

        decryptionProof = KMSDecryptionProofHelper.assembleDecryptionProof(signatures, EMPTY_EXTRA_DATA);
    }

    function _getTransferAmountHandle(Vm.Log[] memory logs) internal returns (euint64) {
        _ingestExecutorLogs(logs);

        Vm.Log[] memory tokenLogs = _filterLogsByAddress(logs, address(token));
        require(tokenLogs.length > 0, "missing token logs");
        return euint64.wrap(tokenLogs[0].topics[3]);
    }

    function _ingestExecutorLogs(Vm.Log[] memory logs) internal {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == fhevmExecutorAdd) {
                _dispatchFheEvent(logs[i]);
            }
        }
    }

    /// @notice Grants persistent ACL permission on `handle` from `handleOwner` to `to`.
    /// @param handleOwner Current owner authorized to grant ACL access.
    /// @param handle Encrypted handle being shared.
    /// @param to Recipient granted persistent access.
    function _allowHandle(address handleOwner, euint64 handle, address to) internal {
        vm.prank(handleOwner);
        _acl.allow(euint64.unwrap(handle), to);
    }

    /// @notice Sets `operator` as an active operator for `holder` with a short-lived approval window.
    function _setOperatorApproval() internal {
        vm.prank(holder);
        token.setOperator(operator, uint48(block.timestamp + 100));
    }

    function _filterLogsByAddress(Vm.Log[] memory logs, address expected) internal pure returns (Vm.Log[] memory) {
        uint256 count;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == expected) {
                count++;
            }
        }

        Vm.Log[] memory filtered = new Vm.Log[](count);
        uint256 index;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == expected) {
                filtered[index] = logs[i];
                index++;
            }
        }

        return filtered;
    }
}
