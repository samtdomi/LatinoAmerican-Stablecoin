// SPDX-License-Identifer: MIT

pragma solidity ^0.8.19;

/* Import Statements */
import {LAT} from "./LAT.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/* Error Declarations */
error Engine__UnequalTokensAndPriceFeeds();
error Engine__TokenNotAcceptedAsColateral();
error Engine__CollateralFailedToBeDeposited();
error Engine__HealthFactorBroken();
error Engine__UserHasZeroLAT();
error Engine__HealthFactorNotBroken();
error Engine__HealthFactorDidNotImproveAfterLiquidation();
error Engine__TransferFailed();
error Engine__InsufficientBalance();

/* Contracts, Interfaces, Libraries */
/**
 * @title Engine
 * @author Samuel Dominguez
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a
 * 1 token == $1 peg
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI, if DAI had no governance, no fees, and was only backed by
 * wETH and wBTC.
 *
 * It is similar to DAI, if DAI had no governance, no fees, and was only backed by
 * wETH and wBTC
 *
 * our DSC system should always be "Over-Collateralized"
 * at no point should the value of all collateral < = value of all the stablecoin
 *
 * @notice this contract is the core of the LAT stablecoin system. It handles all of the logic for minting and redeeming LAT, as well as depositing & withdrawing collateral.
 * @notice this contract is very loosely based on the MakerDAO DSS (DAI) system
 *
 */

