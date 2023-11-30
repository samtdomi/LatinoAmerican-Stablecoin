// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Engine} from "../src/Engine.sol";
import {LAT} from "../src/LAT.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Script, console} from "lib/forge-std/src/Script.sol";

contract DeployLAT is Script {
    /* ENGINE CONSTRUCTOR PARAMTERS */
    address[] public collateralTokens;
    address[] public priceFeeds;
    address public latAddress;

    /**
     * @notice in the Deploy script, the RUN function is the function where all of the deploy
     * logic is written and executed.
     * @notice the purpose of this deploy script is to populate the LAT Stablecoin smart contracts
     * with the necessary and correct information at the time of deployment so the logic of those
     * contracts work as intended. Constructors will be passed in the correct Arguments
     * @return LAT, Engine, HelperConfig contracts (not addresses) the actual contracts for the purpose
     * of using them in our Test's
     */
    function run() external returns (LAT, Engine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (
            address wethAddress,
            address wbtcAddress,
            address ethUsdPriceFeed,
            address btcUsdPriceFeed
        ) = helperConfig.networkConfig();

        // Engine Constructor Paramaters Populated IN ORDER
        collateralTokens.push(wethAddress);
        collateralTokens.push(wbtcAddress);
        priceFeeds.push(ethUsdPriceFeed);
        priceFeeds.push(btcUsdPriceFeed);

        vm.startBroadcast();

        // Deploy the LAT contract , initial ownership has to be declared, so the owner will
        // be this Deploy contract, and then after deployment of ENGINE - transfer ownership of
        // LAT contract to the ENGINE contract
        LAT lat = new LAT();

        // Deploy ENGINE contract, pass in the correct constructor arguments
        Engine engine = new Engine(collateralTokens, priceFeeds, latAddress);
        address engineAddress = address(engine);

        // Transfer ownership of LAT contract to the ENGINE contract
        // so the ENGINE contract can be the owner of LAT
        // lat.transferOwnership(engineAddress);

        vm.stopBroadcast();

        return (lat, engine, helperConfig);
    }
}
