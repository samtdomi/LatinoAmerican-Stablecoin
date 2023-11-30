// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

/* Import Statements */
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {Script} from "lib/forge-std/src/Script.sol";

/* Contracts, Interfces, Libraries */
/**
 * @author Samuel Dominguez
 * @notice this contract is the helper config contract
 * that has the sole purpose of making the LAT stablecoin smart contracts able
 * to work on multiple blockchains
 * Accepted ERC20 Tokens: ETH, BTC
 * Compatible Blockchains: ETH MAINNET, SEPOLIA TESTNET, POLYGON MUMBAI TESTNET, POLYGON MAINNET, LOCAL ANVIL
 * for each blockchain accepted, this contrct will populate the corresponding wETH, wBTc
 *
 * for ANVIL Local Chain: Mock will be deployed to price mock token and act as mock pricefeed
 */

contract HelperConfig is Script {
    /** ERRORS */
    error HelperConfig__ChainNotAllowed();

    ///////////////////////////////
    ////   Type Declarations  /////
    ///////////////////////////////
    struct NetworkConfig {
        address wethAddress;
        address wbtcAddress;
        address ethUsdPriceFeed;
        address btcUsdPriceFeed;
    }
    ///////////////////////////////
    ////    State Variables   /////
    ///////////////////////////////
    NetworkConfig public networkConfig;

    ///////////////////////////////
    ////        Events        /////
    ///////////////////////////////

    //////////////////////////////////////////////////////////////////////////////////////
    ////       Functions      ////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////

    constructor() {
        if (block.chainid == 1) {
            networkConfig = EthMainnetConfig();
        } else if (block.chainid == 11155111) {
            networkConfig = SepoliaEthTestnetConfig();
        } else if (block.chainid == 31337) {
            networkConfig = AnvilConfig();
        } else if (block.chainid == 137) {
            networkConfig = PolygonMainnetConfig();
        } else if (block.chainid == 80001) {
            networkConfig = MumbaiPolygonTestnetConfig();
        }
    }

    /**
     * @dev all inputs for ETH MAINNET
     */
    function EthMainnetConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory ethMainnetConfig = NetworkConfig({
            wethAddress: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            wbtcAddress: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            ethUsdPriceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
            btcUsdPriceFeed: 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c
        });

        return ethMainnetConfig;
    }

    /**
     * @dev all inputs for ETH SEPOLIA TESTNET
     */
    function SepoliaEthTestnetConfig()
        public
        view
        returns (NetworkConfig memory)
    {
        NetworkConfig memory sepoliaConfig = NetworkConfig({
            wethAddress: 0xf531B8F309Be94191af87605CfBf600D71C2cFe0,
            wbtcAddress: 0xE6D22d565C860Bbeb2B411dFce91dD4B8F318594,
            ethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            btcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43
        });

        return sepoliaConfig;
    }

    /**
     * @dev all inputs for POLYGON MAINNET
     */
    function PolygonMainnetConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory polygonConfig = NetworkConfig({
            wethAddress: 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619,
            wbtcAddress: 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6,
            ethUsdPriceFeed: 0xF9680D99D6C9589e2a93a78A04A279e509205945,
            btcUsdPriceFeed: 0xc907E116054Ad103354f2D350FD2514433D57F6f
        });

        return polygonConfig;
    }

    /**
     * @dev all inputs for Polygon Mumbi Testnet
     */
    function MumbaiPolygonTestnetConfig()
        public
        pure
        returns (NetworkConfig memory)
    {
        NetworkConfig memory mumbaiPolygonConfig = NetworkConfig({
            wethAddress: 0xb4ee6879Ba231824651991C8F0a34Af4d6BFca6a,
            wbtcAddress: 0xCF6BC4Ae4a99C539353E4BF4C80fff296413CeeA,
            ethUsdPriceFeed: 0x0715A7794a1dc8e42615F059dD6e406A6594651A,
            btcUsdPriceFeed: 0x007A22900a3B98143368Bd5906f8E17e9867581b
        });

        return mumbaiPolygonConfig;
    }

    /**
     * @dev ANVIL TESTNET MOCKS
     */
    function AnvilConfig() public returns (NetworkConfig memory) {
        uint8 Decimals = 8;
        int256 EthUsdPrice = 1000e8;
        int256 BtcUsdPrice = 1000e8;

        vm.startBroadcast();

        // creates new mock ETH price feed and giving ETH the price of $1,000 USD
        MockV3Aggregator ethMockPriceFeed = new MockV3Aggregator(
            Decimals,
            EthUsdPrice
        );
        // creates deploys mock wETH token to get wETH mock token address and assigns the user 500 wETH
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 500e8);

        // creates new mock BTC price feed and giving BTC price of $1,000 USD
        MockV3Aggregator btcUsdMockPriceFeed = new MockV3Aggregator(
            Decimals,
            BtcUsdPrice
        );
        // creates and deploys mock wBTC token to get wBTC mock token address and assigns the user 500 wBTC
        ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, 500e8);

        vm.stopBroadcast();

        NetworkConfig memory anvilConfig = NetworkConfig({
            wethAddress: address(wethMock),
            wbtcAddress: address(wbtcMock),
            ethUsdPriceFeed: address(ethMockPriceFeed),
            btcUsdPriceFeed: address(btcUsdMockPriceFeed)
        });

        return anvilConfig;
    }
}
