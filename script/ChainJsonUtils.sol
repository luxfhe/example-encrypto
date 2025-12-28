// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";

contract ChainJsonUtils is Script {
    using stdJson for string;

    string public chainName;
    string public deploymentPath;
    string public deploymentJson;

    error ChainNameNotSet();
    error MissingPath();
    error MissingContractName();
    error DeployedContractWhileFrozen();

    modifier loadChain() {
        chainName = vm.envString("CHAIN_NAME");
        string memory root = vm.projectRoot();
        deploymentPath = string.concat(
            root,
            "/data/",
            chainName,
            "/deployment.json"
        );
        deploymentJson = vm.readFile(deploymentPath);
        _;
    }

    // Paths

    function contractPath(
        string memory item
    ) internal pure returns (string memory) {
        return string.concat(".contracts.", item);
    }

    // Primitives

    function readAddress(string memory path) internal view returns (address) {
        if (bytes(path).length == 0) revert MissingPath();
        bytes memory addressRaw = deploymentJson.parseRaw(path);
        return abi.decode(addressRaw, (address));
    }
    function readUint(string memory path) internal view returns (uint256) {
        if (bytes(path).length == 0) revert MissingPath();
        bytes memory uintRaw = deploymentJson.parseRaw(path);
        return abi.decode(uintRaw, (uint256));
    }
    function readBool(string memory path) internal view returns (bool) {
        if (bytes(path).length == 0) revert MissingPath();
        bytes memory boolRaw = deploymentJson.parseRaw(path);
        return abi.decode(boolRaw, (bool));
    }
    function writeAddress(string memory path, address value) internal {
        if (bytes(path).length == 0) revert MissingPath();
        vm.writeJson(vm.toString(value), deploymentPath, path);
    }
    function writeUint(string memory path, uint256 value) internal {
        if (bytes(path).length == 0) revert MissingPath();
        vm.writeJson(vm.toString(value), deploymentPath, path);
    }
    function writeBool(string memory path, bool value) internal {
        if (bytes(path).length == 0) revert MissingPath();
        vm.writeJson(vm.toString(value), deploymentPath, path);
    }
    function writeContractAddress(
        string memory contractName,
        address contractAddress
    ) internal {
        if (bytes(contractName).length == 0) revert MissingPath();
        writeAddress(contractPath(contractName), contractAddress);
    }
}
