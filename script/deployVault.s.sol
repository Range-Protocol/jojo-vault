// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Script, console2 } from 'forge-std/Script.sol';
import { ERC1967Proxy } from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import { RangeProtocolJOJOVault } from '../src/RangeProtocolJOJOVault.sol';

contract deployVault is Script {
    function run() public {
        uint256 pk = vm.envUint('PK');
        vm.startBroadcast(pk);

//        address implementation = address(new RangeProtocolJOJOVault());
        address implementation = 0x63b5dA23Cf6331366Df10aE34d860cEc5985077B;
        RangeProtocolJOJOVault vault = RangeProtocolJOJOVault(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeWithSignature(
                        "initialize(address,string,string)",
                        0x2B986A355F5676F77687A84b3209Af8654b2C6aa,
                        "JOJO Test Vault",
                        "JTV"
                    )
                )
            )
        );

        console2.log('Vault: ', address(vault));
        console2.log(vault.owner());
        vm.stopBroadcast();
    }
}
