pragma solidity 0.8.30;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {TripFundFixture} from "./TripFundFixture.sol";
import {TripFund} from "../src/TripFund.sol";

contract TripFundTest is TripFundFixture {
    function testLocalTokenMetadataAndMinting() public {
        assertEq(token.name(), "Trip Token");
        assertEq(token.symbol(), "TRIP");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 3 * INITIAL_BALANCE);
        token.mint(organizer, 1 ether);
        assertEq(token.balanceOf(organizer), 1 ether);
        assertEq(token.totalSupply(), 3 * INITIAL_BALANCE + 1 ether);
    }

    function testInitializesProxyAtomically() public view {
        assertEq(address(fund.token()), address(token));
        assertEq(fund.organizer(), organizer);
        assertEq(fund.goal(), GOAL);
        assertEq(fund.deadline(), deadline);
        assertEq(fund.totalRaised(), 0);
        assertFalse(fund.withdrawn());
        assertEq(proxyAdmin.owner(), adminOwner);
        assertTrue(address(fund) != address(implementation));
    }

    function testRejectsZeroToken() public {
        vm.expectRevert(TripFund.InvalidAddress.selector);
        _deploy(address(0), organizer, GOAL, deadline);
    }

    function testRejectsZeroOrganizer() public {
        vm.expectRevert(TripFund.InvalidAddress.selector);
        _deploy(address(token), address(0), GOAL, deadline);
    }

    function testRejectsZeroGoal() public {
        vm.expectRevert(TripFund.InvalidGoal.selector);
        _deploy(address(token), organizer, 0, deadline);
    }

    function testRejectsDeadlineAtPresent() public {
        vm.expectRevert(TripFund.InvalidDeadline.selector);
        _deploy(address(token), organizer, GOAL, block.timestamp);
    }

    function testRejectsDeadlineInPast() public {
        vm.expectRevert(TripFund.InvalidDeadline.selector);
        _deploy(address(token), organizer, GOAL, block.timestamp - 1);
    }

    function testRejectsProxyReinitialization() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        fund.initialize(address(token), alice, 1, deadline + 1);
    }

    function testRejectsImplementationInitialization() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(address(token), organizer, GOAL, deadline);
    }

    function testAccumulatesRepeatedContributionsFromTwoParticipants() public {
        _contribute(alice, 20 ether);
        _contribute(bob, 30 ether);
        _contribute(alice, 15 ether);

        _assertAccounting(35 ether, 30 ether, 65 ether);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 35 ether);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE - 30 ether);
        assertEq(token.balanceOf(address(fund)), 65 ether);
    }

    function testContributionEmitsPayerBeneficiaryAndAmount() public {
        vm.prank(alice);
        token.approve(address(fund), 12 ether);
        vm.expectEmit(true, true, false, true, address(fund));
        emit Contribution(alice, alice, 12 ether);
        vm.prank(alice);
        fund.contribute(12 ether);
    }

    function testZeroContributionLeavesAccountingAndBalancesUnchanged() public {
        _contribute(alice, 10 ether);
        vm.prank(alice);
        vm.expectRevert(TripFund.InvalidAmount.selector);
        fund.contribute(0);

        _assertAccounting(10 ether, 0, 10 ether);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 10 ether);
        assertEq(token.balanceOf(address(fund)), 10 ether);
    }

    function testInsufficientBalanceRollsBackContributionAndAllowance() public {
        uint256 amount = INITIAL_BALANCE + 1;
        vm.prank(alice);
        token.approve(address(fund), amount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, INITIAL_BALANCE, amount
            )
        );
        vm.prank(alice);
        fund.contribute(amount);

        _assertAccounting(0, 0, 0);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(fund)), 0);
        assertEq(token.allowance(alice, address(fund)), amount);
    }

    function testInsufficientAllowanceRollsBackContribution() public {
        vm.prank(alice);
        token.approve(address(fund), 9 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(fund), 9 ether, 10 ether
            )
        );
        vm.prank(alice);
        fund.contribute(10 ether);

        _assertAccounting(0, 0, 0);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(fund)), 0);
        assertEq(token.allowance(alice, address(fund)), 9 ether);
    }

    function testApprovingImplementationDoesNotApproveProxy() public {
        vm.prank(alice);
        token.approve(address(implementation), 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(fund), 0, 10 ether
            )
        );
        vm.prank(alice);
        fund.contribute(10 ether);
        _assertAccounting(0, 0, 0);
    }

    function testContributionOneSecondBeforeDeadlineSucceeds() public {
        vm.warp(deadline - 1);
        _contribute(alice, 1 ether);
        _assertAccounting(1 ether, 0, 1 ether);
    }

    function testContributionAtDeadlineReverts() public {
        vm.warp(deadline);
        vm.prank(alice);
        vm.expectRevert(TripFund.FundClosed.selector);
        fund.contribute(1 ether);
        _assertAccounting(0, 0, 0);
    }

    function testContributionAfterDeadlineReverts() public {
        vm.warp(deadline + 1);
        vm.prank(alice);
        vm.expectRevert(TripFund.FundClosed.selector);
        fund.contribute(1 ether);
    }

    function testContributionsContinueAfterGoalIsReachedBeforeDeadline() public {
        _contribute(alice, GOAL);
        _contribute(bob, 5 ether);
        _assertAccounting(GOAL, 5 ether, GOAL + 5 ether);
    }

    function testWithdrawBeforeDeadlineRevertsEvenWhenGoalReached() public {
        _contribute(alice, GOAL);
        vm.warp(deadline - 1);
        vm.prank(organizer);
        vm.expectRevert(TripFund.FundNotClosed.selector);
        fund.withdraw();
        assertFalse(fund.withdrawn());
        assertEq(token.balanceOf(organizer), 0);
        assertEq(token.balanceOf(address(fund)), GOAL);
    }

    function testRefundBeforeDeadlineReverts() public {
        _contribute(alice, 20 ether);
        vm.warp(deadline - 1);
        vm.prank(alice);
        vm.expectRevert(TripFund.FundNotClosed.selector);
        fund.refund();
        _assertAccounting(20 ether, 0, 20 ether);
    }

    function testWithdrawAtDeadlineWhenExactlyGoalReached() public {
        _contribute(alice, 40 ether);
        _contribute(bob, 60 ether);
        vm.warp(deadline);
        vm.expectEmit(true, false, false, true, address(fund));
        emit Withdrawal(organizer, GOAL);
        vm.prank(organizer);
        fund.withdraw();

        assertTrue(fund.withdrawn());
        assertEq(token.balanceOf(organizer), GOAL);
        assertEq(token.balanceOf(address(fund)), 0);
        _assertAccounting(40 ether, 60 ether, GOAL);
    }

    function testWithdrawTransfersFullAccountedAmountAboveGoal() public {
        _contribute(alice, 80 ether);
        _contribute(bob, 70 ether);
        vm.warp(deadline + 1);
        vm.prank(organizer);
        fund.withdraw();
        assertEq(token.balanceOf(organizer), 150 ether);
        assertEq(token.balanceOf(address(fund)), 0);
        _assertAccounting(80 ether, 70 ether, 150 ether);
    }

    function testOnlyOrganizerCanWithdraw() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);
        vm.prank(alice);
        vm.expectRevert(TripFund.Unauthorized.selector);
        fund.withdraw();
        assertFalse(fund.withdrawn());
        assertEq(token.balanceOf(address(fund)), GOAL);
    }

    function testProxyAdminOwnerCannotWithdrawAsOrganizer() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);
        vm.prank(adminOwner);
        vm.expectRevert(TripFund.Unauthorized.selector);
        fund.withdraw();
    }

    function testSecondWithdrawalReverts() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);
        vm.startPrank(organizer);
        fund.withdraw();
        vm.expectRevert(TripFund.AlreadyWithdrawn.selector);
        fund.withdraw();
        vm.stopPrank();
        assertEq(token.balanceOf(organizer), GOAL);
    }

    function testWithdrawOnFailedFundReverts() public {
        _contribute(alice, GOAL - 1);
        vm.warp(deadline);
        vm.prank(organizer);
        vm.expectRevert(TripFund.GoalNotReached.selector);
        fund.withdraw();
        assertFalse(fund.withdrawn());
    }

    function testRefundAtDeadlineReturnsWholeContributionAndEmitsEvent() public {
        _contribute(alice, 10 ether);
        _contribute(alice, 20 ether);
        vm.warp(deadline);
        vm.expectEmit(true, false, false, true, address(fund));
        emit Refund(alice, 30 ether);
        vm.prank(alice);
        fund.refund();
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(fund)), 0);
        _assertAccounting(0, 0, 30 ether);
    }

    function testParticipantsRefundIndependentlyAndTotalRaisedStaysCumulative() public {
        _contribute(alice, 20 ether);
        _contribute(bob, 30 ether);
        vm.warp(deadline);
        vm.prank(bob);
        fund.refund();
        _assertAccounting(20 ether, 0, 50 ether);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 20 ether);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(fund)), 20 ether);

        vm.prank(alice);
        fund.refund();
        _assertAccounting(0, 0, 50 ether);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(fund)), 0);
        assertFalse(fund.withdrawn());
    }

    function testRefundWithoutContributionReverts() public {
        _contribute(alice, 20 ether);
        vm.warp(deadline);
        vm.prank(bob);
        vm.expectRevert(TripFund.NoContribution.selector);
        fund.refund();
        _assertAccounting(20 ether, 0, 20 ether);
    }

    function testSecondRefundReverts() public {
        _contribute(alice, 20 ether);
        vm.warp(deadline);
        vm.startPrank(alice);
        fund.refund();
        vm.expectRevert(TripFund.NoContribution.selector);
        fund.refund();
        vm.stopPrank();
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(fund.totalRaised(), 20 ether);
    }

    function testRefundOnSuccessfulFundReverts() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);
        vm.prank(alice);
        vm.expectRevert(TripFund.GoalReached.selector);
        fund.refund();
        _assertAccounting(GOAL, 0, GOAL);
    }

    function testRefundAfterSuccessfulWithdrawalReverts() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);
        vm.prank(organizer);
        fund.withdraw();
        vm.prank(alice);
        vm.expectRevert(TripFund.GoalReached.selector);
        fund.refund();
    }

    function testDirectDonationStaysAfterSuccessfulWithdrawal() public {
        _contribute(alice, GOAL);
        vm.prank(carol);
        token.transfer(address(fund), 17 ether);
        _assertAccounting(GOAL, 0, GOAL);
        assertEq(fund.contributions(carol), 0);

        vm.warp(deadline);
        vm.prank(organizer);
        fund.withdraw();
        assertEq(token.balanceOf(address(fund)), 17 ether);
        assertEq(token.balanceOf(organizer), GOAL);
        assertEq(fund.totalRaised(), GOAL);
    }

    function testDirectDonationCannotMakeFundSuccessfulAndStaysAfterRefunds() public {
        _contribute(alice, 20 ether);
        _contribute(bob, 30 ether);
        vm.prank(carol);
        token.transfer(address(fund), 100 ether);
        _assertAccounting(20 ether, 30 ether, 50 ether);

        vm.warp(deadline);
        vm.prank(organizer);
        vm.expectRevert(TripFund.GoalNotReached.selector);
        fund.withdraw();
        vm.prank(alice);
        fund.refund();
        vm.prank(bob);
        fund.refund();
        assertEq(token.balanceOf(address(fund)), 100 ether);
        assertEq(token.balanceOf(organizer), 0);
        _assertAccounting(0, 0, 50 ether);
    }

    function testFuzzSuccessfulFundPaysAccountedTotalAndKeepsDonation(uint256 amount, uint256 donation)
        public
    {
        amount = bound(amount, GOAL, INITIAL_BALANCE);
        donation = bound(donation, 0, INITIAL_BALANCE);
        _contribute(alice, amount);
        vm.prank(carol);
        token.transfer(address(fund), donation);
        vm.warp(deadline);
        vm.prank(organizer);
        fund.withdraw();

        assertEq(token.balanceOf(organizer), amount);
        assertEq(token.balanceOf(address(fund)), donation);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - amount);
        assertEq(fund.totalRaised(), amount);
    }

    function testFuzzFailedFundRefundsInEitherOrder(uint256 aliceAmount, uint256 bobAmount, bool aliceFirst)
        public
    {
        aliceAmount = bound(aliceAmount, 1, GOAL - 2);
        bobAmount = bound(bobAmount, 1, GOAL - aliceAmount - 1);
        _contribute(alice, aliceAmount);
        _contribute(bob, bobAmount);
        vm.warp(deadline);

        vm.prank(aliceFirst ? alice : bob);
        fund.refund();
        vm.prank(aliceFirst ? bob : alice);
        fund.refund();

        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(fund)), 0);
        _assertAccounting(0, 0, aliceAmount + bobAmount);
    }
}
