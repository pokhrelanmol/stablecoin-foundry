// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {TrieStableCoin} from "./TrieStableCoin.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title TSCEngine
 * @author Anmol Pokhrel
 * The System is designed to maintain the price of TrieStableCoin at $1.It is backed by WBTC and WETH.
 * This is the core contract of the system.
 */

contract TSCEngine is ReentrancyGuard {
    error DSCEngine__moreThanZero();
    error DSCEngine__tokenAddressAndPriceFeedAddressMustBeEqual();
    error DSCEngine__NotAllowedToken();
    error TSCEngine__TransferFail();
    error TSCEngine__BreaksHealthFactor(uint256 userHealthFactor);

    uint256 private constant ADDITIONAL_FEED_PRESCISION = 1e10; // just to make the the price feed compatible with the system
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% over collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    mapping(address user => uint256 amountTscMinted) private s_tscMinted;
    address[] private s_collateralTokens;
    TrieStableCoin immutable i_tsc;

    event CollateralDeposited(
        address indexed depositor,
        address indexed token,
        uint256 indexed amount
    );

    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__moreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _tokenAddress) {
        if (s_priceFeeds[_tokenAddress] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address tscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__tokenAddressAndPriceFeedAddressMustBeEqual();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_tsc = TrieStableCoin(tscAddress);
    }

    function depositCollateralAndMintTSC() external payable returns (bool) {}

    /**
     * @param tokenCollateralAddress address of the collateral token
     * @param _amountCollateral amount of collateral to be deposited
     */

    function depositCollaterals(
        address tokenCollateralAddress,
        uint256 _amountCollateral
    )
        external
        moreThanZero(_amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        address sender = msg.sender;
        s_collateralDeposited[sender][
            tokenCollateralAddress
        ] += _amountCollateral;
        emit CollateralDeposited(
            sender,
            tokenCollateralAddress,
            _amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            _amountCollateral
        );
        if (!success) {
            revert TSCEngine__TransferFail();
        }
    }

    function redeemCollateralForTsc() external returns (bool) {}

    function redeemCollateral() external returns (bool) {}

    /**
     *@param amountTscToMint of TSC to mint user can specify this
     *@dev this function will mint TSC on the basis of collateral deposited
     *@notice minter should have minimal treshold deposited before minting
     */
    function mintTsc(
        uint256 amountTscToMint
    ) external moreThanZero(amountTscToMint) {
        s_tscMinted[msg.sender] += amountTscToMint;
        _checkHealthFactor(msg.sender);

        // in order to mint we need to figure out the deposited collateral and its USD value and on the basis of that we gotta mint the token lets say 70% of collateral
    }

    function burnTsc() external returns (bool) {}

    function liquidate() external returns (bool) {}

    function getHealthFactor() external view returns (bool) {}

    /**********************
     * INTERNAL FUNCTIONS *
     **********************/

    /**
     *@param user address of the user
     *@dev this function will check the health factor of the user
     *@dev checks if the deposited collateral is less than the threshold
     */
    function _checkHealthFactor(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert TSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /**
     * Returns how close to liquidation a user is
     * if a user go below 1 then they can get liquidated
     */
    function _healthFactor(address user) internal view returns (uint256) {
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        uint256 collateralAdjustedForTreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // $1000 ETH and 100 TSC
        // collateralAdjustedForTreshold  = 1000 * 50 = 5000 / 100 = 500
        // return 500 / 100 = 5 (health factor) here it will do this with precision

        return (collateralAdjustedForTreshold * PRECISION) / totalDscMinted;
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_tscMinted[user];
        collateralValueInUsd = _getAccountCollateralValue(user);
    }

    function _getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint256 formattedPrice = (uint256(price) *
            ADDITIONAL_FEED_PRESCISION *
            amount) / 1e18;
    }
}