contract Engine is ReentrancyGuard {
    ///////////////////////////////
    ////   Type Declarations  /////
    ///////////////////////////////
    LAT private immutable i_lat;

    ///////////////////////////////
    ////    State Variables   /////
    ///////////////////////////////
    address[] private s_collateralTokens;

    /// @dev maps the chainlink pricefeed for each acceptable ERC20 token
    mapping(address collateralToken => address priceFeed) private s_priceFeeds;
    /// @dev maps the amount of collateral a user has for each specific token (wBTC, wETH)
    mapping(address user => mapping(address collateralToken => uint256 amountCollateral))
        private s_userCollateralBalances;
    /// @dev maps the amount of "LAT" the user has
    mapping(address user => uint256 amountLat) private s_userLatAmount;

    /// @dev giving names to "Magic Numbers"
    uint256 private constant PRICEFEED_TEN_DECIMALS = 1e10;
    uint256 private constant PRICEFEED_EIGHTEEN_DECIMALS = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // this enforces 200% overCollateralized rule
    uint256 private constant LIQUIDATION_DIVIDE_HUNDRED = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // enforces rule of min health factor of 1
    uint256 private constant LIQUIDATION_BONUS_DISCOUNT = 10; // gives a 10% bonus to the liquidator

    ///////////////////////////////
    ////        Events        /////
    ///////////////////////////////
    event UserDepositedCollateral(address user, address token, uint256 amount);
    event CollateralRedeemed(
        address from,
        address to,
        address collateralToken,
        uint256 amount
    );

    ///////////////////////////////
    ////       Modifiers      /////
    ///////////////////////////////
    modifier valueMoreThanZero(uint256 _amount) {
        require(msg.value > 0);
        _;
    }

    modifier isAcceptedToken(address _token) {
        if (s_priceFeeds[_token] == address(0)) {
            revert Engine__TokenNotAcceptedAsColateral();
        }
        _;
    }

    //////////////////////////////////////////////////////////////////////////////////////
    ////       Functions      ////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////

    /**
     * @param _collateralTokens are the addresses of the ERC20 tokens accepted as collateral
     * @param _priceFeeds are the addresses of the chainink pricefeeds IN SAME ORDER, for colalteral tokens
     * @param _lat the address of our LAT contract
     */
    constructor(
        address[] memory _collateralTokens,
        address[] memory _priceFeeds,
        address _lat
    ) {
        if (_collateralTokens.length != _priceFeeds.length) {
            revert Engine__UnequalTokensAndPriceFeeds();
        }

        for (uint256 i = 0; i < _collateralTokens.length; i++) {
            s_priceFeeds[_collateralTokens[i]] = _priceFeeds[i];
            s_collateralTokens.push(_collateralTokens[i]);
        }

        i_lat = LAT(_lat);
    }

    //////////////////////////////////////
    ////////   DEPOSITING   /////////////
    /////////////////////////////////////
    /**
     * @param _collateralToken is the address of the erc20 token being deposited as collateral
     * @param _amount is the amount of the specific token the user wants to deposit
     * @notice follows CEI - Checks, Effects, Interactions
     * @notice collateral is deposited from the user to THIS ENGINE contract
     * @dev mapping of user collateral balances is updated
     */
    function depositCollateral(
        address _collateralToken,
        uint256 _amount
    )
        public
        payable
        nonReentrant
        valueMoreThanZero(_amount)
        isAcceptedToken(_collateralToken)
    {
        s_userCollateralBalances[msg.sender][_collateralToken] += _amount;
        IERC20(_collateralToken).approve(address(this), _amount);
        bool success = IERC20(_collateralToken).transferFrom(
            msg.sender,
            address(this),
            _amount
        );

        if (!success) {
            revert Engine__CollateralFailedToBeDeposited();
        }

        emit UserDepositedCollateral(msg.sender, _collateralToken, _amount);
    }

    //////////////////////////////////////
    ////////   MINTING   ////////////////
    /////////////////////////////////////
    /**
     * Checks, Effects, Interactions
     * @param _amount is the amount the user wants to mint of LAT
     * @dev 1. update user LAT balance
     * 2. Check if the user health factor is acceptable with the new LAT to be minted
     * 3. If the new LAT ruins health factor, revert - else, allow user to MINT LAT
     */
    function mintLat(
        uint256 _amount
    ) public payable valueMoreThanZero(_amount) nonReentrant {
        s_userLatAmount[msg.sender] += _amount;
        revertIfHealthFactorBroken(msg.sender);
        i_lat.mint(msg.sender, _amount);
    }

    /**
     * @dev this function allows the user to deposit collateral and mint LAT in one transaction
     * @param _collateralToken is the address of the ERC20 token being deposited as collateral
     */
    function depositCollateralAndMintLat(
        address _collateralToken,
        uint256 _collateralAmount,
        uint256 _latAmount
    ) public payable nonReentrant valueMoreThanZero(_collateralAmount) {
        // 1. Allow User To Deposit Collateral
        depositCollateral(_collateralToken, _collateralAmount);
        // 2. Allow user to mint if their health factor is not broken after
        // updating their balance of LAT prior to minting to ensure health factor is not broken
        mintLat(_latAmount);
    }

    //////////////////////////////////////
    /////     REEDEEM COLLATERAL    //////
    /////////////////////////////////////
    /**
     * @dev Checks, Effects, Interactions !!!!!!!!!!!!!!!!!
     * @dev this is to be as an internal function, to be called by public functions
     * @param _user is the user who wants to redeem their collateral
     * @param _collateralToken address of the collateral ERC20 token being redeemed
     * @param _collateralAmount amount of the ERC20 user wnats to redeem
     */
    function _redeemCollateral(
        address _user,
        address _collateralToken,
        uint256 _collateralAmount
    ) internal nonReentrant valueMoreThanZero(_collateralAmount) {
        // 1. Checks: update the user balance if the requested amount of collateral is available in their balance
        if (
            s_userCollateralBalances[_user][_collateralToken] <
            _collateralAmount
        ) {
            revert Engine__InsufficientBalance();
        }

        s_userCollateralBalances[_user][_collateralToken] -= _collateralAmount;

        // 2. Effects: enusre the updated balances do not break the user's health factor
        revertIfHealthFactorBroken(_user);

        // 3. Interactions: If health factor not broken, transfer ERC20 collateral FROM ENGINE, TO USER
        bool success = IERC20(_collateralToken).transfer(
            _user,
            _collateralAmount
        );
        if (!success) {
            revert Engine__TransferFailed();
        }
    }

    /**
     * @dev this is the public function to be used when a user wants to redeem collateral
     * @param _collateralToken is the address of the ERC20 collatera token
     * @param _collateralAmount the amount of collateral
     *
     */
    function redeemCollateral(
        address _collateralToken,
        uint256 _collateralAmount
    ) public payable nonReentrant valueMoreThanZero(_collateralAmount) {
        _redeemCollateral(msg.sender, _collateralToken, _collateralAmount);
    }

    /**
     *
     * @notice this function allows a user to burn LAT and then redeem collateral in 1 transaction
     * @param _collateralToken is the address of the ERC20 collteral token
     * @param _collateralAmount is the amount of collateral to redeem
     * @param _burnLatAmount is the amount of LAT user wants to burn
     */
    function redeemCollateralForLat(
        address _collateralToken,
        uint256 _collateralAmount,
        uint256 _burnLatAmount
    ) public payable nonReentrant valueMoreThanZero(_collateralAmount) {
        // 1. Step one has to be to burn the LAT, so the user health factor does not break
        // and then not allow the user to redeem collateral
        _burnLat(msg.sender, msg.sender, _burnLatAmount);

        // 2. redeem collateral for the user
        _redeemCollateral(msg.sender, _collateralToken, _collateralAmount);
    }

    //////////////////////////////////////
    /////  USER ACCOUNT INFORMATION //////
    /////////////////////////////////////
    /**
     * @dev returns the account information of the user
     * @dev calls a different funtion to retrieve the total collateral value for the user
     * @param _user is the user who's ccount information we will get
     */
    function _getAccountInformation(
        address _user
    ) internal returns (uint256 userLatValue, uint256 userCollateralValueUsd) {
        userLatValue = s_userLatAmount[_user];
        userCollateralValueUsd = getAccountCollateralValue(_user);

        return (userLatValue, userCollateralValueUsd);
    }

    /**
     * @dev calls a different funtion to calculate and retrieve USD value of collateral
     * @dev creates a for loop to get the user collateral balance for each possible token
     * and then calls to get the USD value of that collateral, and then adds it to the total
     * USD value of the user collateral
     * @param _user user
     */
    function getAccountCollateralValue(
        address _user
    ) internal returns (uint256 totalCollateralValueUsd) {
        uint256 totalCollateralValueUsd = 0;
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 userCollateral = s_userCollateralBalances[_user][token];
            totalCollateralValueUsd += _getUsdValue(token, userCollateral);
        }

        return totalCollateralValueUsd;
    }

    /**
     * @dev uses Chainlink Price Feeds to calculate current USD price and
     * then calculates the USD value of the collateral token
     * @dev need to add 10 decimals to returned value from cahinlink
     * @param _token the token to get the price of
     * @param _collateralValue the value of collateral the user has in the token
     */
    function _getUsdValue(
        address _token,
        uint256 _collateralValue
    ) public returns (uint256 usdValue) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[_token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint256 tokenUsdPrice = uint256(price) * PRICEFEED_TEN_DECIMALS;
        usdValue =
            (tokenUsdPrice * _collateralValue) /
            PRICEFEED_EIGHTEEN_DECIMALS;

        return usdValue;
    }

    //////////////////////////////////////
    ////////   HEALTH FACTOR   //////////
    /////////////////////////////////////

    /**
     * @dev calls _healthFactor and reverts if the health factor is broken
     * @param _user is the user who will have their health factor checked
     */
    function revertIfHealthFactorBroken(address _user) internal {
        uint256 healthFactor = _healthFactor(_user);

        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert Engine__HealthFactorBroken();
        }
    }

    /**
     * @dev this function will return the current health factor of the user
     * @dev calls a different function to do the computation of the health factor
     * @param _user user
     */
    function _healthFactor(address _user) internal returns (uint256) {
        (
            uint256 userLatValue,
            uint256 userCollateralValue
        ) = _getAccountInformation(_user);
        uint256 userHealthFactor = _calculateHealthFactor(
            userLatValue,
            userCollateralValue
        );
        return userHealthFactor;
    }

    /**
     * @dev This function caluculates the current health factor of the user
     * @param userLatValue is the amount of LAT the user currently has
     * @param userCollateralValue is the total USD value of collateral the user has
     * @dev the threshold for colalteral is 200% , the user must maintain a 200% OVER_COLLATERALZIED
     * position at all times.
     * Ex: userTotalCollateral = 10
     * the max LAT user can have and maintain a minimum health factor of 1 is 5 LAT
     * so to calculate healthFactor we must adjust the collateral amount to the health factor
     * if we dont, in this situation - the user would have (10 collateral, 5 LAT, and therefore a health factor of 2)
     * which allows the user to continue minting LAT up until 10 LAT (which would make healthFactor 1)
     * @dev formula for adjusting collateral to enforce 200% rule is (collateralAmount * 50) / 100
     */
    function _calculateHealthFactor(
        uint256 userLatValue,
        uint256 userCollateralValue
    ) internal pure returns (uint256) {
        if (userLatValue == 0) {
            revert Engine__UserHasZeroLAT();
        }

        uint256 collateralAdjustedForHealthFactor = (userCollateralValue *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_DIVIDE_HUNDRED;
        uint256 healthFactor = (collateralAdjustedForHealthFactor *
            PRICEFEED_EIGHTEEN_DECIMALS) / userLatValue;
        return healthFactor;
    }

    //////////////////////////////////////
    ////////    LIQUIDATE     ///////////
    /////////////////////////////////////
    /**
     * if user starts to get under-collateralized, allow anyone to liquidate their positions
     * we will pay anyone to liquidate uers under-collateralized positions
     * @notice the liquidator will receive the total collateral of the user being liquidated
     * and pay off / burn the DSC amount owned by the user being liquidated - and receive the
     * difference as profit
     * @param _collateralToken the address of the erc20 token used as collateral
     * @param _user the user to be liquidated
     * @param _debtToCover the amount of DSC you want to burn to improve the users healthFactor
     * @notice you CAN partially liquidate a user and improve their healthFactor
     * @notice you will get a liquidation bonus for taking a users funds (collateral - DSC)
     * @notice this function working assumes the protocol will be roughly 200%
     * over-collateralized in order for this to work.
     * @notice a known bug would be if the protocol were only 100% collateralized or less, then we
     * wouldnt be able to incentivize the liquidators
     * For example, if the price of the collateral plummeted before anyone could be liquidated
     */
    function liquidate(
        address _user,
        address _collateralToken,
        uint256 _debtToCover
    ) public payable valueMoreThanZero(_debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(_user);

        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert Engine__HealthFactorNotBroken();
        }

        // we want to burn their DSC ("debt") and take their Collateral
        // Bad User: $140 ETH , $100 DSC
        // debtToCover = $100
        // $100 of DSC == ?? ETH ? how many ETH tokens is $100 usd??
        // if ETH/USD price is $2,000/USD then the user's $100 DSC is worth .05 ETH
        uint256 tokenAmountOfDebt = _getTokenAmountOfDebt(
            _collateralToken,
            _debtToCover
        );
        // and give the liquidator a 10% bonus
        // So we are giving the liquidator $110 wETH for $100 DSC
        // We should implement a feature to liquidate in the event the protocol goes insolvent
        // and sweep extra amounts into a treasury
        // Bonus = 0.05 ETH * 10% = 0.005
        // Total to pay lqiuidator = 0.055 ETH   -----> 0.05 ETH  +  .005 ETH Bonus
        uint256 bonusCollateral = (tokenAmountOfDebt *
            (LIQUIDATION_BONUS_DISCOUNT / 100)); // 10 /100 = 10%
        uint256 totalCollateralToRedeem = tokenAmountOfDebt + bonusCollateral;
        // redeems collateral of the user being liquidated and sending to the LIQUIDATOR
        _redeemCollateralForLiquidation(
            _user,
            msg.sender,
            _collateralToken,
            totalCollateralToRedeem
        );

        // burn the amount of DSC that the user had before being liquidated
        // msg.sender (the liquidator) will pay the debtToCover amount onBehalfOf the USER being liquidated ,
        // after being transferred the user's collateral and bonus to liquidate.
        // liquidator gets paid the total collateral of the user being liquidated + bonus, then pays back the Users debt
        _burnLat(_user, msg.sender, _debtToCover);

        uint256 userEndingHealthFactor = _healthFactor(_user);

        if (userEndingHealthFactor <= startingUserHealthFactor) {
            revert Engine__HealthFactorDidNotImproveAfterLiquidation();
        }

        // if the liquidation ruined the LIQUIDATORS health factor, revert and dont let it go through
        revertIfHealthFactorBroken(msg.sender);
    }

    /**
     * @dev this function will calculate how many TOKENS the value of debt a user has in USD.
     *      if ETH/USD price is $2,000/USD then the user's $100 DSC is worth .05 ETH
     * @param _collateralToken is the ERC20 Token to be used as currency value
     * @param _debtToCover is the value of debt in USD
     */
    function _getTokenAmountOfDebt(
        address _collateralToken,
        uint256 _debtToCover
    ) public view returns (uint256) {
        address priceFeed = s_priceFeeds[_collateralToken];
        (, int256 price, , , ) = AggregatorV3Interface(priceFeed)
            .latestRoundData();
        uint256 tokenPriceInUsd = uint256(price) * PRICEFEED_TEN_DECIMALS;
        uint256 tokenDebtAmount = (_debtToCover / tokenPriceInUsd) *
            PRICEFEED_EIGHTEEN_DECIMALS;
        return tokenDebtAmount;
    }

    /**
     * @dev this function transfers collteral from Engine contract balance of the specific token to a user
     * @param  _to is the user the collateral will be transferred to
     * @param _collateralToken is the address of the specific token of collateral to be transferred
     * @param _amount is the token amount of collateral
     */
    function _redeemCollateralForLiquidation(
        address _from,
        address _to,
        address _collateralToken,
        uint256 _amount
    ) internal {
        // update user that is losing collateral balance
        s_userCollateralBalances[_from][_collateralToken] -= _amount;

        emit CollateralRedeemed(_from, _to, _collateralToken, _amount);

        bool success = IERC20(_collateralToken).transfer(_to, _amount);
        if (!success) {
            revert Engine__TransferFailed();
        }
    }

    /**
     *
     * @param _onBehalfOf is the user being Liquidated
     * @param _userPayingLat is the user doing the liquidation and pying the LAT that is owed
     * @param _debtToCover is the amount of debt the liquidator has to cover
     */
    function _burnLat(
        address _onBehalfOf,
        address _userPayingLat,
        uint256 _debtToCover
    ) internal {
        s_userLatAmount[_onBehalfOf] -= _debtToCover;
        // user doing the liquidation and paying off debt will transfer LAT to this ENGINE contract
        bool success = i_lat.transferFrom(
            _userPayingLat,
            address(this),
            _debtToCover
        );
        if (!success) {
            revert Engine__TransferFailed();
        }

        // now that the LAT debt has been covered by the liquidator and transferred to this ENGINE contract
        // this ENGINE contract will burn that amount by being the msg.sender of the burn function in LAT ERC20 contract
        i_lat.burn(_debtToCover);
    }

    //////////////////////////////////////
    ////////    BURNING     /////////////
    /////////////////////////////////////
    /**
     * @dev calls the internal function "_burn" from this same contract to execute
     * @dev transfers the amount of LAT to be burned from the user to this contract
     */
    function burn(uint256 _amount) public payable valueMoreThanZero(_amount) {
        _burnLat(msg.sender, msg.sender, _amount);
    }

    //////////////////////////////////////
    ////////    GETTER FUNCTIONS     /////
    /////////////////////////////////////
    function getUserCollateralAmountForSpecificToken(
        address _user,
        address _collateralToken
    ) public view returns (uint256) {
        uint256 collateralAmount = s_userCollateralBalances[_user][
            _collateralToken
        ];
        return collateralAmount;
    }

    function getUserAccountInformation(
        address _user
    ) public returns (uint256, uint256) {
        (uint256 latValue, uint256 collateralValue) = _getAccountInformation(
            _user
        );
        return (latValue, collateralValue);
    }

    function getCollateralTokens() public view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getSpecificTokenPriceFeed(
        address _collateralToken
    ) public view returns (address) {
        address priceFeed = s_priceFeeds[_collateralToken];
        return priceFeed;
    }
}
