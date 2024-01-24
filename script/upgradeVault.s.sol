// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Script, console2 } from 'forge-std/Script.sol';
import { ERC1967Proxy } from
    '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import { RangeProtocolJOJOVault } from '../src/RangeProtocolJOJOVault.sol';

contract upgradeVault is Script {
    function run() public {
        uint256 pk = vm.envUint('PK');
        vm.startBroadcast(pk);

        address implementation = address(new RangeProtocolJOJOVault());
        console2.log('implementation address: ', implementation);
        address vault = 0xCa9BFf75cF2b40b4ba2Ad001Ca448334d0aeE1da;
        (bool success,) = vault.call(
            abi.encodeWithSignature(
                'upgradeToAndCall(address,bytes)', implementation, ''
            )
        );
        console2.log('upgrade status:', success);
        vm.stopBroadcast();
    }
}
