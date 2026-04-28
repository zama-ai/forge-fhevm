// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ACL} from "@fhevm/host-contracts/contracts/ACL.sol";
import {FheType} from "@fhevm/host-contracts/contracts/shared/FheType.sol";
import {ACLTestBase} from "./helpers/ACLTestBase.sol";

contract ACLDelegationTest is ACLTestBase {
    event DelegatedForUserDecryption(
        address indexed delegator,
        address indexed delegate,
        address contractAddress,
        uint64 delegationCounter,
        uint64 oldExpirationDate,
        uint64 newExpirationDate
    );

    address internal constant DAPP = address(0xCA11AB1E);

    function setUp() public {
        _deployExecutorStack();
    }

    function test_delegate_revertsWhenPaused() public {
        _mockPauserSetIsPauser(address(this), true);
        aclContract.pause();

        vm.prank(ALICE);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        aclContract.delegateForUserDecryption(BOB, DAPP, uint64(block.timestamp + 2 hours));
    }

    function test_delegate_revertsWhenExpirationInThePast() public {
        vm.prank(ALICE);
        vm.expectRevert(ACL.ExpirationDateInThePast.selector);
        aclContract.delegateForUserDecryption(BOB, DAPP, uint64(block.timestamp));
    }

    function test_delegate_revertsWhenSenderIsContract() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(ACL.SenderCannotBeContractAddress.selector, ALICE));
        aclContract.delegateForUserDecryption(BOB, ALICE, uint64(block.timestamp + 2 hours));
    }

    function test_delegate_revertsWhenSenderIsDelegate() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(ACL.SenderCannotBeDelegate.selector, ALICE));
        aclContract.delegateForUserDecryption(ALICE, DAPP, uint64(block.timestamp + 2 hours));
    }

    function test_delegate_revertsWhenDelegateIsContract() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(ACL.DelegateCannotBeContractAddress.selector, BOB));
        aclContract.delegateForUserDecryption(BOB, BOB, uint64(block.timestamp + 2 hours));
    }

    function test_delegate_revertsOnDoubleInSameBlock() public {
        uint64 expiry0 = uint64(block.timestamp + 2 hours);
        uint64 expiry1 = uint64(block.timestamp + 3 hours);
        vm.startPrank(ALICE);
        aclContract.delegateForUserDecryption(BOB, DAPP, expiry0);
        vm.expectRevert(
            abi.encodeWithSelector(ACL.AlreadyDelegatedOrRevokedInSameBlock.selector, ALICE, BOB, DAPP, block.number)
        );
        aclContract.delegateForUserDecryption(BOB, DAPP, expiry1);
        vm.stopPrank();
    }

    function test_delegate_revertsOnSameExpiration() public {
        uint64 expiry = uint64(block.timestamp + 2 hours);
        vm.startPrank(ALICE);
        aclContract.delegateForUserDecryption(BOB, DAPP, expiry);
        vm.roll(block.number + 1);
        vm.expectRevert(
            abi.encodeWithSelector(ACL.ExpirationDateAlreadySetToSameValue.selector, ALICE, BOB, DAPP, expiry)
        );
        aclContract.delegateForUserDecryption(BOB, DAPP, expiry);
        vm.stopPrank();
    }

    function test_delegate_storesDelegation() public {
        uint64 expiry = uint64(block.timestamp + 2 hours);
        vm.prank(ALICE);
        aclContract.delegateForUserDecryption(BOB, DAPP, expiry);

        assertEq(aclContract.getUserDecryptionDelegationExpirationDate(ALICE, BOB, DAPP), expiry);
    }

    function test_delegate_emitsEvent() public {
        uint64 expiry = uint64(block.timestamp + 2 hours);
        vm.expectEmit(true, true, false, true, address(aclContract));
        emit DelegatedForUserDecryption(ALICE, BOB, DAPP, 1, 0, expiry);

        vm.prank(ALICE);
        aclContract.delegateForUserDecryption(BOB, DAPP, expiry);
    }

    function test_isDelegated_delegatorNoPermission() public {
        uint64 expiry = uint64(block.timestamp + 2 hours);
        bytes32 handle = _createHandleWithPersistentPermission(99, FheType.Uint16, DAPP);

        vm.prank(ALICE);
        aclContract.delegateForUserDecryption(BOB, DAPP, expiry);

        assertFalse(aclContract.isHandleDelegatedForUserDecryption(ALICE, BOB, DAPP, handle));
    }

    function test_isDelegated_contractNoPermission() public {
        uint64 expiry = uint64(block.timestamp + 2 hours);
        bytes32 handle = _createHandleWithPersistentPermission(99, FheType.Uint16, ALICE);

        vm.prank(ALICE);
        aclContract.delegateForUserDecryption(BOB, DAPP, expiry);

        assertFalse(aclContract.isHandleDelegatedForUserDecryption(ALICE, BOB, DAPP, handle));
    }

    function test_isDelegated_expired() public {
        uint64 expiry = uint64(block.timestamp + 2 hours);
        bytes32 handle = _createHandleTransientOnly(99, FheType.Uint16);
        aclContract.allow(handle, ALICE);
        aclContract.allow(handle, DAPP);

        vm.prank(ALICE);
        aclContract.delegateForUserDecryption(BOB, DAPP, expiry);

        vm.warp(expiry + 1);
        assertFalse(aclContract.isHandleDelegatedForUserDecryption(ALICE, BOB, DAPP, handle));
    }

    function test_isDelegated_allConditionsMet() public {
        uint64 expiry = uint64(block.timestamp + 2 hours);
        bytes32 handle = _createHandleTransientOnly(99, FheType.Uint16);
        aclContract.allow(handle, ALICE);
        aclContract.allow(handle, DAPP);

        vm.prank(ALICE);
        aclContract.delegateForUserDecryption(BOB, DAPP, expiry);

        assertTrue(aclContract.isHandleDelegatedForUserDecryption(ALICE, BOB, DAPP, handle));
    }

    function test_isDelegated_isView() public {
        uint64 expiry = uint64(block.timestamp + 2 hours);
        bytes32 handle = _createHandleTransientOnly(99, FheType.Uint16);
        aclContract.allow(handle, ALICE);
        aclContract.allow(handle, DAPP);

        vm.prank(ALICE);
        aclContract.delegateForUserDecryption(BOB, DAPP, expiry);

        uint64 expirationBefore = aclContract.getUserDecryptionDelegationExpirationDate(ALICE, BOB, DAPP);
        bool delegated = aclContract.isHandleDelegatedForUserDecryption(ALICE, BOB, DAPP, handle);
        uint64 expirationAfter = aclContract.getUserDecryptionDelegationExpirationDate(ALICE, BOB, DAPP);

        assertTrue(delegated);
        assertEq(expirationBefore, expirationAfter);
    }
}
