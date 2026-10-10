pragma solidity 0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TripFundFixture} from "./TripFundFixture.sol";
import {FailingToken} from "./mocks/FailingToken.sol";
import {CallbackToken} from "./mocks/CallbackToken.sol";
import {TripFund} from "../src/TripFund.sol";
import {TripFundV2} from "../src/TripFundV2.sol";

contract TripFundTransfersTest is TripFundFixture {
    function testFalseReturningTransferFromRollsBackContribution() public {
        _assertContributionRollback(FailingToken.Failure.ReturnFalse);
    }

    function testRevertingTransferFromRollsBackContribution() public {
        _assertContributionRollback(FailingToken.Failure.Revert);
    }

    function testFalseReturningTransferRollsBackWithdrawal() public {
        _assertWithdrawalRollback(FailingToken.Failure.ReturnFalse);
    }

    function testRevertingTransferRollsBackWithdrawal() public {
        _assertWithdrawalRollback(FailingToken.Failure.Revert);
    }

    function testFalseReturningTransferRollsBackRefund() public {
        _assertRefundRollback(FailingToken.Failure.ReturnFalse);
    }

    function testRevertingTransferRollsBackRefund() public {
        _assertRefundRollback(FailingToken.Failure.Revert);
    }

    function testContributionUpdatesAccountingBeforeTokenCallAndBlocksReentry() public {
        CallbackToken callbackToken = _useCallbackToken();
        callbackToken.configure(fund, alice, abi.encodeCall(TripFund.contribute, (1)), true);
        _contribute(alice, 20 ether);

        assertEq(callbackToken.observedContribution(), 20 ether);
        assertEq(callbackToken.observedTotalRaised(), 20 ether);
        _assertReentryBlocked(callbackToken);
        _assertAccounting(20 ether, 0, 20 ether);
        assertEq(token.balanceOf(address(fund)), 20 ether);
    }

    function testWithdrawalMarksPaidBeforeTokenCallAndBlocksReentry() public {
        CallbackToken callbackToken = _useCallbackToken();
        organizer = address(callbackToken);
        fund = _deploy(address(token), organizer, GOAL, deadline);
        _contribute(alice, GOAL);
        callbackToken.configure(fund, alice, abi.encodeCall(TripFund.withdraw, ()), false);
        vm.warp(deadline);
        vm.prank(organizer);
        fund.withdraw();

        assertTrue(callbackToken.observedWithdrawn());
        assertEq(callbackToken.observedTotalRaised(), GOAL);
        _assertReentryBlocked(callbackToken);
        assertEq(token.balanceOf(organizer), GOAL);
        assertEq(token.balanceOf(address(fund)), 0);
    }

    function testRefundClearsContributionBeforeTokenCallAndBlocksReentry() public {
        CallbackToken callbackToken = _useCallbackToken();
        token.mint(address(callbackToken), 20 ether);
        _contribute(address(callbackToken), 20 ether);
        callbackToken.configure(fund, address(callbackToken), abi.encodeCall(TripFund.refund, ()), false);
        vm.warp(deadline);
        vm.prank(address(callbackToken));
        fund.refund();

        assertEq(callbackToken.observedContribution(), 0);
        assertEq(callbackToken.observedTotalRaised(), 20 ether);
        _assertReentryBlocked(callbackToken);
        assertEq(token.balanceOf(address(callbackToken)), 20 ether);
        assertEq(token.balanceOf(address(fund)), 0);
    }

    function testContributeForSharesGuardWithOrdinaryContribution() public {
        CallbackToken callbackToken = _useCallbackToken();
        proxyAdmin = ProxyAdmin(address(uint160(uint256(vm.load(address(fund), ADMIN_SLOT)))));
        TripFundV2 upgradedFund = _upgrade();
        callbackToken.configure(fund, bob, abi.encodeCall(TripFund.contribute, (1)), true);
        vm.startPrank(alice);
        token.approve(address(fund), 20 ether);
        upgradedFund.contributeFor(bob, 20 ether);
        vm.stopPrank();

        assertEq(callbackToken.observedContribution(), 20 ether);
        assertEq(callbackToken.observedTotalRaised(), 20 ether);
        _assertReentryBlocked(callbackToken);
        _assertAccounting(0, 20 ether, 20 ether);
        assertEq(token.balanceOf(address(fund)), 20 ether);
    }

    function _useFailingToken() internal returns (FailingToken failingToken) {
        failingToken = new FailingToken();
        token = failingToken;
        fund = _deploy(address(token), organizer, GOAL, deadline);
        _fundActors(token);
    }

    function _useCallbackToken() internal returns (CallbackToken callbackToken) {
        callbackToken = new CallbackToken();
        token = callbackToken;
        fund = _deploy(address(token), organizer, GOAL, deadline);
        _fundActors(token);
    }

    function _expectTransferFailure(FailingToken.Failure failure) internal {
        if (failure == FailingToken.Failure.ReturnFalse) {
            vm.expectRevert(
                abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token))
            );
        } else {
            vm.expectRevert(FailingToken.TransferRejected.selector);
        }
    }

    function _assertContributionRollback(FailingToken.Failure failure) internal {
        FailingToken failingToken = _useFailingToken();
        _contribute(alice, 10 ether);
        failingToken.setFailures(failure, FailingToken.Failure.None);
        vm.prank(alice);
        token.approve(address(fund), 20 ether);

        _expectTransferFailure(failure);
        vm.prank(alice);
        fund.contribute(20 ether);

        _assertAccounting(10 ether, 0, 10 ether);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 10 ether);
        assertEq(token.balanceOf(address(fund)), 10 ether);
        assertEq(token.allowance(alice, address(fund)), 20 ether);

        failingToken.setFailures(FailingToken.Failure.None, FailingToken.Failure.None);
        vm.prank(alice);
        fund.contribute(20 ether);
        _assertAccounting(30 ether, 0, 30 ether);
    }

    function _assertWithdrawalRollback(FailingToken.Failure failure) internal {
        FailingToken failingToken = _useFailingToken();
        _contribute(alice, GOAL);
        failingToken.setFailures(FailingToken.Failure.None, failure);
        vm.warp(deadline);

        _expectTransferFailure(failure);
        vm.prank(organizer);
        fund.withdraw();

        assertFalse(fund.withdrawn());
        _assertAccounting(GOAL, 0, GOAL);
        assertEq(token.balanceOf(organizer), 0);
        assertEq(token.balanceOf(address(fund)), GOAL);

        failingToken.setFailures(FailingToken.Failure.None, FailingToken.Failure.None);
        vm.prank(organizer);
        fund.withdraw();
        assertTrue(fund.withdrawn());
        assertEq(token.balanceOf(organizer), GOAL);
    }

    function _assertRefundRollback(FailingToken.Failure failure) internal {
        FailingToken failingToken = _useFailingToken();
        _contribute(alice, 20 ether);
        _contribute(bob, 30 ether);
        failingToken.setFailures(FailingToken.Failure.None, failure);
        vm.warp(deadline);

        _expectTransferFailure(failure);
        vm.prank(alice);
        fund.refund();

        _assertAccounting(20 ether, 30 ether, 50 ether);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 20 ether);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE - 30 ether);
        assertEq(token.balanceOf(address(fund)), 50 ether);

        failingToken.setFailures(FailingToken.Failure.None, FailingToken.Failure.None);
        vm.prank(alice);
        fund.refund();
        _assertAccounting(0, 30 ether, 50 ether);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
    }

    function _assertReentryBlocked(CallbackToken callbackToken) internal view {
        assertFalse(callbackToken.callbackSucceeded());
        assertEq(
            callbackToken.callbackResult(),
            abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector)
        );
    }
}
