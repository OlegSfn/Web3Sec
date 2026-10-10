pragma solidity 0.8.30;

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {TripFundFixture} from "./TripFundFixture.sol";
import {TripFundV2} from "../src/TripFundV2.sol";

contract TripFundUpgradeTest is TripFundFixture {
    function testValidatedUpgradePreservesStateAndSupportsSponsoredRefund() public {
        _contribute(alice, 20 ether);
        address proxyAddress = address(fund);
        address previousImplementation = Upgrades.getImplementationAddress(proxyAddress);
        address previousAdmin = Upgrades.getAdminAddress(proxyAddress);
        vm.warp(deadline - 1 days);

        Options memory options;
        options.referenceContract = "TripFund.sol:TripFund";
        options.unsafeAllow = "constructor";
        Upgrades.upgradeProxy(proxyAddress, "TripFundV2.sol:TripFundV2", "", options, adminOwner);
        TripFundV2 upgradedFund = TripFundV2(proxyAddress);

        assertEq(address(upgradedFund), proxyAddress);
        assertTrue(Upgrades.getImplementationAddress(proxyAddress) != previousImplementation);
        assertEq(Upgrades.getAdminAddress(proxyAddress), previousAdmin);
        assertEq(proxyAdmin.owner(), adminOwner);
        assertEq(address(upgradedFund.token()), address(token));
        assertEq(upgradedFund.organizer(), organizer);
        assertEq(upgradedFund.goal(), GOAL);
        assertEq(upgradedFund.deadline(), deadline);
        assertFalse(upgradedFund.withdrawn());
        _assertAccounting(20 ether, 0, 20 ether);
        assertEq(token.balanceOf(proxyAddress), 20 ether);

        vm.startPrank(bob);
        token.approve(proxyAddress, 30 ether);
        upgradedFund.contributeFor(carol, 30 ether);
        vm.stopPrank();
        _contribute(alice, 5 ether);
        _assertAccounting(25 ether, 0, 55 ether);
        assertEq(upgradedFund.contributions(carol), 30 ether);
        assertEq(token.balanceOf(proxyAddress), 55 ether);

        vm.warp(deadline);
        vm.prank(carol);
        upgradedFund.refund();
        vm.prank(alice);
        upgradedFund.refund();

        assertEq(token.balanceOf(carol), INITIAL_BALANCE + 30 ether);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE - 30 ether);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(token.balanceOf(proxyAddress), 0);
        _assertAccounting(0, 0, 55 ether);
        assertEq(upgradedFund.contributions(carol), 0);
    }
}
