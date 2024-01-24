// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Initializable } from
    '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import { UUPSUpgradeable } from
    '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import { ERC20Upgradeable } from
    '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import { ReentrancyGuardUpgradeable } from
    '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import { PausableUpgradeable } from
    '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import { Address } from '@openzeppelin/contracts/utils/Address.sol';
import { IERC20Metadata } from
    '@openzeppelin/contracts/interfaces/IERC20Metadata.sol';
import { IERC20 } from '@openzeppelin/contracts/interfaces/IERC20.sol';
import { SafeERC20 } from
    '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { OwnableUpgradeable } from
    '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from
    '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { RangeProtocolJOJOVaultStorage } from
    './RangeProtocolJOJOVaultStorage.sol';
import { IDealer } from './interfaces/JOJO/IDealer.sol';
import { VaultErrors } from './errors/VaultErrors.sol';
import { FullMath } from './libraries/FullMath.sol';

import { Test, console2 } from 'forge-std/Test.sol';

/**
 * @notice RangeProtocolJOJOVault is a vault managed by the vault manager to
 * manage perpetual positions on JOJO exchange . It allows users to deposit
 * {depositToken} when opening a vault position and get vault shares that represent
 * their ownership of the vault. The vault manager is a linked signer of the
 * vault and can manage vault's assets off-chain to open long/short perpetual
 * positions on the vertex protocol.
 *
 * The LP ownership of the vault is represented by the fungible ERC20 token minted
 * by the vault to LPs.
 *
 * The vault manager is responsible to maintain a certain ratio of {depositToken} in
 * the vault as passive balance, so LPs can burn their vault shares and redeem the
 * underlying {depositToken} pro-rata to the amount of shares being burned.
 *
 * The LPs can burn their vault shares and redeem the underlying vault's {depositToken}
 * pro-rata to the amount of shares they are burning. The LPs pay managing fee on their
 * final redeemable amount.
 *
 * The LP token's price is based on total passive holding of the vault in {depositToken}.
 * Holding of vault is calculated as sum of margin + perps positions' PnL from the JOJO
 * and the passive deposit token balance in the vault.
 *
 * Manager can change the managing fee which is capped at maximum to 10% of the
 * redeemable amount by LP.
 */
