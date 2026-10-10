pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TripFundFixture} from "./TripFundFixture.sol";
import {TripFund} from "../src/TripFund.sol";
import {TripFundV2} from "../src/TripFundV2.sol";

contract TripFundV2Test is TripFundFixture {
    TripFundV2 internal upgradedFund;

    function setUp() public override {
        super.setUp();
        upgradedFund = _upgrade();
    }

    function testContributeForChargesPayerAndAccumulatesBeneficiaryContributions() public {
        _contributeFor(alice, bob, 20 ether);
        _contributeFor(carol, bob, 15 ether);
        _contribute(bob, 5 ether);

        _assertAccounting(0, 40 ether, 40 ether);
        assertEq(fund.contributions(carol), 0);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 20 ether);
        assertEq(token.balanceOf(carol), INITIAL_BALANCE - 15 ether);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE - 5 ether);
        assertEq(token.balanceOf(address(fund)), 40 ether);
    }

    function testContributeForEmitsPayerBeneficiaryAndAmount() public {
        vm.prank(alice);
        token.approve(address(fund), 20 ether);
        vm.expectEmit(true, true, false, true, address(fund));
        emit Contribution(alice, bob, 20 ether);
        vm.prank(alice);
        upgradedFund.contributeFor(bob, 20 ether);
    }

    function testContributeForRejectsZeroBeneficiary() public {
        vm.prank(alice);
        vm.expectRevert(TripFund.InvalidAddress.selector);
        upgradedFund.contributeFor(address(0), 10 ether);
        _assertAccounting(0, 0, 0);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
    }

    function testContributeForRejectsZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(TripFund.InvalidAmount.selector);
        upgradedFund.contributeFor(bob, 0);
        _assertAccounting(0, 0, 0);
    }

    function testContributeForSucceedsOneSecondBeforeDeadline() public {
        vm.warp(deadline - 1);
        _contributeFor(alice, bob, 20 ether);
        _assertAccounting(0, 20 ether, 20 ether);
    }

    function testContributeForRejectsAtDeadline() public {
        vm.warp(deadline);
        vm.prank(alice);
        vm.expectRevert(TripFund.FundClosed.selector);
        upgradedFund.contributeFor(bob, 20 ether);
        _assertAccounting(0, 0, 0);
    }

    function testBeneficiaryApprovalCannotAuthorizePayerTokens() public {
        vm.prank(bob);
        token.approve(address(fund), 20 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(fund), 0, 20 ether
            )
        );
        vm.prank(alice);
        upgradedFund.contributeFor(bob, 20 ether);
        _assertAccounting(0, 0, 0);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(fund)), 0);
    }

    function testOnlyBeneficiaryCanRefundSponsoredContribution() public {
        _contributeFor(alice, bob, 20 ether);
        vm.warp(deadline);
        vm.prank(alice);
        vm.expectRevert(TripFund.NoContribution.selector);
        fund.refund();

        vm.prank(bob);
        fund.refund();
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 20 ether);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE + 20 ether);
        assertEq(token.balanceOf(address(fund)), 0);
        _assertAccounting(0, 0, 20 ether);
    }

    function testContributeForSelfMatchesOrdinaryContribution() public {
        _contributeFor(alice, alice, 20 ether);
        _contribute(alice, 10 ether);
        _assertAccounting(30 ether, 0, 30 ether);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 30 ether);
    }

    function testOrdinaryContributionWorksAfterUpgrade() public {
        _contribute(alice, 20 ether);
        _assertAccounting(20 ether, 0, 20 ether);
        assertEq(token.balanceOf(address(fund)), 20 ether);
    }

    function testUpgradeRequiresActualProxyAdminOwner() public {
        TripFundV2 nextImplementation = new TripFundV2();
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        bytes32 previousImplementation = vm.load(address(fund), implementationSlot);

        vm.prank(organizer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, organizer));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(fund)), address(nextImplementation), ""
        );
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(fund)), address(nextImplementation), ""
        );

        assertEq(vm.load(address(fund), implementationSlot), previousImplementation);
        assertEq(proxyAdmin.owner(), adminOwner);
        assertEq(fund.organizer(), organizer);
    }

    function testUpgradedProxyRejectsReinitialization() public {
        vm.prank(adminOwner);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        upgradedFund.initialize(address(token), alice, 1, deadline + 1);
        assertEq(fund.organizer(), organizer);
        assertEq(fund.goal(), GOAL);
        assertEq(fund.deadline(), deadline);
    }

    function testV2ImplementationRejectsDirectInitialization() public {
        TripFundV2 nextImplementation = new TripFundV2();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        nextImplementation.initialize(address(token), organizer, GOAL, deadline);
    }

    function testFuzzSponsoredRefundConservesTokensAndCreditsRecipient(uint256 first, uint256 second) public {
        first = bound(first, 1, GOAL - 2);
        second = bound(second, 1, GOAL - first - 1);
        _contributeFor(alice, bob, first);
        _contributeFor(carol, bob, second);
        vm.warp(deadline);
        vm.prank(bob);
        fund.refund();

        assertEq(token.balanceOf(alice), INITIAL_BALANCE - first);
        assertEq(token.balanceOf(carol), INITIAL_BALANCE - second);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE + first + second);
        assertEq(token.balanceOf(address(fund)), 0);
        _assertAccounting(0, 0, first + second);
    }

    function _contributeFor(address payer, address beneficiary, uint256 amount) internal {
        vm.startPrank(payer);
        token.approve(address(fund), amount);
        upgradedFund.contributeFor(beneficiary, amount);
        vm.stopPrank();
    }
}
