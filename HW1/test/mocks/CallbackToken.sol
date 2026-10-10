pragma solidity 0.8.30;

import {TestToken} from "../../src/TestToken.sol";
import {TripFund} from "../../src/TripFund.sol";

contract CallbackToken is TestToken {
    TripFund public target;
    address public beneficiary;
    bytes public callbackData;
    bool public callbackOnTransferFrom;
    bool public callbackSucceeded;
    bytes public callbackResult;
    uint256 public observedContribution;
    uint256 public observedTotalRaised;
    bool public observedWithdrawn;
    bool private active;

    function configure(TripFund target_, address beneficiary_, bytes calldata data, bool onTransferFrom)
        external
    {
        target = target_;
        beneficiary = beneficiary_;
        callbackData = data;
        callbackOnTransferFrom = onTransferFrom;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (!callbackOnTransferFrom) _callback();
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (callbackOnTransferFrom) _callback();
        return super.transferFrom(from, to, amount);
    }

    function _callback() private {
        if (active || address(target) == address(0)) return;
        active = true;
        observedContribution = target.contributions(beneficiary);
        observedTotalRaised = target.totalRaised();
        observedWithdrawn = target.withdrawn();
        (callbackSucceeded, callbackResult) = address(target).call(callbackData);
        active = false;
    }
}
