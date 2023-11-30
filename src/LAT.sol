// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

/* Import Statements */
import {ERC20Burnable, ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/* Error Declarations */
error LAT__BurnAmountExceedsAvailableBalance();
error LAT__CannotBurnZero();
error LAT__CannotBeZeroAddress();
error LAT__CannotMintZero();

/* Contracts, Interfces, Libraries */
/**
 * @title LATINOAMERICAN Stablecoin "LAT"
 * @author Samuel Dominguez
 * Collateral: Exogenous (wETH & wBTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD $
 *
 * This is the contract meant to be governed by "ENGINE" contract.
 * This contract is meant to be "OWNED" by the "ENGINE" contract.
 * This contract is an ERC20 token that can be minted and burned by the "ENGINE" contract
 */
contract LAT is ERC20Burnable {
    ///////////////////////////////
    ////   Type Declarations  /////
    ///////////////////////////////

    ///////////////////////////////
    ////    State Variables   /////
    ///////////////////////////////
    uint256 public immutable latNumber;

    ///////////////////////////////
    ////        Events        /////
    ///////////////////////////////

    ///////////////////////////////
    ////       Modifiers      /////
    ///////////////////////////////

    //////////////////////////////////////////////////////////////////////////////////////
    ////       Functions      ////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////
    constructor() ERC20("LatinoAmericanStablecoin", "LAT") {
        latNumber = 5;
    }

    function burn(uint256 _amount) public override {
        // record the balance of the user that is burning LAT
        // by calling "balnceOf" function from ERC20Burnable.sol
        uint256 balance = balanceOf(msg.sender);

        // burn amount has to be more than 0
        if (_amount <= 0) {
            revert LAT__CannotBurnZero();
        }
        // only burn if the amount to burn is less than their available balance
        if (balance < _amount) {
            revert LAT__BurnAmountExceedsAvailableBalance();
        }

        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external returns (bool) {
        if (_to == address(0)) {
            revert LAT__CannotBeZeroAddress();
        }
        if (_amount <= 0) {
            revert LAT__CannotMintZero();
        }

        // calls the "_mint" function from "ERC20 openzeppelin contract"
        // the "_mint" function creates the requested "amount" of "LAT" and transfers to the user calling this mint function
        _mint(_to, _amount);

        return true;
    }
}
