pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

contract TripFund is Initializable, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    error InvalidAddress();
    error InvalidGoal();
    error InvalidDeadline();
    error InvalidAmount();
    error FundClosed();
    error FundNotClosed();
    error GoalNotReached();
    error GoalReached();
    error Unauthorized();
    error AlreadyWithdrawn();
    error NoContribution();

    event Contribution(address indexed payer, address indexed beneficiary, uint256 amount);
    event Withdrawal(address indexed organizer, uint256 amount);
    event Refund(address indexed beneficiary, uint256 amount);

    IERC20 public token;
    address public organizer;
    uint256 public goal;
    uint256 public deadline;
    uint256 public totalRaised;
    mapping(address => uint256) public contributions;
    bool public withdrawn;

    constructor() {
        _disableInitializers();
    }

    function initialize(address token_, address organizer_, uint256 goal_, uint256 deadline_)
        external
        initializer
    {
        if (token_ == address(0) || organizer_ == address(0)) revert InvalidAddress();
        if (goal_ == 0) revert InvalidGoal();
        if (deadline_ <= block.timestamp) revert InvalidDeadline();

        token = IERC20(token_);
        organizer = organizer_;
        goal = goal_;
        deadline = deadline_;
    }

    function contribute(uint256 amount) external nonReentrant {
        _contribute(msg.sender, amount);
    }

    function withdraw() external nonReentrant {
        _requireClosed();
        if (msg.sender != organizer) revert Unauthorized();
        if (totalRaised < goal) revert GoalNotReached();
        if (withdrawn) revert AlreadyWithdrawn();

        withdrawn = true;
        token.safeTransfer(organizer, totalRaised);

        emit Withdrawal(organizer, totalRaised);
    }

    function refund() external nonReentrant {
        _requireClosed();
        if (totalRaised >= goal) revert GoalReached();

        uint256 amount = contributions[msg.sender];
        if (amount == 0) revert NoContribution();

        contributions[msg.sender] = 0;
        token.safeTransfer(msg.sender, amount);

        emit Refund(msg.sender, amount);
    }

    function _contribute(address beneficiary, uint256 amount) internal {
        if (block.timestamp >= deadline) revert FundClosed();
        if (beneficiary == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        contributions[beneficiary] += amount;
        totalRaised += amount;
        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Contribution(msg.sender, beneficiary, amount);
    }

    function _requireClosed() private view {
        if (block.timestamp < deadline) revert FundNotClosed();
    }
}
