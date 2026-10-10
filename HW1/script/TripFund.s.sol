pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {TripFund} from "../src/TripFund.sol";
import {TripFundV2} from "../src/TripFundV2.sol";
import {TestToken} from "../src/TestToken.sol";

contract TripFundScript is Script {
    error LocalChainRequired();

    modifier onlyLocalChain() {
        if (block.chainid != 31337) revert LocalChainRequired();
        _;
    }

    function run() external onlyLocalChain returns (address tokenAddress, address proxyAddress) {
        address adminOwner = vm.envAddress("ADMIN_OWNER");
        address organizer = vm.envAddress("ORGANIZER");
        uint256 goal = vm.envOr("GOAL", uint256(100 ether));
        uint256 deadline = block.timestamp + vm.envOr("DURATION", uint256(7 days));
        Options memory options = _validationOptions();

        vm.startBroadcast(adminOwner);
        TestToken token = new TestToken();
        token.mint(adminOwner, 1_000 ether);
        proxyAddress = Upgrades.deployTransparentProxy(
            "TripFund.sol:TripFund",
            adminOwner,
            abi.encodeCall(TripFund.initialize, (address(token), organizer, goal, deadline)),
            options
        );
        vm.stopBroadcast();

        tokenAddress = address(token);
        console2.log("TOKEN", tokenAddress);
        console2.log("PROXY", proxyAddress);
    }

    function upgrade() external onlyLocalChain {
        address adminOwner = vm.envAddress("ADMIN_OWNER");
        address proxy = vm.envAddress("PROXY");
        Options memory options = _validationOptions();
        options.referenceContract = "TripFund.sol:TripFund";

        vm.startBroadcast(adminOwner);
        Upgrades.upgradeProxy(proxy, "TripFundV2.sol:TripFundV2", "", options);
        vm.stopBroadcast();

        console2.log("PROXY", proxy);
        console2.log("IMPLEMENTATION", Upgrades.getImplementationAddress(proxy));
    }

    function _validationOptions() private pure returns (Options memory options) {
        options.unsafeAllow = "constructor";
    }
}
