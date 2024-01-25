// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IRangeProtocolJOJOVault } from './interfaces/IRangeProtocolJOJOVault.sol';
import { IDealer } from './interfaces/JOJO/IDealer.sol';

abstract contract RangeProtocolJOJOVaultStorage is IRangeProtocolJOJOVault {
    IDealer public dealer;
    IERC20 public depositToken;
    address public operator;
    uint256 public managingFee;
    uint256 public ownerBalance;
}
