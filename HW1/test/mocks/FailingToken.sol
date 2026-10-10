pragma solidity 0.8.30;

import {TestToken} from "../../src/TestToken.sol";

contract FailingToken is TestToken {
    enum Failure {
        None,
        ReturnFalse,
        Revert
    }

    error TransferRejected();

    Failure public incomingFailure;
    Failure public outgoingFailure;

    function setFailures(Failure incoming, Failure outgoing) external {
        incomingFailure = incoming;
        outgoingFailure = outgoing;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        super.transfer(to, amount);
        return _result(outgoingFailure);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        super.transferFrom(from, to, amount);
        return _result(incomingFailure);
    }

    function _result(Failure failure) private pure returns (bool) {
        if (failure == Failure.Revert) revert TransferRejected();
        return failure != Failure.ReturnFalse;
    }
}
