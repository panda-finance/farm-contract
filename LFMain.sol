// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import {ReentrancyGuard} from "./lib/ReentrancyGuard.sol";
import {OwnerGuard} from "./lib/OwnerGuard.sol";
import {LeverFarm} from "./LeverFarm.sol";

contract LFMain is ReentrancyGuard,OwnerGuard{
    
    address[] public farmPools;
    
    
    function getPools() external view returns (address[] memory pools) {
        pools = farmPools;
    }
    
    function create(address stakeTokenAddress,
                address farmTokenAddress,
                address feeAddress,
                uint256 startTime,
                uint256 endTime,
                uint256 farmPerSec) public onlyOwner {
            LeverFarm leverFarm = new LeverFarm();     
            leverFarm.init(stakeTokenAddress,farmTokenAddress,feeAddress,startTime,endTime,farmPerSec);
            leverFarm.changeOwner(msg.sender);
            address conAddr = leverFarm.getSelfAddress();
            farmPools.push(conAddr);
            
    }
    
}








