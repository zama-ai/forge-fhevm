// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ACL} from "@fhevm/host-contracts/contracts/ACL.sol";
import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";
import {fhevmExecutorAdd} from "@fhevm/host-contracts/addresses/FHEVMHostAddresses.sol";
import {ACLTestBase} from "./helpers/ACLTestBase.sol";

contract ACLTest is ACLTestBase {
    event Allowed(address indexed caller, address indexed account, bytes32 handle);
    event AllowedForDecryption(address indexed caller, bytes32[] handlesList);
    event BlockedAccount(address indexed account);
    event UnblockedAccount(address indexed account);

    function setUp() public {
        _deployExecutorStack();
    }

    function test_allow_revertsWhenPaused() public {
        bytes32 handle = _createHandleTransientOnly(11, FheType.Uint8);
        _mockPauserSetIsPauser(address(this), true);
        aclContract.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        aclContract.allow(handle, ALICE);
    }

    function test_allow_revertsWhenSenderDenied() public {
        bytes32 handle = _createHandleTransientOnly(11, FheType.Uint8);

        vm.prank(OWNER);
        aclContract.blockAccount(address(this));

        vm.expectRevert(abi.encodeWithSelector(ACL.SenderDenied.selector, address(this)));
        aclContract.allow(handle, ALICE);
    }

    function test_allow_revertsWhenSenderNotAllowed() public {
        bytes32 handle = _createHandleTransientOnly(10, FheType.Uint8);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(ACL.SenderNotAllowed.selector, ALICE));
        aclContract.allow(handle, BOB);
    }

    function test_allow_setsPersistentPermission() public {
        bytes32 handle = _createHandleTransientOnly(11, FheType.Uint8);
        aclContract.allow(handle, ALICE);

        assertTrue(aclContract.persistAllowed(handle, ALICE));
    }

    function test_allow_emitsAllowedEvent() public {
        bytes32 handle = _createHandleTransientOnly(11, FheType.Uint8);
        vm.expectEmit(true, true, false, true, address(aclContract));
        emit Allowed(address(this), ALICE, handle);
        aclContract.allow(handle, ALICE);
    }

    function test_allow_permissionChain() public {
        bytes32 handle = _createHandleWithPersistentPermission(10, FheType.Uint16, ALICE);

        vm.prank(ALICE);
        aclContract.allow(handle, BOB);

        vm.prank(BOB);
        aclContract.allow(handle, CHARLIE);

        assertTrue(aclContract.persistAllowed(handle, CHARLIE));
    }

    function test_allow_transientSenderCanGrantPersistent() public {
        bytes32 handle = _createHandleTransientOnly(10, FheType.Uint16);
        assertTrue(aclContract.allowedTransient(handle, address(this)));
        assertFalse(aclContract.persistAllowed(handle, address(this)));

        aclContract.allow(handle, ALICE);
        assertTrue(aclContract.persistAllowed(handle, ALICE));
    }

    function test_allowTransient_revertsWhenPaused() public {
        bytes32 handle = _createHandleTransientOnly(10, FheType.Uint8);
        _mockPauserSetIsPauser(address(this), true);
        aclContract.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        aclContract.allowTransient(handle, ALICE);
    }

    function test_allowTransient_executorBypasses() public {
        bytes32 handle = bytes32(uint256(0x1234));
        vm.prank(fhevmExecutorAdd);
        aclContract.allowTransient(handle, ALICE);
        assertTrue(aclContract.allowedTransient(handle, ALICE));
    }

    function test_allowTransient_nonExecutor_revertsWhenDenied() public {
        bytes32 handle = _createHandleTransientOnly(1, FheType.Uint8);
        vm.prank(OWNER);
        aclContract.blockAccount(address(this));

        vm.expectRevert(abi.encodeWithSelector(ACL.SenderDenied.selector, address(this)));
        aclContract.allowTransient(handle, ALICE);
    }

    function test_allowTransient_nonExecutor_revertsWhenNotAllowed() public {
        bytes32 handle = _createHandleTransientOnly(10, FheType.Uint8);
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(ACL.SenderNotAllowed.selector, ALICE));
        aclContract.allowTransient(handle, BOB);
    }

    function test_allowTransient_setsTransientPermission() public {
        bytes32 handle = _createHandleTransientOnly(10, FheType.Uint16);
        aclContract.allowTransient(handle, ALICE);
        assertTrue(aclContract.allowedTransient(handle, ALICE));
    }

    function test_allowTransient_transientOnly() public {
        bytes32 handle = _createHandleTransientOnly(10, FheType.Uint32);
        aclContract.allowTransient(handle, ALICE);
        assertTrue(aclContract.isAllowed(handle, ALICE));
        assertFalse(aclContract.persistAllowed(handle, ALICE));
    }

    function test_isAllowed_persistentOnly() public {
        bytes32 handle = _createHandleWithPersistentPermission(10, FheType.Uint8, ALICE);
        assertTrue(aclContract.isAllowed(handle, ALICE));
    }

    function test_isAllowed_transientOnly() public {
        bytes32 handle = _createHandleTransientOnly(10, FheType.Uint16);
        assertTrue(aclContract.isAllowed(handle, address(this)));
        assertFalse(aclContract.persistAllowed(handle, address(this)));
    }

    function test_isAllowed_both() public {
        bytes32 handle = _createHandleWithPersistentPermission(10, FheType.Uint8, ALICE);
        vm.prank(ALICE);
        aclContract.allowTransient(handle, ALICE);
        assertTrue(aclContract.persistAllowed(handle, ALICE));
        assertTrue(aclContract.allowedTransient(handle, ALICE));
        assertTrue(aclContract.isAllowed(handle, ALICE));
    }

    function test_isAllowed_neither() public {
        bytes32 handle = _createHandleTransientOnly(10, FheType.Uint8);
        assertFalse(aclContract.isAllowed(handle, ALICE));
    }

    function test_isAllowed_isView() public {
        bytes32 handle = _createHandleWithPersistentPermission(10, FheType.Uint8, ALICE);
        bool persistentBefore = aclContract.persistAllowed(handle, ALICE);
        bool transientBefore = aclContract.allowedTransient(handle, ALICE);
        bool allowedFirst = aclContract.isAllowed(handle, ALICE);
        bool allowedSecond = aclContract.isAllowed(handle, ALICE);

        assertTrue(allowedFirst);
        assertEq(allowedFirst, allowedSecond);
        assertEq(aclContract.persistAllowed(handle, ALICE), persistentBefore);
        assertEq(aclContract.allowedTransient(handle, ALICE), transientBefore);
    }

    function test_allowForDecryption_revertsWhenEmpty() public {
        bytes32[] memory handles = new bytes32[](0);
        vm.expectRevert(ACL.HandlesListIsEmpty.selector);
        aclContract.allowForDecryption(handles);
    }

    function test_allowForDecryption_revertsWhenPaused() public {
        bytes32 handle = _createHandleTransientOnly(10, FheType.Uint8);
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = handle;
        _mockPauserSetIsPauser(address(this), true);
        aclContract.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        aclContract.allowForDecryption(handles);
    }

    function test_allowForDecryption_revertsWhenSenderDenied() public {
        bytes32 handle = _createHandleTransientOnly(10, FheType.Uint8);
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = handle;

        vm.prank(OWNER);
        aclContract.blockAccount(address(this));

        vm.expectRevert(abi.encodeWithSelector(ACL.SenderDenied.selector, address(this)));
        aclContract.allowForDecryption(handles);
    }

    function test_allowForDecryption_revertsWhenSenderNotAllowed() public {
        bytes32 handle = _createHandleTransientOnly(10, FheType.Uint8);
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = handle;

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(ACL.SenderNotAllowed.selector, ALICE));
        aclContract.allowForDecryption(handles);
    }

    function test_allowForDecryption_setsFlag() public {
        bytes32 handle = _createHandleTransientOnly(10, FheType.Uint8);
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = handle;
        aclContract.allowForDecryption(handles);

        assertTrue(aclContract.isAllowedForDecryption(handle));
    }

    function test_allowForDecryption_emitsEvent() public {
        bytes32 handle = _createHandleTransientOnly(10, FheType.Uint8);
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = handle;

        vm.expectEmit(true, false, false, true, address(aclContract));
        emit AllowedForDecryption(address(this), handles);
        aclContract.allowForDecryption(handles);
    }

    function test_allowForDecryption_multipleHandles() public {
        bytes32 h0 = _createHandleTransientOnly(1, FheType.Uint8);
        bytes32 h1 = _createHandleTransientOnly(2, FheType.Uint16);
        bytes32 h2 = _createHandleTransientOnly(3, FheType.Uint32);
        bytes32[] memory handles = new bytes32[](3);
        handles[0] = h0;
        handles[1] = h1;
        handles[2] = h2;
        aclContract.allowForDecryption(handles);

        assertTrue(aclContract.isAllowedForDecryption(h0));
        assertTrue(aclContract.isAllowedForDecryption(h1));
        assertTrue(aclContract.isAllowedForDecryption(h2));
    }

    function test_allowForDecryption_revertsOnPartialPermission() public {
        bytes32 allowedHandle = _createHandleTransientOnly(10, FheType.Uint8);

        vm.prank(ALICE);
        bytes32 disallowedHandle = executor.trivialEncrypt(11, FheType.Uint8);

        bytes32[] memory handles = new bytes32[](2);
        handles[0] = allowedHandle;
        handles[1] = disallowedHandle;

        vm.expectRevert(abi.encodeWithSelector(ACL.SenderNotAllowed.selector, address(this)));
        aclContract.allowForDecryption(handles);
        assertFalse(aclContract.isAllowedForDecryption(allowedHandle));
    }

    function test_isAllowedForDecryption_markedHandle() public {
        bytes32 handle = _createHandleTransientOnly(10, FheType.Uint8);
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = handle;
        aclContract.allowForDecryption(handles);

        assertTrue(aclContract.isAllowedForDecryption(handle));
    }

    function test_isAllowedForDecryption_unmarkedHandle() public {
        bytes32 handle = _createHandleTransientOnly(10, FheType.Uint8);
        assertFalse(aclContract.isAllowedForDecryption(handle));
    }

    function test_isAllowedForDecryption_isView() public {
        bytes32 handle = _createHandleTransientOnly(10, FheType.Uint8);
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = handle;
        aclContract.allowForDecryption(handles);

        bool markedFirst = aclContract.isAllowedForDecryption(handle);
        bool markedSecond = aclContract.isAllowedForDecryption(handle);
        assertTrue(markedFirst);
        assertEq(markedFirst, markedSecond);
    }

    function test_multicall_innerRevertPropagates() public {
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(ACL.getVersion, ());
        calls[1] = abi.encodeCall(ACL.allowForDecryption, (new bytes32[](0)));

        vm.expectRevert(ACL.HandlesListIsEmpty.selector);
        aclContract.multicall(calls);
    }

    function test_multicall_allSucceed() public {
        bytes32 h0 = _createHandleTransientOnly(10, FheType.Uint8);
        bytes32 h1 = _createHandleTransientOnly(11, FheType.Uint8);
        bytes32[] memory handles = new bytes32[](2);
        handles[0] = h0;
        handles[1] = h1;

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(ACL.allowForDecryption, (handles));
        calls[1] = abi.encodeCall(ACL.isAllowedForDecryption, (h1));

        bytes[] memory results = aclContract.multicall(calls);
        assertEq(results.length, 2);
        assertTrue(abi.decode(results[1], (bool)));
        assertTrue(aclContract.isAllowedForDecryption(h0));
        assertTrue(aclContract.isAllowedForDecryption(h1));
    }

    function test_multicall_executionOrder() public {
        vm.prank(OWNER);
        bytes32 handle = executor.trivialEncrypt(10, FheType.Uint8);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(ACL.blockAccount, (OWNER));
        calls[1] = abi.encodeCall(ACL.allow, (handle, ALICE));

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(ACL.SenderDenied.selector, OWNER));
        aclContract.multicall(calls);
    }

    function test_blockAccount_onlyOwner() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, ALICE));
        aclContract.blockAccount(BOB);
    }

    function test_blockAccount_success() public {
        vm.expectEmit(true, false, false, true, address(aclContract));
        emit BlockedAccount(ALICE);

        vm.prank(OWNER);
        aclContract.blockAccount(ALICE);
        assertTrue(aclContract.isAccountDenied(ALICE));
    }

    function test_blockAccount_alreadyBlocked() public {
        vm.startPrank(OWNER);
        aclContract.blockAccount(ALICE);
        vm.expectRevert(abi.encodeWithSelector(ACL.AccountAlreadyBlocked.selector, ALICE));
        aclContract.blockAccount(ALICE);
        vm.stopPrank();
    }

    function test_unblockAccount_onlyOwner() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, ALICE));
        aclContract.unblockAccount(BOB);
    }

    function test_unblockAccount_success() public {
        vm.prank(OWNER);
        aclContract.blockAccount(ALICE);

        vm.expectEmit(true, false, false, true, address(aclContract));
        emit UnblockedAccount(ALICE);

        vm.prank(OWNER);
        aclContract.unblockAccount(ALICE);
        assertFalse(aclContract.isAccountDenied(ALICE));
    }

    function test_unblockAccount_notBlocked() public {
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(ACL.AccountNotBlocked.selector, ALICE));
        aclContract.unblockAccount(ALICE);
    }

    function test_pause_requiresPauser() public {
        vm.expectRevert(abi.encodeWithSelector(ACL.NotPauser.selector, address(this)));
        aclContract.pause();
    }

    function test_pause_success() public {
        _mockPauserSetIsPauser(ALICE, true);
        vm.prank(ALICE);
        aclContract.pause();
        assertTrue(aclContract.paused());
    }

    function test_unpause_onlyOwner() public {
        _mockPauserSetIsPauser(ALICE, true);
        vm.prank(ALICE);
        aclContract.pause();

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, ALICE));
        aclContract.unpause();
    }

    function test_unpause_success() public {
        _mockPauserSetIsPauser(ALICE, true);
        vm.prank(ALICE);
        aclContract.pause();

        vm.prank(OWNER);
        aclContract.unpause();
        assertFalse(aclContract.paused());
    }

    function test_persistAllowed_transientAndPersistentDistinction() public {
        bytes32 handle = _createHandleTransientOnly(77, FheType.Uint32);
        assertTrue(aclContract.isAllowed(handle, address(this)));
        assertFalse(aclContract.persistAllowed(handle, address(this)));
    }

    function test_persistAllowed_userDecryptRequiresPersistent() public {
        bytes32 handle = _createHandleTransientOnly(77, FheType.Uint32);
        aclContract.allowTransient(handle, ALICE);

        assertTrue(aclContract.isAllowed(handle, ALICE));
        assertFalse(aclContract.persistAllowed(handle, ALICE));
    }
}
