pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TripFund} from "../src/TripFund.sol";
import {TripFundV2} from "../src/TripFundV2.sol";
import {TestToken} from "../src/TestToken.sol";

abstract contract TripFundFixture is Test {
    uint256 internal constant GOAL = 100 ether;
    uint256 internal constant INITIAL_BALANCE = 1_000 ether;
    bytes32 internal constant ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);

    address internal adminOwner = makeAddr("adminOwner");
    address internal organizer = makeAddr("organizer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    TestToken internal token;
    TripFund internal implementation;
    TripFund internal fund;
    ProxyAdmin internal proxyAdmin;
    uint256 internal deadline;

    event Contribution(address indexed payer, address indexed beneficiary, uint256 amount);
    event Withdrawal(address indexed organizer, uint256 amount);
    event Refund(address indexed beneficiary, uint256 amount);

    function setUp() public virtual {
        vm.warp(1_700_000_000);
        deadline = block.timestamp + 7 days;
        token = new TestToken();
        implementation = new TripFund();
        fund = _deploy(address(token), organizer, GOAL, deadline);
        proxyAdmin = ProxyAdmin(address(uint160(uint256(vm.load(address(fund), ADMIN_SLOT)))));
        _fundActors(token);
    }

    function _deploy(address token_, address organizer_, uint256 goal_, uint256 deadline_)
        internal
        returns (TripFund)
    {
        return TripFund(
            address(
                new TransparentUpgradeableProxy(
                    address(implementation),
                    adminOwner,
                    abi.encodeCall(TripFund.initialize, (token_, organizer_, goal_, deadline_))
                )
            )
        );
    }

    function _fundActors(TestToken token_) internal {
        token_.mint(alice, INITIAL_BALANCE);
        token_.mint(bob, INITIAL_BALANCE);
        token_.mint(carol, INITIAL_BALANCE);
    }

    function _contribute(address payer, uint256 amount) internal {
        vm.startPrank(payer);
        token.approve(address(fund), amount);
        fund.contribute(amount);
        vm.stopPrank();
    }

    function _upgrade() internal returns (TripFundV2) {
        TripFundV2 nextImplementation = new TripFundV2();
        vm.prank(adminOwner);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(fund)), address(nextImplementation), ""
        );
        return TripFundV2(address(fund));
    }

    function _assertAccounting(uint256 aliceAmount, uint256 bobAmount, uint256 total) internal view {
        assertEq(fund.contributions(alice), aliceAmount);
        assertEq(fund.contributions(bob), bobAmount);
        assertEq(fund.totalRaised(), total);
    }
}
