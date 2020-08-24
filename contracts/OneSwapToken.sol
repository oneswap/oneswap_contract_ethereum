// SPDX-License-Identifier: GPL
pragma solidity ^0.6.6;

import "./interfaces/IOneSwapToken.sol";
import "./libraries/SafeMath256.sol";
import "./OneSwapBlackList.sol";

contract OneSwapToken is IOneSwapToken,OneSwapBlackList {

    using SafeMath256 for uint256;

    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;
    // solhint-disable-next-line state-visibility
    uint8 immutable _decimals;

    constructor (string memory name, string memory symbol, uint256 supply, uint8 decimals) public OneSwapBlackList() {
        _name = name;
        _symbol = symbol;
        _decimals = decimals;
        _totalSupply = supply;
        _balances[msg.sender] = supply;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender,
                _allowances[sender][msg.sender].sub(amount, "OneSwapToken: TRANSFER_AMOUNT_EXCEEDS_ALLOWANCE"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual override returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual override returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].sub(subtractedValue, "OneSwapToken: DECREASED_ALLOWANCE_BELOW_ZERO"));
        return true;
    }

    function burn(uint256 amount) public virtual override {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) public virtual override {
        uint256 decreasedAllowance = allowance(account, msg.sender).sub(amount, "OneSwapToken: BURN_AMOUNT_EXCEEDS_ALLOWANCE");

        _approve(account, msg.sender, decreasedAllowance);
        _burn(account, amount);
    }

    function multiTransfer(uint256[] calldata mixedAddrVal) public override returns (bool) {
        for (uint i = 0; i < mixedAddrVal.length; i++) {
            address to = address(mixedAddrVal[i]>>96);
            uint256 value = mixedAddrVal[i]&0xffffffffffff;
            _transfer(msg.sender,to,value);
        }
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "OneSwapToken: TRANSFER_FROM_THE_ZERO_ADDRESS");
        require(recipient != address(0), "OneSwapToken: TRANSFER_TO_THE_ZERO_ADDRESS");

        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(amount, "OneSwapToken: TRANSFER_AMOUNT_EXCEEDS_BALANCE");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "OneSwapToken: BURN_FROM_THE_ZERO_ADDRESS");

        _balances[account] = _balances[account].sub(amount, "OneSwapToken: BURN_AMOUNT_EXCEEDS_BALANCE");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "OneSwapToken: APPROVE_FROM_THE_ZERO_ADDRESS");
        require(spender != address(0), "OneSwapToken: APPROVE_TO_THE_ZERO_ADDRESS");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 ) internal virtual view {
        require(!isBlackListed(from), "OneSwapToken: FROM_IS_BLACKLISTED_BY_TOKEN_OWNER");
        require(!isBlackListed(to), "OneSwapToken: TO_IS_BLACKLISTED_BY_TOKEN_OWNER");
    }

}
