// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Endless} from "../src/Endless.sol";

contract EndlessTest is Test {
    Endless public endless;

    function setUp() public {
        endless = new Endless();
    }
}
