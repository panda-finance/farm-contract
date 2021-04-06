/*
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

contract OwnerGuard {
    
    address private _OWNER_;
    
    // safe 
    mapping(address => uint8) blackList;
    uint8 _SAFE_LOCK_;
    uint8 _PAUSE_LOCK_;
    uint256 _START_TIME_;    
    
    event OwnerSet(address indexed oldOwner, address indexed newOwner);
    
    modifier onlyOwner() {
        require(msg.sender == _OWNER_, "Caller is not owner");
        _;
    }
    
    modifier safeCheck() {
        require(_SAFE_LOCK_ == 0,"!safeLock");
        require(block.timestamp >= _START_TIME_,"farm not start");
        require(blackList[msg.sender] == 0,"address in blackList!");
        _;
    }
    
    constructor() internal{
        _OWNER_ = msg.sender;
        emit OwnerSet(address(0), _OWNER_);
    }
    
    function changeOwner(address newOwner) public onlyOwner {
        emit OwnerSet(_OWNER_, newOwner);
        _OWNER_ = newOwner;
    }

    function getOwner() external view returns (address) {
        return _OWNER_;
    }
    
    function setBlack(address user,uint8 isBlack) public onlyOwner {
        blackList[user] = isBlack;
    }  
    
    function setLock(uint8 safeLock,uint8 pauseLock, uint256 startTime) public onlyOwner {
        _SAFE_LOCK_ = safeLock;
        _PAUSE_LOCK_ = pauseLock;
        _START_TIME_ = startTime;
    }    
}