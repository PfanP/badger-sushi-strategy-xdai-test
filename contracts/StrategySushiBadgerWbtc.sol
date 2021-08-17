// SPDX-License-Identifier: MIT

pragma solidity ^0.6.11;
pragma experimental ABIEncoderV2;

import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "../deps/@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/badger/IController.sol";
import "../interfaces/sushiswap/IMinichef.sol";
import "../interfaces/uniswap/IUniswapRouterV2.sol";

import {
    BaseStrategy
} from "../deps/BaseStrategy.sol";

contract StrategySushiBadgerWbtc is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;
    using SafeERC20 for IERC20;

    // address public want // Inherited from BaseStrategy, the token the strategy wants, swaps into and tries to grow
    address public lpComponent; // Token we provide liquidity with
    address public reward; // Token we farm and swap to want / lpComponent

    address public constant wbtc = 0x8e5bBbb09Ed1ebdE8674Cda39A0c169401db4252; // WBTC Token
    address public constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH Token
    address public constant sushi = 0x2995D1317DcD4f0aB89f4AE60F3f020A4F17C7CE; // SUSHI token
    address public constant stake = 0xb7D311E2Eb55F2f68a9440da38e7989210b9A05e; // stake token
    address public constant badgerTree = 0xb7D311E2Eb55F2f68a9440da38e7989210b9A05e; // stake token
    
    address public constant chef = 0xdDCbf776dF3dE60163066A5ddDF2277cB445E0F3; // Master staking contract
    uint256 public constant pid = 1; // LP token pool ID
    address public constant SUSHISWAP_ROUTER = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;

    // Used to signal to the Badger Tree that rewards where sent to it
    event TreeDistribution(address indexed token, uint256 amount, uint256 indexed blockNumber, uint256 timestamp);
    event DepositBadgerStrategy(uint256 amount);
    function initialize(
        address _governance,
        address _strategist,
        address _controller,
        address _keeper,
        address _guardian,
        address[3] memory _wantConfig,
        uint256[3] memory _feeConfig
    ) public initializer {
        __BaseStrategy_init(_governance, _strategist, _controller, _keeper, _guardian);

        /// @dev Add config here
        want = _wantConfig[0];
        lpComponent = _wantConfig[1];
        reward = _wantConfig[2];

        performanceFeeGovernance = _feeConfig[0];
        performanceFeeStrategist = _feeConfig[1];
        withdrawalFee = _feeConfig[2];

        /// @dev do one off approvals here
        // IERC20Upgradeable(want).safeApprove(gauge, type(uint256).max);

        IERC20(want).safeApprove(chef, type(uint256).max);
    }

    /// ===== View Functions =====

    // @dev Specify the name of the strategy
    function getName() external override pure returns (string memory) {
        return "StrategySushiv2LP";
    }

    // @dev Specify the version of the Strategy, for upgrades
    function version() external pure returns (string memory) {
        return "1.0";
    }

    /// @dev Balance of want currently held in strategy positions
    function balanceOfPool() public override view returns (uint256) {
        (uint256 amount, ) = IMiniChefV2(chef).userInfo(pid, address(this));
        return amount;
    }
    
    function sushiAvailable() internal view returns (uint256) {
        return IERC20(sushi).balanceOf(address(this));
    }

    /// @dev Returns true if this strategy requires tending
    function isTendable() public override view returns (bool) {
        return true;
    }

    // @dev These are the tokens that cannot be moved except by the vault
    function getProtectedTokens() public override view returns (address[] memory) {
        address[] memory protectedTokens = new address[](3);
        protectedTokens[0] = want;
        protectedTokens[1] = lpComponent;
        protectedTokens[2] = reward;
        return protectedTokens;
    }

    /// ===== Permissioned Actions: Governance =====
    /// @notice Delete if you don't need!
    function setKeepReward(uint256 _setKeepReward) external {
        _onlyGovernance();
    }

    /// ===== Internal Core Implementations =====

    /// @dev security check to avoid moving tokens that would cause a rugpull, edit based on strat
    function _onlyNotProtectedTokens(address _asset) internal override {
        address[] memory protectedTokens = getProtectedTokens();

        for(uint256 x = 0; x < protectedTokens.length; x++){
            require(address(protectedTokens[x]) != _asset, "Asset is protected");
        }
    }


    /// @dev invest the amount of want
    /// @notice When this function is called, the controller has already sent want to this
    /// @notice Just get the current balance and then invest accordingly
    function _deposit(uint256 _amount) internal override {
        // compare the lp amount with _amount
        // uint256 lpAmount = IERC20(want).balanceOf(address(this));
        IMiniChefV2(chef).deposit(
            pid,
            _amount,
            address(this)
        );
        emit DepositBadgerStrategy(_amount);
    }

    /// @dev utility function to withdraw everything for migration
    function _withdrawAll() internal override {
        // Withdraw all want from Chef
        IMiniChefV2(chef).withdrawAndHarvest(pid, balanceOfPool(), address(this));

    }
    /// @dev withdraw the specified amount of want, liquidate from lpComponent to want, paying off any necessary debt for the conversion
    function _withdrawSome(uint256 _amount) internal override returns (uint256) {
        if (_amount > balanceOfPool()) {
            _amount = balanceOfPool();
        }

        IMiniChefV2(chef).withdrawAndHarvest(pid, _amount, address(this));
        return _amount;
    }

    /// @dev Harvest from strategy mechanics, realizing increase in underlying position
    function harvest() external whenNotPaused returns (uint256 harvested) {
        _onlyAuthorizedActors();


        uint256 _before = sushiAvailable();

        // Write your code here 
        IMiniChefV2(chef).harvest(pid, address(this));
        
        // Collect Stake tokens
        uint256 _stake = IERC20(stake).balanceOf(address(this));
        // if (_stake > 0) {
        //     _swapSushiswap(stake, sushi, _stake);
        // }

        uint256 sushiAmount = sushiAvailable();
        uint256 earned = sushiAmount.sub(_before);

        /// @notice Keep this in so you get paid!
        // (uint256 governancePerformanceFee, uint256 strategistPerformanceFee) = _processPerformanceFees(earned);

        // TODO: If you are harvesting a reward token you're not compounding
        // You probably still want to capture fees for it 
        // // Process Sushi rewards if existing
        if (sushiAvailable() > 0) {
            // Process fees on Sushi Rewards
            // NOTE: Use this to receive fees on the reward token
            _processRewardsFees(sushiAmount, sushi);

            // Transfer balance of Sushi to the Badger Tree
            // NOTE: Send reward to badgerTree
            IERC20Upgradeable(sushi).safeTransfer(badgerTree, sushiAvailable());
            
            // NOTE: Signal the amount of reward sent to the badger tree
            emit TreeDistribution(sushi, sushiAmount, block.number, block.timestamp);
        }

        /// @dev Harvest event that every strategy MUST have, see BaseStrategy
        emit Harvest(earned, block.number);

        /// @dev Harvest must return the amount of want increased
        return earned;
    }

    /// @dev Rebalance, Compound or Pay off debt here
    function tend() external whenNotPaused {
        _onlyAuthorizedActors();
    }


    /// ===== Internal Helper Functions =====
    
    /// @dev used to manage the governance and strategist fee, make sure to use it to get paid!
    function _processPerformanceFees(uint256 _amount) internal returns (uint256 governancePerformanceFee, uint256 strategistPerformanceFee) {
        governancePerformanceFee = _processFee(want, _amount, performanceFeeGovernance, IController(controller).rewards());

        strategistPerformanceFee = _processFee(want, _amount, performanceFeeStrategist, strategist);
    }

    /// @dev used to manage the governance and strategist fee on earned rewards, make sure to use it to get paid!
    function _processRewardsFees(uint256 _amount, address _token) internal returns (uint256 governanceRewardsFee, uint256 strategistRewardsFee) {
        governanceRewardsFee = _processFee(_token, _amount, performanceFeeGovernance, IController(controller).rewards());

        strategistRewardsFee = _processFee(_token, _amount, performanceFeeStrategist, strategist);
    }

    /// @notice swap on sushiswap
    function _swapSushiswap(
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        require(_to != address(0));

        address[] memory path;

        path = new address[](3);
        path[0] = _from;
        path[1] = weth;
        path[2] = _to;

        // IERC20(_from).safeApprove(SUSHISWAP_ROUTER, _amount);
        IUniswapRouterV2(SUSHISWAP_ROUTER).swapExactTokensForTokens(
            _amount,
            0,
            path,
            address(this),
            now.add(999999999)
        );
    }

    function onTokenTransfer(address _sender, uint _value, bytes calldata _data) override external {

    }
}
