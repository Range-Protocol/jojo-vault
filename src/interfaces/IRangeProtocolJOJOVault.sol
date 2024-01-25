// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

interface IRangeProtocolJOJOVault {
    event OperatorStatusChanged(address operator, bool status);
    event Minted(address user, uint256 shares, uint256 amount);
    event Burned(address user, uint256 shares, uint256 amount);
    event LiquidityAdded(uint256 amount);
    event WithdrawRequested(uint256 amount);
    event WithdrawExecuted(uint256 amount);
    event ManagingFeeSet(uint256 fee);

    function initialize(address _owner, string memory _name, string memory _symbol) external;
    function setOperator(address _operator) external;
    function mint(uint256 amount) external returns (uint256 shares);
    function burn(uint256 shares, uint256 minAmount) external returns (uint256 amount);
    function addLiquidity(uint256 amount) external;
    function requestWithdraw(uint256 amount) external;
    function executeWithdraw() external;
    function setManagingFee(uint256 _managingFee) external;
    function collectManagingFee() external;
    function getUnderlyingBalance() external view returns (uint256 amount);
    function getUnderlyingBalanceByShares(uint256 shares) external view returns (uint256 amount);
}
