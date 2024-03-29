// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Script, console2 } from 'forge-std/Script.sol';
import { ERC1967Proxy } from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import { RangeProtocolJOJOVault } from '../src/RangeProtocolJOJOVault.sol';

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract mint is Script {
    function run() public {
        uint256 pk = vm.envUint('PK');
        vm.startBroadcast(pk);
        RangeProtocolJOJOVault vault = RangeProtocolJOJOVault(0x0e3B9E7CfC71EE01CE425D7E82139a8D12058968);
        IERC20 depositToken = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
        uint256 amount = 10e6;
        depositToken.approve(address(vault), amount);
        vault.mint(amount);
        vm.stopBroadcast();
    }
}