contract RangeProtocolJOJOVault is
    Initializable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    ERC20Upgradeable,
    PausableUpgradeable,
    RangeProtocolJOJOVaultStorage,
    Test
{
    using SafeERC20 for IERC20;

    event OperatorStatusChanged(address operator, bool status);
    event Minted(address user, uint256 shares, uint256 amount);
    event Burned(address user, uint256 shares, uint256 amount);
    event LiquidityAdded(uint256 amount);
    event WithdrawRequested();
    event WithdrawExecuted();

    uint256 public constant MAX_MANAGING_FEE = 1000;

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice initializes the vault.
     * @param _owner address of vault's manager.
     * @param _name name of vault's ERC20 fungible token.
     * @param _symbol symbol of vault's ERC20 fungible token.
     */
    function initialize(
        address _owner,
        string memory _name,
        string memory _symbol
    )
        external
        initializer
    {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Ownable_init(_owner);
        __ERC20_init(_name, _symbol);
        __Pausable_init();

        dealer = IDealer(0xcDf9eED57Fe8dFaaCeCf40699E5861517143bcC7);
        depositToken = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
        ownerFee = 0;
    }

    /**
     * @notice sets/unsets the operator for the vault which can open positions on the JOJO exchange
     * on behalf of the vault.
     * @param _operator address of the operator.
     * @param status set or unset the operator.
     */
    function setOperator(address _operator, bool status) external onlyOwner {
        operator = _operator;
        dealer.setOperator(operator, status);
        emit OperatorStatusChanged(_operator, status);
    }

    /**
     * @notice mints vault shares by depositing the {depositToken} amount.
     * @param amount the amount of {depositToken} to deposit.
     * @return shares the amount of vault shares minted.
     */
    function mint(uint256 amount)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        if (amount == 0) {
            revert VaultErrors.ZeroDepositAmount();
        }
        uint256 totalSupply = totalSupply();
        shares = totalSupply != 0
            ? FullMath.mulDivRoundingUp(amount, totalSupply, getUnderlyingBalance())
            : amount;
        _mint(msg.sender, shares);
        depositToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Minted(msg.sender, shares, amount);
    }

    /**
     * @notice allows burning of vault {shares} to redeem the underlying the {depositTokenBalance}.
     * @param shares the amount of shares to be burned by the user.
     * @return amount the amount of underlying {depositToken} to be redeemed by the user.
     */
    function burn(
        uint256 shares,
        uint256 minAmount
    )
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amount)
    {
        if (shares == 0) revert VaultErrors.ZeroSharesAmount();
        amount = shares * getUnderlyingBalance() / totalSupply();
        _burn(msg.sender, shares);

        _netManagingFee(amount);
        if (amount < minAmount) {
            revert VaultErrors.AmountIsLessThanMinAmount();
        }
        if (amount > depositToken.balanceOf(address(this))) {
            revert VaultErrors.NotEnoughPassiveBalanceForWithdrawal();
        }
        depositToken.transfer(msg.sender, amount);
        emit Burned(msg.sender, shares, amount);
    }

    /**
     * @notice adds liquidity/margin to the JOJO protocol.
     * @param amount the amount of liquidity to add to JOJO.
     * only owner can call this function.
     */
    function addLiquidity(uint256 amount) external onlyOwner {
        if (amount == 0) {
            revert VaultErrors.ZeroLiquidityAmount();
        }
        depositToken.forceApprove(address(dealer), amount);
        dealer.deposit(amount, 0, address(this));
        emit LiquidityAdded(amount);
    }

    /**
     * @notice initiates request for withdrawal from the JOJO.
     * This it does withdraw the amount from JOJO but only initiates the request.
     * @param amount the amount of margin to withdraw from JOJO.
     * only owner can call this function.
     */
    function requestWithdraw(uint256 amount) external onlyOwner {
        if (amount == 0) {
            revert VaultErrors.ZeroLiquidityAmount();
        }
        dealer.requestWithdraw(amount, 0);
        emit WithdrawRequested();
    }

    /**
     * @notice executes withdraw and transfers margin/PnL from JOJO to the vault.
     * @param amount amount of margin/PnL to withdraw.
     * only manager can call this function.
     */
    function executeWithdraw(uint256 amount) external onlyOwner {
        if (amount == 0) {
            revert VaultErrors.ZeroLiquidityAmount();
        }
        (,, uint256 pendingPrimaryWithdraw,,) =
            dealer.getCreditOf(address(this));
        if (amount > pendingPrimaryWithdraw) {
            revert VaultErrors.NotEnoughRequestedForWithdrawal();
        }
        dealer.executeWithdraw(address(this), false);
        emit WithdrawExecuted();
    }

    function collectOwnerFee() external onlyOwner {
        uint256 _ownerBalance = ownerBalance;
        ownerBalance = 0;
        depositToken.transfer(msg.sender, _ownerBalance);
    }

    /**
     * @notice returns underlying balance of the vault.
     * It computes underlying balance by summing passive balance
     * and net value (margin + PnL from perp positions).
     * @return amount the amount of underlying balance in deposit token.
     */
    function getUnderlyingBalance() public view returns (uint256 amount) {
        (int256 netValue,,) = dealer.getTraderRisk(address(this));
        uint256 passiveBalance = depositToken.balanceOf(address(this));

        if (passiveBalance > ownerBalance) {
            passiveBalance -= ownerBalance;
        }
        amount = uint256(netValue) + passiveBalance;
    }

    /**
     * @notice returns redeemable balance based on the number of {shares} passed.
     * @param shares the amount of shares.
     * @return amount the amount of underlying balance redeemable against the {shares}.
     */
    function getUnderlyingBalanceByShares(uint256 shares)
        public
        view
        returns (uint256 amount)
    {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply != 0) {
            amount = shares * getUnderlyingBalance() / _totalSupply;
            amount = _netManagingFee(amount);
        }
    }

    /**
     * @notice subtracts managing fee from the redeemable {amount}.
     * @return amountAfterFee the {depositToken} amount redeemable after
     * the managing fee is deducted.
     */
    function _netManagingFee(uint256 amount)
        private
        view
        returns (uint256 amountAfterFee)
    {
        uint256 fee = amount * ownerFee / 10_000;
        amountAfterFee = amount - fee;
    }

    /**
     * @notice add managing fee to the manager collectable balance.
     * @param amount the amount to apply managing fee upon.
     */
    function _applyManagingFee(uint256 amount) private {
        ownerBalance += amount * ownerFee / 10_000;
    }

    /**
     * @notice internal function guard against upgrading the vault
     * implementation by non-manager.
     */
    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != owner()) {
            revert VaultErrors.NotAuthorizedToUpgrade();
        }
    }
}
