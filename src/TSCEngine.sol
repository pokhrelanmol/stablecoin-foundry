// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {TrieStableCoin} from "./TrieStableCoin.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

/**
 * @title TSCEngine
 * @author Anmol Pokhrel
 * The System is designed to maintain the price of TrieStableCoin at $1.It is backed by WBTC and WETH.
 * This is the core contract of the system.
 */

contract TSCEngine is ReentrancyGuard {
    /* --------------------------------- ERRORS --------------------------------- */

    error TSCEngine__MoreThanZero();
    error TSCEngine__TokenAddressAndPriceFeedAddressMustBeEqual();
    error TSCEngine__NotAllowedToken();
    error TSCEngine__TransferFail();
    error TSCEngine__BreaksHealthFactor(uint256 userHealthFactor);
    error TSCEngine__MintFailed();
    error TSCEngine__UserNotLiquidatable();
    error TSCEngine__HealthFactorNotImproved();

    /* ----------------------------- STATE VARIABLES ---------------------------- */

    uint256 private constant ADDITIONAL_FEED_PRESCISION = 1e10; // just to make the the price feed compatible with the system
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% over collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidator

    mapping(address token => address priceFeed) private s_priceFeeds; //solhint-disable-line
    mapping(address user => mapping(address token => uint256 amount)) // solhint-disable-line
        private s_collateralDeposited; //solhint-disable-line
    mapping(address user => uint256 amountTscMinted) private s_tscMinted; //solhint-disable-line
    address[] private s_collateralTokens; //solhint-disable-line
    TrieStableCoin immutable i_tsc; //solhint-disable-line

    /* ------------------------------- EVENTS --------------------------------- */

    event CollateralDeposited(address indexed depositor, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    /* -------------------------------- MODIFIERS ------------------------------- */
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert TSCEngine__MoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _tokenAddress) {
        if (s_priceFeeds[_tokenAddress] == address(0)) {
            revert TSCEngine__NotAllowedToken();
        }
        _;
    }
    /* -------------------------------------------------------------------------- */
    /*                                  FUNCTIONS                                 */
    /* -------------------------------------------------------------------------- */

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address tscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert TSCEngine__TokenAddressAndPriceFeedAddressMustBeEqual();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_tsc = TrieStableCoin(tscAddress);
    }
    /* ---------------------------- EXTERNAL FUNCTIONS--------------------------- */

    function depositCollateralAndMintTSC(address tokenCollateralAddress, uint256 amount, uint256 amountDscToMint)
        external
    {
        depositCollateral(tokenCollateralAddress, amount);
        mintTsc(amountDscToMint);
    }

    /**
     * @param tokenCollateralAddress address of the collateral token
     * @param _amountCollateral amount of collateral to be deposited
     */

    function depositCollateral(address tokenCollateralAddress, uint256 _amountCollateral)
        public
        moreThanZero(_amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        address sender = msg.sender;
        s_collateralDeposited[sender][tokenCollateralAddress] += _amountCollateral;
        emit CollateralDeposited(sender, tokenCollateralAddress, _amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);
        if (!success) {
            revert TSCEngine__TransferFail();
        }
    }

    function redeemCollateralForTsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountTscToBurn)
        external
    {
        burnTsc(amountTscToBurn);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _checkHealthFactor(msg.sender);

        // in order to redeem the follwoing should met
        // 1. user should have more than 1 health factor after collateral pulled
        //  _redeemCollateral(tokenCollateralAddress,amountCollateral,msg.sender,msg.sender);
        _checkHealthFactor(msg.sender);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _checkHealthFactor(msg.sender);
    }
    /**
     *
     * @param collateral erc20 collateral address to liquidate
     * @param user  user who has broken the health factor i.e userhealthfactor < MIN_HEALTH_FACTOR
     * @param debtToCover amount of TSC you want to burn to improve user healt factor
     * @notice you can partially liquidate the user
     * @notice you will get liquidation bonus taking the users fund
     * @notice this function workings assumes that the protocol is 200% over collateralized
     * @notice A known bug would be if the protocol is 100% or less collateralize then we wouldn't be able to incentive the liquidators.
     * for example of the price of collateral plummeted before anyone could be liquidated
     */

    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert TSCEngine__UserNotLiquidatable();
        }
        //  We want to burn their TSC debt
        // And take their collateral
        //Bad user: $140 ETH ,$100 TSC (should not pass healtfactor)
        // debtToCover = $100
        // $100 TSC == ?? ETH
        uint256 tokenAmountFromDebtCover = getTokenAmountFromUsd(collateral, debtToCover);
        // and give them 10% bonus
        // so we are giving liquidator $110 of Weth for 100 TSC
        uint256 bonusCollateral = tokenAmountFromDebtCover * LIQUIDATION_BONUS / LIQUIDATION_PRECISION;
        // 0.05 eth * 0.1 = 0.005 => getting 0.055 eth
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCover + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnTsc(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert TSCEngine__HealthFactorNotImproved();
        }
        _checkHealthFactor(msg.sender);
    }

    /* ---------------------------- PUBLIC FUNCTIONS ---------------------------- */

    /**
     * @param amountTscToMint of TSC to mint user can specify this
     * @dev this function will mint TSC on the basis of collateral deposited
     * @notice minter should have minimal treshold deposited before minting
     */

    function mintTsc(uint256 amountTscToMint) public moreThanZero(amountTscToMint) {
        s_tscMinted[msg.sender] += amountTscToMint;
        _checkHealthFactor(msg.sender);
        bool minted = i_tsc.mint(msg.sender, amountTscToMint);
        if (!minted) {
            revert TSCEngine__MintFailed();
        }
    }

    function burnTsc(uint256 amount) public moreThanZero(amount) {
        _burnTsc(amount, msg.sender, msg.sender);
        _checkHealthFactor(msg.sender); // dont know if this is needed
    }

    /* ---------------------------- PRIVATE FUNCTIONS --------------------------- */

    function _burnTsc(uint256 amountTscToBurn, address onBehalfOf, address tscFrom) private {
        s_tscMinted[onBehalfOf] -= amountTscToBurn;
        bool success = i_tsc.transferFrom(tscFrom, address(this), amountTscToBurn);
        if (!success) {
            revert TSCEngine__TransferFail();
        }
        i_tsc.burn(amountTscToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert TSCEngine__TransferFail();
        }
    }

    /* -------------------------- PRIVATE/VIEW/INTERNAL FUNCTIONS ------------------------- */

    /**
     * @param user address of the user
     * @dev this function will check the health factor of the user
     * @dev checks if the deposited collateral is less than the threshold
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
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForTreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // $1000 ETH and 100 TSC
        // collateralAdjustedForTreshold  = 1000 * 50 = 5000 / 100 = 500
        // return 500 / 100 = 5 (health factor) here it will do this with precision

        return (collateralAdjustedForTreshold * PRECISION) / totalDscMinted;
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_tscMinted[user];
        collateralValueInUsd = _getAccountCollateralValue(user);
    }

    /* --------------------- PUBLIC/EXTERNAL/VIEW FUNCTIONS --------------------- */

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        //  price of ETH(token)
        // $/eth => eth > ??
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRESCISION);
        //  $ (10e18 * 1e18) / ($2000e8 * 1e10)
    }

    function _getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint256 formattedPrice = (uint256(price) * ADDITIONAL_FEED_PRESCISION * amount) / 1e18;
        return formattedPrice;
    }
}
