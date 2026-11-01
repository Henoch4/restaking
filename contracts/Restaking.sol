// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract ReentrancyGuard {
    bool private _nonReentrant;
    constructor() { _nonReentrant = false; }
    modifier nonReentrant() {
        require(!_nonReentrant, "ReentrancyGuard: reentrant call");
        _nonReentrant = true;
        _;
        _nonReentrant = false;
    }
}
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), _owner); }
    modifier onlyOwner() { require(_owner == msg.sender, "Ownable: caller is not the owner"); _; }
    function owner() public view returns (address) { return _owner; }
}

contract Restaking is ReentrancyGuard, Ownable {
    struct Restake {
        address user;
        address asset;
        uint256 amount;
        uint256 shares;
        uint256 stakedAt;
        bool active;
    }
    Restake[] public restakes;
    mapping(address => uint256[]) public userRestakes;
    uint256 public restakeCount;
    uint256 public totalRestaked;
    uint256 public rewardRateBps;

    event Restaked(address indexed user, address asset, uint256 amount, uint256 shares);
    event Unrestaked(address indexed user, address asset, uint256 amount);
    event RewardRateUpdated(uint256 newRate);

    function restake(address asset, uint256 amount) external payable nonReentrant returns (uint256) {
        require(amount > 0, "Zero amount");
        require(msg.value == amount, "Incorrect amount");
        uint256 shares = amount;
        Restake storage r = restakes.push();
        r.user = msg.sender;
        r.asset = asset;
        r.amount = amount;
        r.shares = shares;
        r.stakedAt = block.timestamp;
        r.active = true;
        uint256 rid = restakes.length - 1;
        restakeCount = rid + 1;
        userRestakes[msg.sender].push(rid);
        totalRestaked += amount;
        emit Restaked(msg.sender, asset, amount, shares);
        return rid;
    }

    function unrestake(uint256 rid) external nonReentrant {
        Restake storage r = restakes[rid];
        require(r.active, "Not active");
        require(r.user == msg.sender, "Not your restake");
        r.active = false;
        totalRestaked -= r.amount;
        // FIX: unrestake flipped `active` and updated accounting but never sent
        // the ETH back — one-way lockbox. Pay the unstaker from the vault.
        uint256 amount = r.amount;
        require(address(this).balance >= amount, "Insufficient vault");
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "ETH transfer failed");
        emit Unrestaked(msg.sender, r.asset, amount);
    }

    function updateRewardRate(uint256 newRate) external onlyOwner {
        rewardRateBps = newRate;
    }

    function getRestake(uint256 rid) external view returns (address user, address asset, uint256 amount, uint256 shares, uint256 stakedAt, bool active) {
        Restake storage r = restakes[rid];
        return (r.user, r.asset, r.amount, r.shares, r.stakedAt, r.active);
    }
    function getTotalRestaked() external view returns (uint256) { return totalRestaked; }
}
