pragma solidity =0.6.6;

import './interfaces/IRamzSwapFactory.sol';
import './libraries/TransferHelper.sol';

import './interfaces/IRamzSwapRouter.sol';
import './libraries/RamzSwapLibrary.sol';
import './libraries/SafeMath.sol';
import './interfaces/IMAAL20.sol';
import './interfaces/IWMAAL.sol';

contract RamzSwapRouter is IRamzSwapRouter {
    using SafeMath for uint;

    address public immutable override factory;
    address public immutable override WMAAL;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'RamzSwapRouter: EXPIRED');
        _;
    }

    constructor(address _factory, address _WMAAL) public {
        factory = _factory;
        WMAAL = _WMAAL;
    }

    receive() external payable {
        assert(msg.sender == WMAAL); // only accept MAAL via fallback from the WMAAL contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (IRamzSwapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IRamzSwapFactory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = RamzSwapLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = RamzSwapLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'RamzSwapRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = RamzSwapLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'RamzSwapRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = RamzSwapLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IRamzSwapPair(pair).mint(to);
    }
    function addLiquidityMAAL(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountMAALMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountMAAL, uint liquidity) {
        (amountToken, amountMAAL) = _addLiquidity(
            token,
            WMAAL,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountMAALMin
        );
        address pair = RamzSwapLibrary.pairFor(factory, token, WMAAL);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWMAAL(WMAAL).deposit{value: amountMAAL}();
        assert(IWMAAL(WMAAL).transfer(pair, amountMAAL));
        liquidity = IRamzSwapPair(pair).mint(to);
        // refund dust maal, if any
        if (msg.value > amountMAAL) TransferHelper.safeTransferMAAL(msg.sender, msg.value - amountMAAL);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = RamzSwapLibrary.pairFor(factory, tokenA, tokenB);
        IRamzSwapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IRamzSwapPair(pair).burn(to);
        (address token0,) = RamzSwapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'RamzSwapRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'RamzSwapRouter: INSUFFICIENT_B_AMOUNT');
    }
    function removeLiquidityMAAL(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountMAALMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountMAAL) {
        (amountToken, amountMAAL) = removeLiquidity(
            token,
            WMAAL,
            liquidity,
            amountTokenMin,
            amountMAALMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWMAAL(WMAAL).withdraw(amountMAAL);
        TransferHelper.safeTransferMAAL(to, amountMAAL);
    }
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountA, uint amountB) {
        address pair = RamzSwapLibrary.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        IRamzSwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    function removeLiquidityMAALWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountMAALMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountToken, uint amountMAAL) {
        address pair = RamzSwapLibrary.pairFor(factory, token, WMAAL);
        uint value = approveMax ? uint(-1) : liquidity;
        IRamzSwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountMAAL) = removeLiquidityMAAL(token, liquidity, amountTokenMin, amountMAALMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityMAALSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountMAALMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountMAAL) {
        (, amountMAAL) = removeLiquidity(
            token,
            WMAAL,
            liquidity,
            amountTokenMin,
            amountMAALMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IMAAL20(token).balanceOf(address(this)));
        IWMAAL(WMAAL).withdraw(amountMAAL);
        TransferHelper.safeTransferMAAL(to, amountMAAL);
    }
    function removeLiquidityMAALWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountMAALMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountMAAL) {
        address pair = RamzSwapLibrary.pairFor(factory, token, WMAAL);
        uint value = approveMax ? uint(-1) : liquidity;
        IRamzSwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountMAAL = removeLiquidityMAALSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountMAALMin, to, deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = RamzSwapLibrary.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? RamzSwapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            IRamzSwapPair(RamzSwapLibrary.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = RamzSwapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'RamzSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, RamzSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = RamzSwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'RamzSwapRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, RamzSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapExactMAALForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WMAAL, 'RamzSwapRouter: INVALID_PATH');
        amounts = RamzSwapLibrary.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'RamzSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWMAAL(WMAAL).deposit{value: amounts[0]}();
        assert(IWMAAL(WMAAL).transfer(RamzSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }
    function swapTokensForExactMAAL(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WMAAL, 'RamzSwapRouter: INVALID_PATH');
        amounts = RamzSwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'RamzSwapRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, RamzSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWMAAL(WMAAL).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferMAAL(to, amounts[amounts.length - 1]);
    }
    function swapExactTokensForMAAL(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WMAAL, 'RamzSwapRouter: INVALID_PATH');
        amounts = RamzSwapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'RamzSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, RamzSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWMAAL(WMAAL).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferMAAL(to, amounts[amounts.length - 1]);
    }
    function swapMAALForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WMAAL, 'RamzSwapRouter: INVALID_PATH');
        amounts = RamzSwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'RamzSwapRouter: EXCESSIVE_INPUT_AMOUNT');
        IWMAAL(WMAAL).deposit{value: amounts[0]}();
        assert(IWMAAL(WMAAL).transfer(RamzSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust maal, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferMAAL(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = RamzSwapLibrary.sortTokens(input, output);
            IRamzSwapPair pair = IRamzSwapPair(RamzSwapLibrary.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IMAAL20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = RamzSwapLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? RamzSwapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, RamzSwapLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IMAAL20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IMAAL20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'RamzSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactMAALForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        payable
        ensure(deadline)
    {
        require(path[0] == WMAAL, 'RamzSwapRouter: INVALID_PATH');
        uint amountIn = msg.value;
        IWMAAL(WMAAL).deposit{value: amountIn}();
        assert(IWMAAL(WMAAL).transfer(RamzSwapLibrary.pairFor(factory, path[0], path[1]), amountIn));
        uint balanceBefore = IMAAL20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IMAAL20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'RamzSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactTokensForMAALSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        require(path[path.length - 1] == WMAAL, 'RamzSwapRouter: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, RamzSwapLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint amountOut = IMAAL20(WMAAL).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'RamzSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWMAAL(WMAAL).withdraw(amountOut);
        TransferHelper.safeTransferMAAL(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return RamzSwapLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountOut)
    {
        return RamzSwapLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountIn)
    {
        return RamzSwapLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return RamzSwapLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return RamzSwapLibrary.getAmountsIn(factory, amountOut, path);
    }
}
