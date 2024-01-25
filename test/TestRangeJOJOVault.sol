// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Test, console2 } from 'forge-std/Test.sol';
import { ERC1967Proxy } from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import { FullMath } from '../src/libraries/FullMath.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { RangeProtocolJOJOVault } from '../src/RangeProtocolJOJOVault.sol';
import { VaultErrors } from '../src/errors/VaultErrors.sol';
import { IDealer } from '../src/interfaces/JOJO/IDealer.sol';

contract TestRangeJOJOVault is Test {
    RangeProtocolJOJOVault vault = RangeProtocolJOJOVault(0xf32d1cD5b42e4a476F0F6BB83695b8d3585e7020);
    IERC20 depositToken;
    address owner;

    event OperatorStatusChanged(address operator, bool status);
    event Minted(address user, uint256 shares, uint256 amount);
    event Burned(address user, uint256 shares, uint256 amount);
    event LiquidityAdded(uint256 amount);
    event WithdrawRequested(uint256);
    event WithdrawExecuted(uint256);
    event ManagingFeeSet(uint256 fee);

    error OwnableUnauthorizedAccount(address);
    error OwnableInvalidOwner(address owner);

    function setUp() external {
        vm.createSelectFork('https://rpc.arb1.arbitrum.gateway.fm');
        owner = vault.owner();
        vm.startPrank(owner);
        address implementation = address(new RangeProtocolJOJOVault());
        vault.upgradeToAndCall(implementation, '');
        vm.stopPrank();

        depositToken = vault.depositToken();
        deal(address(depositToken), address(this), 100_000e6);
    }

    function testMintWithZeroAmount() external {
        vm.expectRevert(VaultErrors.ZeroDepositAmount.selector);
        vault.mint(0);
    }

    function testMintWithoutApprove() external {
        uint256 amount = 1000e6;
        vm.expectRevert(bytes('ERC20: transfer amount exceeds allowance'));
        vault.mint(amount);
    }

    function testMint() external {
        uint256 amount = 1000e6;
        depositToken.approve(address(vault), amount);

        uint256 vaultBalanceBefore = vault.getUnderlyingBalance();
        vm.expectEmit();
        emit Minted(address(this), amount, amount);
        vault.mint(amount);
        assertEq(vault.getUnderlyingBalance(), vaultBalanceBefore + amount);
    }

    function testAddLiquidityWithZeroAmount() external {
        vm.expectRevert(VaultErrors.ZeroLiquidityAmount.selector);
        vm.prank(owner);
        vault.addLiquidity(0);
    }

    function testAddLiquidityWithNonManager() external {
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(this)));
        vault.addLiquidity(1);
    }

    function testAddLiquidity() external {
        uint256 amount = 1000e6;
        depositToken.approve(address(vault), amount);
        vault.mint(amount);

        IDealer dealer = vault.dealer();
        (int256 jojoBalanceBefore,,,,) = dealer.getCreditOf(address(vault));

        uint256 balance = depositToken.balanceOf(address(vault));
        vm.expectEmit();
        emit LiquidityAdded(balance);
        vm.prank(owner);
        vault.addLiquidity(balance);
        assertEq(depositToken.balanceOf(address(vault)), 0);

        (int256 jojoBalanceAfter,,,,) = dealer.getCreditOf(address(vault));
        assertEq(uint256(jojoBalanceAfter - jojoBalanceBefore), amount);
    }

    function testRequestWithdrawWithZeroAmount() external {
        vm.expectRevert(VaultErrors.ZeroLiquidityAmount.selector);
        vm.prank(owner);
        vault.requestWithdraw(0);
    }

    function testRequestWithdrawByNonManager() external {
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(this)));
        vault.requestWithdraw(123);
    }

    function testRequestWithdraw() external {
        uint256 amount = 1000e6;
        depositToken.approve(address(vault), amount);
        vault.mint(amount);

        IDealer dealer = vault.dealer();
        (,, uint256 pendingWithdrawBefore,,) = dealer.getCreditOf(address(vault));

        uint256 balance = depositToken.balanceOf(address(vault));
        vm.expectEmit();
        emit WithdrawRequested(balance);
        vm.prank(owner);
        vault.requestWithdraw(balance);

        (,, uint256 pendingWithdrawAfter,,) = dealer.getCreditOf(address(vault));
        assertEq(pendingWithdrawAfter, pendingWithdrawBefore + balance);
    }

    function testExecuteWithdraw() external {
        uint256 amount = 1000e6;
        depositToken.approve(address(vault), amount);
        vault.mint(amount);

        uint256 balance = depositToken.balanceOf(address(vault));
        vm.startPrank(owner);
        vault.addLiquidity(balance);
        assertEq(depositToken.balanceOf(address(vault)), 0);
        vault.requestWithdraw(balance);

        vm.expectRevert('JOJO_WITHDRAW_PENDING');
        vault.executeWithdraw();

        vm.warp(block.timestamp + 5);
        vault.executeWithdraw();
        assertEq(depositToken.balanceOf(address(vault)), balance);
        vm.stopPrank();
    }

    function testBurnZeroAmount() external {
        vm.expectRevert(VaultErrors.ZeroSharesAmount.selector);
        vault.burn(0, 0);
    }

    function testBurnWithoutOwningShares() external {
        vm.prank(address(0x1));
        vm.expectRevert();
        vault.burn(1000, 0);
    }

    function testBurnWithMoreThanExpectedAmount() external {
        uint256 depositAmount = 1000e6;
        depositToken.approve(address(vault), depositAmount);
        vault.mint(depositAmount);
        uint256 amount = vault.balanceOf(address(this)) * 100 / 10_000;
        uint256 expectedAmount = vault.getUnderlyingBalanceByShares(amount);
        vm.expectRevert(VaultErrors.AmountIsLessThanMinAmount.selector);
        vault.burn(amount, expectedAmount + 1000);
    }

    function testBurn() external {
        uint256 depositAmount = 1000e6;
        depositToken.approve(address(vault), depositAmount);
        vault.mint(depositAmount);

        uint256 shares = vault.balanceOf(address(this)) * 9900 / 10_000;
        uint256 expectedAmount = vault.getUnderlyingBalanceByShares(shares);
        uint256 expectedOwnerBalance =
            vault.ownerBalance() + (expectedAmount * 10_000 / (10_000 - vault.managingFee())) - expectedAmount;

        vm.expectEmit();
        emit Burned(address(this), shares, expectedAmount);
        vault.burn(shares, expectedAmount);

        assertEq(vault.ownerBalance(), expectedOwnerBalance);
        uint256 ownerAccountBalanceBefore = depositToken.balanceOf(owner);
        vm.prank(owner);
        vault.collectManagingFee();
        assertEq(vault.ownerBalance(), 0);
        assertEq(depositToken.balanceOf(owner), ownerAccountBalanceBefore + expectedOwnerBalance);
    }

    function testSetManagingFeeByNonOwner() external {
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(this)));
        vault.setManagingFee(2000);
    }

    function testSetManagingFee() external {
        vm.expectEmit();
        emit ManagingFeeSet(200);
        vm.prank(owner);
        vault.setManagingFee(200);
        assertEq(vault.managingFee(), 200);
    }

    function testSetInvalidManagingFee() external {
        uint256 feeToSet = vault.MAX_MANAGING_FEE() + 1;
        vm.expectRevert(VaultErrors.InvalidManagingFee.selector);
        vm.prank(owner);
        vault.setManagingFee(feeToSet);
    }

    function testSetOperatorByNonManager() external {
        address operator = address(0x123);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(this)));
        vault.setOperator(operator);
    }

    function testSetOperatorByManager() external {
        address operator = address(0x123);
        vm.expectEmit();
        emit OperatorStatusChanged(operator, true);
        vm.prank(owner);
        vault.setOperator(operator);
        assertEq(vault.operator(), operator);

        address operator1 = address(0x456);
        vm.expectEmit();
        emit OperatorStatusChanged(operator, false);
        emit OperatorStatusChanged(operator1, true);
        vm.prank(owner);
        vault.setOperator(operator);
    }
}
