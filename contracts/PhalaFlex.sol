// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./PhatRollupAnchor.sol";

contract PhalaFlex is PhatRollupAnchor, Ownable {
    event ResponseReceived(uint reqId, address user, uint256 value);
    event ErrorReceived(uint reqId, address user, uint256 errno);
    event InvalidOTP(uint256 reqId, address user);
    event SuccessOTP(uint256 reqId, address user);
    event AccountCreated(
        string authyHash,
        address Beneficiary,
        uint256 createdAt
    );
    event TokenStaked(address user, Token token, uint256 amount);
    event NativeStaked(address user, uint256 amount);
    event TokenWithdrawn(
        address user,
        Token token,
        uint256 amount,
        bool isBeneficiary
    );
    event NativeWithdrawn(address user, uint256 amount, bool isBeneficiary);
    event AuthyHashUpdated(address user, string newAuthyHash);
    event BeneficiaryUpdated(address user, address newBeneficiary);
    event LockedCannotAccess(address user);

    enum Token {
        dUSD
    }

    struct Account {
        uint256 createdAt;
        string authyHash;
        bool isUnlocked;
        uint256 lastUnlockedTime;
        address beneficiary;
    }

    uint256 constant TYPE_RESPONSE = 0;
    uint256 constant TYPE_ERROR = 2;

    mapping(address => Account) public accounts;
    mapping(address => mapping(Token => uint256)) private _tokenBalances;
    mapping(address => uint256) private _nativeBalances;
    mapping(Token => IERC20) internal TokenContract;
    mapping(Token => address) public TokenContractAddress;
    mapping(address => address) public beneficiaryUserMap;

    mapping(uint => address) private requests;
    uint256 nextRequest = 1;

    uint256 public constant timeLimit = 15 * 60;

    error lockedCannotAccess(address user);
    error AccountAlreadyExist(address user);

    constructor(address phatAttestor) {
        _grantRole(PhatRollupAnchor.ATTESTOR_ROLE, phatAttestor);

        TokenContract[Token.dUSD] = IERC20(
            0x2882CE9eC73cd80AB6c048C030BDa65fd3A0263A
        );
        TokenContractAddress[
            Token.dUSD
        ] = 0x2882CE9eC73cd80AB6c048C030BDa65fd3A0263A;
    }

    function setAttestor(address phatAttestor) public {
        _grantRole(PhatRollupAnchor.ATTESTOR_ROLE, phatAttestor);
    }

    function tokenBalanceOf(
        address user,
        Token token
    ) public view returns (uint256 balance) {
        balance = _tokenBalances[user][token];
    }

    function nativeBalanceOf(
        address user
    ) public view returns (uint256 balance) {
        balance = _nativeBalances[user];
    }

    function checkLock(address _user) public view returns (bool) {
        if (
            accounts[_user].lastUnlockedTime + timeLimit < block.timestamp ||
            !accounts[_user].isUnlocked
        ) return true;

        return false;
    }

    function checkIsUnlocked(address user) public view returns (bool) {
        return accounts[user].isUnlocked;
    }

    function getLastUnlockedTime(address user) public view returns (uint256) {
        return accounts[user].lastUnlockedTime;
    }

    function getBeneficiarysOwner(
        address beneficiary
    ) public view returns (address) {
        return beneficiaryUserMap[beneficiary];
    }

    function getBeneficiary(address user) public view returns (address) {
        return accounts[user].beneficiary;
    }

    function getTokenContractAddress(
        Token token
    ) public view returns (address) {
        return TokenContractAddress[token];
    }

    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function stakeToken(address _user, Token _token, uint256 _amount) public {
        require(_user == msg.sender, "user should be msg.sender");
        require(accounts[_user].createdAt > 0, "Account is not initialized!");

        IERC20 tokenContract = TokenContract[_token];

        require(
            tokenContract.allowance(_user, address(this)) >= _amount,
            "Insufficient allowance for the contract"
        );
        tokenContract.transferFrom(_user, address(this), _amount);

        _tokenBalances[_user][_token] += _amount;

        emit TokenStaked(_user, _token, _amount);
    }

    function stakeNative(address _user) public payable {
        require(_user == msg.sender, "user should be msg.sender");
        require(msg.value > 0, "native should be greater than 0");
        require(accounts[_user].createdAt > 0, "Account is not initialized!");

        (bool sent, ) = address(this).call{value: msg.value}("");
        require(sent, "Failed to send Native");

        _nativeBalances[_user] += msg.value;

        emit NativeStaked(_user, msg.value);
    }

    function withdrawToken(
        address _user,
        Token _token,
        uint256 _amount,
        bool _isBeneficiary
    ) external {
        require(_user == msg.sender, "user should be msg.sender");
        address user = _user;

        if (_isBeneficiary) {
            user = beneficiaryUserMap[_user];
        }

        if (checkLock(user)) {
            emit LockedCannotAccess(user);
            revert lockedCannotAccess(user);
        }

        IERC20 tokenContract = TokenContract[_token];

        uint256 balance = tokenBalanceOf(user, _token);

        require(balance >= _amount, "Amount is more than the balance");
        tokenContract.transfer(_user, _amount);

        _tokenBalances[user][_token] -= _amount;
        accounts[user].isUnlocked = false;

        emit TokenWithdrawn(_user, _token, _amount, _isBeneficiary);
    }

    function withdrawNative(
        address _user,
        uint256 _amount,
        bool _isBeneficiary
    ) external {
        require(_user == msg.sender, "user should be msg.sender");
        address user = _user;

        if (_isBeneficiary) {
            user = beneficiaryUserMap[_user];
            require(user != address(0), "No beneficiary found!");
        } else {
            require(
                accounts[user].createdAt > 0,
                "Account is not initialized!"
            );
        }

        if (checkLock(user)) {
            emit LockedCannotAccess(user);
            revert lockedCannotAccess(user);
        }

        uint256 balance = nativeBalanceOf(user);
        require(balance >= _amount, "Amount is more than the balance");

        (bool sent, ) = payable(_user).call{value: _amount}("");
        require(sent, "Failed to send Native");

        _nativeBalances[user] -= _amount;
        accounts[user].isUnlocked = false;

        emit NativeWithdrawn(_user, _amount, _isBeneficiary);
    }

    function setup(string calldata _authyHash, address _beneficiary) external {
        if (accounts[msg.sender].createdAt > 0) {
            revert AccountAlreadyExist(msg.sender);
        }

        accounts[msg.sender].authyHash = _authyHash;
        accounts[msg.sender].beneficiary = _beneficiary;
        accounts[msg.sender].createdAt = block.timestamp;
        beneficiaryUserMap[_beneficiary] = msg.sender;

        emit AccountCreated(
            _authyHash,
            _beneficiary,
            accounts[msg.sender].createdAt
        );
    }

    function updateAuthyHash(string calldata _newAuthyHash) external {
        if (checkLock(msg.sender)) {
            emit LockedCannotAccess(msg.sender);
            revert lockedCannotAccess(msg.sender);
        }
        accounts[msg.sender].authyHash = _newAuthyHash;
        accounts[msg.sender].isUnlocked = false;

        emit AuthyHashUpdated(msg.sender, _newAuthyHash);
    }

    function updateBeneficiary(address _newBeneficiary) external {
        if (checkLock(msg.sender)) {
            emit LockedCannotAccess(msg.sender);
            revert lockedCannotAccess(msg.sender);
        }

        accounts[msg.sender].beneficiary = _newBeneficiary;
        accounts[msg.sender].isUnlocked = false;

        emit BeneficiaryUpdated(msg.sender, _newBeneficiary);
    }

    function request(uint256 _otp, bool _isBeneficiary) public {
        address user = msg.sender;

        if (_isBeneficiary) {
            user = beneficiaryUserMap[msg.sender];
            require(user != address(0), "No beneficiary found!");
        } else {
            require(
                accounts[user].createdAt > 0,
                "Account is not initialized!"
            );
        }

        uint256 id = nextRequest;
        requests[id] = user;
        string memory userString = Strings.toHexString(
            uint256(uint160(user)),
            20
        );
        _pushMessage(
            abi.encode(id, _otp, userString, accounts[user].authyHash)
        );
        nextRequest += 1;
    }

    function _onMessageReceived(bytes calldata action) internal override {
        require(action.length == 32 * 3, "cannot parse action");
        (uint256 respType, uint256 id, uint256 data) = abi.decode(
            action,
            (uint256, uint256, uint256)
        );
        if (respType == TYPE_RESPONSE) {
            emit ResponseReceived(id, requests[id], data);
            address user = requests[id];

            if (data == 0) {
                emit InvalidOTP(id, user);
            } else if (data == 1) {
                accounts[user].isUnlocked = true;
                accounts[user].lastUnlockedTime = block.timestamp;
                emit SuccessOTP(id, user);
            }

            delete requests[id];
        } else if (respType == TYPE_ERROR) {
            emit ErrorReceived(id, requests[id], data);
            delete requests[id];
        }
    }

    receive() external payable {}

    fallback() external payable {}
}
