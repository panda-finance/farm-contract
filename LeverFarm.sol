// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import {IERC20} from "./intf/IERC20.sol";
import {SafeERC20} from "./lib/SafeERC20.sol";
import {SafeMath} from "./lib/SafeMath.sol";
import {DecimalMath} from "./lib/DecimalMath.sol";
import {ReentrancyGuard} from "./lib/ReentrancyGuard.sol";
import {OwnerGuard} from "./lib/OwnerGuard.sol";

contract LeverFarm is ReentrancyGuard,OwnerGuard{
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    uint256 _MAX_ROUND_ = 100;
    uint256 _REFER_RATE_ = 10;
    uint256 _PUMP_RATE = 70;
    uint256 constant _FEE_DECIMAL_ = 10000;
    uint256 constant _DAY_SEC_ = 86400;
    bool _INITED_ = false;
    
    address _ETH_ADDRESS_ = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    
    //address _STAKE_TOKEN_ADDRESS_ = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    //address _FARM_TOKEN_ADDRESS_ = 0xfF9c7aC77c29E030cAfe7256F5c3c4b84B8B5b01;
    address _PUMP_ADDRESS_ = 0x7cD683B2BEa2cb8E8cf0A41F3Cf52daEB659a92c;
    address _DEV_ADDRESS_ = 0x7cD683B2BEa2cb8E8cf0A41F3Cf52daEB659a92c;
    
    uint256 ONE = 1000000000000000000;
    uint256 MAX_AMOUNT = 1000000000000000000000000000;
    
    PoolInfo public poolInfo;
    mapping(uint256 => RoundInfo) public roundInfos;
    mapping(address => UserInfo) public userInfos;
    
    struct PoolInfo{
        address stakeTokenAddress;
        address farmTokenAddress;
        address feeAddress;
        uint256 curRound;
        uint256 maxRound;
        uint256 farmDeposit;
        uint256 farmProducted;
        uint256 maxFee;
        uint256 lastOpTime;
        uint256 keys;
        uint256 mask;   
    }
    
    struct RoundInfo{
        uint256 startTime;
        uint256 endTime;
        uint256 farmPerSec;
    }
    
    struct UserInfo{
        uint256 tokenDeposit;
        uint256 tokenReserved;
        uint256 feePerDay;
        uint256 lastOpTime;
        address referAddress;
        uint256 keys;
        uint256 mask;        
    }    
    
    function getPoolInfo() external view returns (PoolInfo memory pool) {
        pool = poolInfo;
    }
    function getRoundInfo(uint256 inx) external view returns (RoundInfo memory roundInfo) {
        roundInfo = roundInfos[inx];
    }    
    function getUserInfo(address user) external view returns (UserInfo memory userInfo) {
        userInfo = userInfos[user];
    }
    
    function getSelfAddress() external view returns (address addr) {
        addr=address(this);
    }    
    
    function init(address stakeTokenAddress,
                address farmTokenAddress,
                address feeAddress,
                uint256 startTime,
                uint256 endTime,
                uint256 farmPerSec) public onlyOwner {
        require(!_INITED_,"already inited");
        _INITED_ = true;
        require(endTime>startTime,"!endTime");
        RoundInfo memory roundInfo = RoundInfo(startTime,endTime,farmPerSec);
        roundInfos[1]=roundInfo;
        poolInfo.stakeTokenAddress=stakeTokenAddress;
        poolInfo.farmTokenAddress=farmTokenAddress;
        poolInfo.feeAddress=feeAddress;
        poolInfo.curRound=1;
        poolInfo.maxRound=1;
        poolInfo.lastOpTime = startTime;
    }
    
    function setRound(uint256 inx,
                uint256 startTime,
                uint256 endTime,
                uint256 farmPerSec) public onlyOwner {
        
        RoundInfo memory roundInfoNext = roundInfos[inx.add(1)];
        if(roundInfoNext.startTime>0){
            require(endTime<=roundInfoNext.startTime,"!endTime");
        }
        if(inx>1){
            RoundInfo memory roundInfoPre = roundInfos[inx.sub(1)];
            if(roundInfoPre.endTime>0){
                require(startTime>=roundInfoPre.endTime,"!startTime");
            }                
        }
        RoundInfo storage roundInfo = roundInfos[inx];
        require(roundInfo.startTime > 0,"round not found");
        roundInfo.startTime=startTime;
        roundInfo.endTime=endTime;
        roundInfo.farmPerSec=farmPerSec;
    }
    
    function addRound(
                uint256 startTime,
                uint256 endTime,
                uint256 farmPerSec) public onlyOwner {
        uint256 newRoundInx = poolInfo.maxRound.add(1);
        require(roundInfos[poolInfo.maxRound].endTime<=startTime,"!startTime");
        require(endTime>startTime,"!endTime");
        roundInfos[newRoundInx].startTime = startTime;
        roundInfos[newRoundInx].endTime = endTime;
        roundInfos[newRoundInx].farmPerSec = farmPerSec;
        poolInfo.maxRound=newRoundInx;
    }

    function mockLastOpTime(uint256 lastOpTime) public onlyOwner {
        userInfos[msg.sender].lastOpTime = lastOpTime;
        poolInfo.lastOpTime = lastOpTime;
    }    
    
    function calTimeFly(uint256 nowSec,address user) public view
    returns(uint256 farmProduct,uint256 userTimeFly,uint256 newLastOpTime,uint256 nowRound) {
        UserInfo memory userInfo = userInfos[user];
        uint256 userLastOpTime = userInfo.lastOpTime;
        uint256 poolLastOpTime = poolInfo.lastOpTime;
        require(nowSec>=userLastOpTime,"!userLastOpTime");
        require(nowSec>=poolLastOpTime,"!poolLastOpTime");
        
        farmProduct = 0;
        userTimeFly = 0;
        newLastOpTime = userLastOpTime > poolLastOpTime ? userLastOpTime:poolLastOpTime;
        nowRound = poolInfo.curRound;
        if(poolInfo.keys>0){
            for(uint256 inx = 1;inx <= poolInfo.maxRound; inx++){
                RoundInfo memory roundInfo = roundInfos[inx];
                if(roundInfo.startTime < 1){
                    break;
                }
            
                uint256 startTime = roundInfo.startTime;
                uint256 endTime = roundInfo.endTime;
                uint256 farmPerSec = roundInfo.farmPerSec;
            
                if(userLastOpTime >= startTime && userLastOpTime < endTime){
                    userTimeFly = userTimeFly.add(endTime.sub(userLastOpTime));
                }else if(userLastOpTime < startTime){
                    userTimeFly = userTimeFly.add(endTime.sub(startTime));
                }
            
                if(poolLastOpTime >= startTime && poolLastOpTime < endTime){
                    farmProduct = farmProduct.add(farmPerSec.mul(endTime.sub(poolLastOpTime)));
                }else if(poolLastOpTime < startTime){
                    farmProduct = farmProduct.add(farmPerSec.mul(endTime.sub(startTime)));
                }
            
                newLastOpTime = nowSec >= endTime ? endTime:nowSec;
            
                if(nowSec >= startTime && nowSec < endTime){
                    uint256 delt = endTime.sub(nowSec);
                    farmProduct = farmProduct.sub(farmPerSec.mul(delt));
                    userTimeFly = userTimeFly.sub(delt);
                    nowRound=inx;
                }else if(nowSec < startTime){
                    uint256 delt = endTime.sub(startTime);
                    farmProduct = farmProduct.sub(farmPerSec.mul(delt));
                    userTimeFly = userTimeFly.sub(delt);                
                }
            }
        }
    }    
    
    function tickFarmView(uint256 nowSec, address user) public view 
    returns(uint256 poolMask,uint256 farmProducted,uint256 lastOpTime,uint256 taxFee,uint256 debt){
        uint256 farmProduct;
        uint256 userTimeFly;
        uint256 newLastOpTime;
        uint256 nowRound;
        (farmProduct,userTimeFly,newLastOpTime,nowRound)=calTimeFly(nowSec,user);
        if(farmProduct > 0 && poolInfo.keys > 0){
            uint256 profitPerKey = DecimalMath.divFloor(farmProduct,poolInfo.keys);
            poolMask = poolInfo.mask.add(profitPerKey);     
            farmProducted = poolInfo.farmProducted.add(farmProduct);
        }
        lastOpTime = newLastOpTime;
        //
        UserInfo memory userInfo = userInfos[user];
        if(userTimeFly > 0 && userInfo.tokenDeposit > 0 && userInfo.feePerDay > 0){
            taxFee
                = userInfo.tokenDeposit.mul(userInfo.feePerDay).mul(userTimeFly).div(_FEE_DECIMAL_).div(_DAY_SEC_);
            if(taxFee > userInfo.tokenReserved){
                debt = taxFee.sub(userInfo.tokenReserved);
            } 
        }
    }
    
    function _tickFarm(uint256 amount) private{
        uint256 poolMask;
        uint256 farmProducted;
        uint256 lastOpTime;
        uint256 taxFee;
        uint256 debt;
        (poolMask,farmProducted,lastOpTime,taxFee,debt) = tickFarmView(block.timestamp, msg.sender);
        require(poolMask >= poolInfo.mask,"!poolMask");
        require(farmProducted >= poolInfo.farmProducted,"!farmProducted");
        require(lastOpTime >= poolInfo.lastOpTime,"!lastOpTime");
        require(taxFee >= 0,"!taxFee");
        poolInfo.mask = poolMask;
        poolInfo.farmProducted = farmProducted;
        poolInfo.lastOpTime = lastOpTime;
        //
        UserInfo storage userInfo = userInfos[msg.sender];
        userInfo.lastOpTime = lastOpTime;
        //
        uint256 amountIn = amount.add(debt);
        if(amountIn>0){
            uint256 realAmountIn = _transferTokenIn(poolInfo.stakeTokenAddress,amountIn);
            require(realAmountIn>=amountIn,"!amount");
            userInfo.tokenDeposit = userInfo.tokenDeposit.add(amount);
            userInfo.tokenReserved = userInfo.tokenReserved.add(realAmountIn).sub(taxFee);            
        }
        //
        if(taxFee>0){
            uint256 devFee = 0;
            uint256 referFee = 0;
            uint256 pumpFee = taxFee.mul(_PUMP_RATE).div(100);
            if(userInfo.referAddress != address(0)){
                referFee = taxFee.mul(_REFER_RATE_).div(100);
                _transferTokenTo(poolInfo.stakeTokenAddress,userInfo.referAddress,referFee);
            }
            devFee = taxFee.sub(pumpFee).sub(referFee);
            _transferTokenTo(poolInfo.stakeTokenAddress,_DEV_ADDRESS_,devFee);
            _transferTokenTo(poolInfo.stakeTokenAddress,_PUMP_ADDRESS_,pumpFee);
        }   
    }
    
    function stake(uint256 amount,uint256 feePerDay,address refer) public payable{
        UserInfo storage userInfo = userInfos[msg.sender];
        _tickFarm(amount);
        require(feePerDay >= userInfo.feePerDay && feePerDay <= poolInfo.maxFee,"!maxFee");
        userInfo.feePerDay = feePerDay;
        //禁止减少质押，禁止降低杠杆率，如要降低，可以全部赎回后重新质押
        if(amount>0){
            uint256 keys = 0;
            uint256 totalKeys = userInfo.tokenDeposit.mul(feePerDay);
            keys = totalKeys.sub(userInfo.keys);
            poolInfo.keys = poolInfo.keys.add(keys);
            userInfo.keys = userInfo.keys.add(keys);
            userInfo.mask = userInfo.mask.add(poolInfo.mask.mul(keys));            
        }
        if(userInfo.referAddress == address(0) && refer != address(0)){
            userInfo.referAddress=refer;
        }
    }
    
    function unstake() public payable{
        UserInfo storage userInfo = userInfos[msg.sender];
        _tickFarm(0);
        uint256 profit = (poolInfo.mask.mul(userInfo.keys)).sub(userInfo.mask);
        userInfo.mask=poolInfo.mask.mul(userInfo.keys);
        poolInfo.keys = poolInfo.keys.sub(userInfo.keys);
        userInfo.tokenDeposit = 0;
        if(userInfo.tokenReserved > 0){
            _transferTokenOut(poolInfo.stakeTokenAddress,userInfo.tokenReserved);
        }
        userInfo.tokenReserved = 0;
        userInfo.feePerDay = 0;
        userInfo.lastOpTime = 0;
        userInfo.keys = 0;
        userInfo.mask = 0;
        if(profit>0){
            _transferTokenOut(poolInfo.farmTokenAddress,profit);
        }        
    }
    
    function havest() public payable{
        UserInfo storage userInfo = userInfos[msg.sender];
        _tickFarm(0);
        uint256 profit = (poolInfo.mask.mul(userInfo.keys)).sub(userInfo.mask);
        userInfo.mask=poolInfo.mask.mul(userInfo.keys);
        if(profit>0){
            _transferTokenOut(poolInfo.farmTokenAddress,profit);
        }   
    }
    
    function _transferTokenIn(address tokenAddress, uint256 amount) internal returns(uint256){
        require(msg.sender != address(this),"from != to");
        if(tokenAddress == _ETH_ADDRESS_){
            amount = msg.value;
        }else if(amount > 0){
            IERC20 token = IERC20(tokenAddress);
            token.safeTransferFrom(msg.sender,address(this), amount);
        }  
        return amount;
    }
    
    function _transferTokenOut(address tokenAddress, uint256 amount) internal returns(uint256){
        require(msg.sender != address(this),"from != to");
        if(amount>0){
            if(tokenAddress == _ETH_ADDRESS_){
                (bool success,) = msg.sender.call{value:amount}(new bytes(0));
                require(success,"transfer fail");
                //msg.sender.transfer(amount);
            }else{
                IERC20 token = IERC20(tokenAddress);
                token.safeTransfer(msg.sender, amount);
            }
        }
        return amount;
    }
    
    function _transferTokenTo(address tokenAddress, address to, uint256 amount) internal returns(uint256){
        if(amount>0){
            if(tokenAddress == _ETH_ADDRESS_){
                //address payable addr = address(uint160(to));
                //addr.transfer(amount);
                (bool success,) = to.call{value:amount}(new bytes(0));
                require(success,"transfer fail");
            }else if(amount > 0){
                IERC20 token = IERC20(tokenAddress);
                token.safeTransfer(to, amount);
            }              
        }
        return amount;
    }

    function _approveMax(
        address tokenAddress,
        address to,
        uint256 amount
    ) internal {
        IERC20 token = IERC20(tokenAddress);
        uint256 allowance = token.allowance(address(this), to);
        if (allowance < amount) {
            if (allowance > 0) {
                token.safeApprove(to, 0);
            }
            token.safeApprove(to, uint256(-1));
        }
    }
    
    function transferTokenIn(address tokenAddress, uint256 amount) 
    public payable onlyOwner returns(uint256){
        return _transferTokenIn(tokenAddress,amount);
    }
    
    function transferTokenOut(address tokenAddress, uint256 amount) 
    public onlyOwner returns(uint256){
        return _transferTokenOut(tokenAddress,amount);
    }
    
    function transferTokenTo(address tokenAddress, address to, uint256 amount) 
    public onlyOwner returns(uint256){
        return _transferTokenTo(tokenAddress,to,amount);
    }    
}








