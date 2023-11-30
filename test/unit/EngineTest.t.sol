// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {LAT} from "../../src/LAT.sol";
import {Engine} from "../../src/Engine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployLAT} from "../../script/DeployLAT.s.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract EngineUnitTest is Test {
    /** Type Declarations */
    LAT lat;
    Engine engine;
    HelperConfig helperConfig;
    DeployLAT deployLat;

    /** Engine Constructor Paramaters */
    address[] collateralTokens;
    address[] priceFeeds;
    address latAddress;

    /** HelperConfig Variables */
    address wethAddress;
    address wbtcAddress;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;

    /** State Variable Specifically Needed For Test's */
    address testUser = makeAddr("user");
    uint256 userStartingErc20Balance = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;

    /**
     * SETUP FUNCTION
     * 1. Runs deploys script which deploys and returns new:
     * 1a. LAT contract
     * 1b. Engine contract
     * 1c. HelperConfig contract
     * 2. Gets the correct address from the helperConfig for each collateral token and priceFeed
     * 3. mints mock wETH and sends the testUser 10 mock ether
     *
     * the purpose of the setUp() function is to set up all contracts and the correct information for the
     * deployment and deploy the smart contracts that are making up the project so that
     * we can test their functionality once actually deployed.
     * the setUp() function runs anew before every single test function so that every test
     * has brand new, as intended, deployed contracts to test specific functionality on
     */
    function setUp() public {
        deployLat = new DeployLAT();
        (lat, engine, helperConfig) = deployLat.run();
        (
            wethAddress,
            wbtcAddress,
            ethUsdPriceFeed,
            btcUsdPriceFeed
        ) = helperConfig.networkConfig();
        ERC20Mock(wethAddress).mint(testUser, userStartingErc20Balance);
    }

    /////////////////////////////////////////////////////////// these are tests's that test the
    ///////////       CONSTRUCTOR TEST'S       ///////////  ENGINE contract's constructor functionality
    //////////////////////////////////////////////////////////

    /**
     * @dev We are going to manually input only 1 collateral token address and 2 priceFeed addresses
     * to make the length unequal - they are supposed to be equal - and see if the contract\
     * catches the error and reverts
     */
    function testRevertsIfNotEqualAmountsOfTokensAndPriceFeeds() public {
        collateralTokens.push(wethAddress);
        priceFeeds = [ethUsdPriceFeed, btcUsdPriceFeed];
        vm.expectRevert();
        new Engine(collateralTokens, priceFeeds, address(lat));
    }

    function testPriceFeedMapping() public {
        address[] memory listTokens = engine.getCollateralTokens();
        address weth = listTokens[0];
        address wethFeed = engine.getSpecificTokenPriceFeed(weth);

        assertEq(wethFeed, ethUsdPriceFeed);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //////////////     Price Feed Test's    ///////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev if deploying to local chain (anvil) - the helperConfig will deploy mock
     * priceFeeds for ETH and BTC and make their price (1 ETH / $1,000) (1 BTC / $1,000)
     * calls _getUsdValue(token, collateralValue) from ENGINE contract
     * @dev set an initial ETH amount of 10 ETH to check if the price is correct
     */
    function testGetUsdValue() public {
        uint256 ethAmount = 10e18;
        uint256 expectedAmount = 10000e18;

        uint256 actualValue = engine._getUsdValue(wethAddress, ethAmount);
        console.log(actualValue);

        assertEq(expectedAmount, actualValue);
    }

    /**
     * @dev if deploying to local chain (anvil), the helperConfig will deploy
     * mock priceFeeds for ETH and BTC and make their price (1 ETH / $1,000) (1 BTC / $1,000)
     */
    function testGetTokenAmountFromUsd() public {
        uint256 initialUsdAmount = 2000e18;
        uint256 expectedAmount = 2e18;

        uint256 actualAmount = engine._getTokenAmountOfDebt(
            wethAddress,
            initialUsdAmount
        );

        assertEq(expectedAmount, actualAmount);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //////////////     depositCollateral's Test's    ///////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////

    modifier depositedCollateral() {
        vm.startPrank(testUser);
        ERC20Mock(wethAddress).approve(address(engine), 10 ether);
        engine.depositCollateral(wethAddress, 1 ether);
        vm.stopPrank();
        _;
    }

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(testUser);
        vm.expectRevert();
        engine.depositCollateral(wethAddress, 0);
    }

    function testRevertsWithUnnaprovedCollateralToken() public {
        vm.startPrank(testUser);
        ERC20Mock(wethAddress).approve(address(engine), 10 ether);
        vm.expectRevert();
        engine.depositCollateral(address(lat), 1 ether);
    }
} // End of ALL UNIT TEST's
