// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
// import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./interfaces/AggregatorV3Interface.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IBalancerVault.sol";

contract PointAMM is Ownable, AccessControl {
    uint256 constant SCALING_FACTOR = 10 ** 18;

    mapping(address => uint256) public userDeposits;
    mapping(address => uint256) public userProfits;

    IERC20 public USDC;
    IERC20 public WETH;
    IUniswapV2Router02 public router;
    AggregatorV3Interface internal priceFeed;
    IBalancerVault public balancerVault;

    uint256 public minProfit = 100 * 10 ** 6; // 100 USDC
    uint256 public deadlineBlock;

    event Deposit(address indexed user, uint256 amount);
    event WithdrawProfit(address indexed user, uint256 amount);
    event ProfitTaken(uint256 profit);
    event Debug(string message);
    event TokenApproval(address indexed user, uint256 amount);

    bytes32 public constant USER_ROLE = keccak256("USER");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");

    constructor(
        address _usdc,
        address _weth,
        address _router,
        address _priceFeed,
        address _balancerVault
    ) Ownable(msg.sender) {
        emit Debug("Constructor started");

        USDC = IERC20(_usdc);
        WETH = IERC20(_weth);
        router = IUniswapV2Router02(_router);
        priceFeed = AggregatorV3Interface(_priceFeed);
        balancerVault = IBalancerVault(_balancerVault);

        _grantRole(ADMIN_ROLE, msg.sender);
        deadlineBlock = block.number + 5760; // Approx. 1 day (assuming 15s blocks)

        emit Debug("Constructor completed");
    }

    function approveTokens(uint256 amount) external {
        require(amount > 0, "Approval amount must be greater than 0");
        require(USDC.approve(address(this), amount), "Token approval failed");
        emit TokenApproval(msg.sender, amount);
    }

    function depositFunds(uint256 amount) external {
        require(block.number < deadlineBlock, "Deadline has passed");
        require(amount > 0, "Amount must be greater than 0");
        require(USDC.balanceOf(msg.sender) >= amount, "Insufficient balance");
        require(
            USDC.allowance(msg.sender, address(this)) >= amount,
            "Insufficient allowance"
        );
        require(
            USDC.transferFrom(msg.sender, address(this), amount),
            "USDC transfer failed"
        );

        userDeposits[msg.sender] += amount;

        emit Debug(
            string(
                abi.encodePacked(
                    "Deposit successful for user: ",
                    msg.sender,
                    " Amount: ",
                    amount
                )
            )
        );
        emit Deposit(msg.sender, amount);
    }

    function executeFlashLoan(uint256 amount, uint256 slippage) external {
        emit Debug("Flash loan execution started");
        require(block.number < deadlineBlock, "Deadline has passed");
        require(amount > 0, "Amount must be greater than 0");
        emit Debug("Requirements passed, preparing flash loan");

        IERC20[] memory tokens; //= new address[](1);
        tokens[0] = USDC;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        bytes memory userData = abi.encode(slippage);

        balancerVault.flashLoan(address(this), tokens, amounts, userData);

        emit Debug("Flash loan executed");
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external {
        require(
            msg.sender == address(balancerVault),
            "Unauthorized flash loan"
        );

        uint256 slippage = abi.decode(userData, (uint256));

        uint256 swappedAmount = swapTokensForETH(amounts[0], slippage);

        // Make sure to approve the repayment before the function ends
        USDC.approve(address(balancerVault), amounts[0]);

        emit Debug(
            string(
                abi.encodePacked(
                    "Flash loan received and processed. Swapped amount: ",
                    swappedAmount
                )
            )
        );
    }

    function swapTokensForETH(
        uint256 amount,
        uint256 slippage
    ) internal returns (uint256) {
        emit Debug("Swapping tokens for ETH");

        uint256 wethPrice = getCurrentPrice();
        emit Debug(string(abi.encodePacked("WETH price: ", wethPrice)));

        uint256 wethAmount = (amount * SCALING_FACTOR) / wethPrice;
        emit Debug(string(abi.encodePacked("WETH amount: ", wethAmount)));

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);

        uint256 amountOutMin = (wethAmount * (100 - slippage)) / 100;

        USDC.approve(address(router), amount);

        // Get the balance before the swap
        uint256 balanceBefore = address(this).balance;

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );

        // Calculate the amount received by comparing balances
        uint256 amountReceived = address(this).balance - balanceBefore;

        emit Debug("Tokens swapped for ETH");

        return amountReceived;
    }

    function getCurrentPrice() internal view returns (uint256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return uint256(price);
    }

    function takeProfit() external {
        require(block.number >= deadlineBlock, "Deadline has not passed");
        require(userDeposits[msg.sender] > 0, "User has not deposited funds");

        emit Debug("Taking profit");

        uint256 profit = calculateProfit(msg.sender);
        emit Debug(string(abi.encodePacked("User profit: ", profit)));

        USDC.transfer(msg.sender, profit);
        emit Debug("Profit transferred");

        userDeposits[msg.sender] = 0;
        userProfits[msg.sender] = 0;

        emit Debug("User data reset");
    }

    function calculateProfit(address user) internal view returns (uint256) {
        uint256 depositedAmount = userDeposits[user];
        uint256 wethPrice = getCurrentPrice();
        uint256 profit = (depositedAmount * SCALING_FACTOR) / wethPrice;
        return profit;
    }

    function withdrawProfit() external {
        require(userProfits[msg.sender] > 0, "User has no profit");

        emit Debug("Withdrawing profit");

        USDC.transfer(msg.sender, userProfits[msg.sender]);
        emit Debug("Profit transferred");

        userProfits[msg.sender] = 0;
        emit Debug("User data reset");
    }

    function updateDeadline(
        uint256 newDeadlineBlock
    ) external onlyRole(ADMIN_ROLE) {
        emit Debug("Updating deadline");
        deadlineBlock = newDeadlineBlock;
        emit Debug("Deadline updated");
    }

    function updateMinProfit(
        uint256 newMinProfit
    ) external onlyRole(ADMIN_ROLE) {
        emit Debug("Updating minimum profit");
        minProfit = newMinProfit;
        emit Debug("Minimum profit updated");
    }

    // Function to receive ETH
    receive() external payable {}
}
