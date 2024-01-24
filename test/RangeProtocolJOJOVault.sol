// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Test, console2 } from 'forge-std/Test.sol';
import { ERC1967Proxy } from
    '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import { FullMath } from '../src/libraries/FullMath.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { RangeProtocolJOJOVault } from '../src/RangeProtocolJOJOVault.sol';
import { VaultErrors } from '../src/errors/VaultErrors.sol';

contract TestRangeJOJOVault is Test {
    RangeProtocolJOJOVault vault =
        RangeProtocolJOJOVault(0xf32d1cD5b42e4a476F0F6BB83695b8d3585e7020);
    IERC20 depositToken;
    address owner;

    event OperatorStatusChanged(address operator, bool status);
    event Minted(address user, uint256 shares, uint256 amount);
    event Burned(address user, uint256 shares, uint256 amount);
    event LiquidityAdded(uint256 amount);
    event WithdrawRequested();
    event WithdrawExecuted();

    function setUp() external {
        vm.createSelectFork('https://arbitrum.llamarpc.com');
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
        uint256 expectedOwnerBalance = vault.ownerBalance()
            + (expectedAmount * 10_000 / 9900) - expectedAmount;

        vm.expectEmit();
        emit Burned(address(this), shares, expectedAmount);
        vault.burn(shares, expectedAmount);

        assertEq(vault.ownerBalance(), expectedOwnerBalance);
        uint256 ownerAccountBalanceBefore = depositToken.balanceOf(owner);
        vault.collectOwnerFee();
        assertEq(vault.ownerBalance(), 0);
        assertEq(
            depositToken.balanceOf(owner),
            ownerAccountBalanceBefore + expectedOwnerBalance
        );
    }

    function testSetManagingFeeByNonManager() external {
        vm.stopPrank();
        vm.prank(address(0x1));
        vm.expectRevert(bytes('Ownable: caller is not the manager'));
        vault.setManagingFee(2000);
        vm.startPrank(manager);
    }

    function testSetManagerFee() external {
        assertEq(vault.managingFee(), 100);
        vault.setManagingFee(200);
        assertEq(vault.managingFee(), 200);
    }

    function testSetInvalidManagerFee() external {
        uint256 feeToSet = vault.MAX_MANAGING_FEE() + 1;
        vm.expectRevert(VaultErrors.InvalidManagingFee.selector);
        vault.setManagingFee(feeToSet);
    }
}
