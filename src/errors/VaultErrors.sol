// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

library VaultErrors {
    error ZeroDepositAmount();
    error ZeroSharesAmount();
    error AmountIsLessThanMinAmount();
    error NotEnoughBalanceInVault();
    error ZeroLiquidityAmount();
    error NotAuthorizedToUpgrade();
    error InvalidShareAmount();
    error InvalidManagingFee();
}
