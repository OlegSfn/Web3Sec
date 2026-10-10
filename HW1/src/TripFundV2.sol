pragma solidity 0.8.30;

import {TripFund} from "./TripFund.sol";

contract TripFundV2 is TripFund {
    function contributeFor(address beneficiary, uint256 amount) external nonReentrant {
        _contribute(beneficiary, amount);
    }
}
