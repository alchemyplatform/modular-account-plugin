// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {BasePlugin} from "@alchemy/modular-account/src/plugins/BasePlugin.sol";
import {IPluginExecutor} from "@alchemy/modular-account/src/interfaces/IPluginExecutor.sol";
import {
    ManifestFunction,
    ManifestAssociatedFunctionType,
    ManifestAssociatedFunction,
    PluginManifest,
    PluginMetadata
} from "@alchemy/modular-account/src/interfaces/IPlugin.sol";
import {IMultiOwnerPlugin} from "@alchemy/modular-account/src/plugins/owner/IMultiOwnerPlugin.sol";

/// @title SubscriptionPlugin
/// @author Alchemy
/// @notice This plugin lets us subscribe to services!
contract SubscriptionPlugin is BasePlugin {
    // metadata used by the pluginMetadata() method down below
    string public constant NAME = "Subscription Plugin";
    string public constant VERSION = "1.0.0";
    string public constant AUTHOR = "Alchemy";

    // this is a constant used in the manifest, to reference our only dependency: the multi owner plugin
    // since it is the first, and only, plugin the index 0 will reference the multi owner plugin
    // we can use this to tell the modular account that we should use the multi owner plugin to validate our user op
    // in other words, we'll say "make sure the person calling increment is an owner of the account using our multiowner plugin"
    uint256 internal constant _MANIFEST_DEPENDENCY_INDEX_OWNER_USER_OP_VALIDATION = 0;

    // ERC 7562 defines the associated storage rules for ERC 4337 accounts
    // and plugins need to follow this definition to have succesful user ops executed by a bundler
    // a mapping from the account address is considered associated storage
    // see the definition here: https://eips.ethereum.org/EIPS/eip-7562#validation-rules
    mapping(address => mapping(address => SubscriptionData)) public subscriptions;

    struct SubscriptionData {
        uint256 amount;
        uint256 lastPaid;
        bool enabled;
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Execution functions    ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    // this can be called from a user op by the account owner
    function subscribe(address service, uint256 amount) external {
        subscriptions[service][msg.sender] = SubscriptionData(amount, 0, true);
    }

    // this can be called from the service to collect the subcription cost
    function collect(address subscriber, uint256 amount) external {
        SubscriptionData storage subscription = subscriptions[msg.sender][subscriber];
        require(subscription.enabled, "must be enabled");
        require(block.timestamp - subscription.lastPaid >= 4 weeks, "must pass the subcription period");
        require(amount == subscription.amount, "must be the subscription amount");
        subscription.lastPaid = block.timestamp;
        IPluginExecutor(subscriber).executeFromPluginExternal(msg.sender, amount, "0x");
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Plugin interface functions    ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /// @inheritdoc BasePlugin
    function onInstall(bytes calldata) external pure override {}

    /// @inheritdoc BasePlugin
    function onUninstall(bytes calldata) external pure override {}

    /// @inheritdoc BasePlugin
    function pluginManifest() external pure override returns (PluginManifest memory) {
        PluginManifest memory manifest;

        manifest.dependencyInterfaceIds = new bytes4[](1);
        manifest.dependencyInterfaceIds[0] = type(IMultiOwnerPlugin).interfaceId;

        manifest.executionFunctions = new bytes4[](1);
        manifest.executionFunctions[0] = this.subscribe.selector;

        ManifestFunction memory ownerUserOpValidationFunction = ManifestFunction({
            functionType: ManifestAssociatedFunctionType.DEPENDENCY,
            functionId: 0, // unused since it's a dependency
            dependencyIndex: _MANIFEST_DEPENDENCY_INDEX_OWNER_USER_OP_VALIDATION
        });

        manifest.userOpValidationFunctions = new ManifestAssociatedFunction[](1);
        manifest.userOpValidationFunctions[0] = ManifestAssociatedFunction({
            executionSelector: this.subscribe.selector,
            associatedFunction: ownerUserOpValidationFunction
        });

        manifest.preRuntimeValidationHooks = new ManifestAssociatedFunction[](1);
        manifest.preRuntimeValidationHooks[0] = ManifestAssociatedFunction({
            executionSelector: this.subscribe.selector,
            associatedFunction: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.PRE_HOOK_ALWAYS_DENY,
                functionId: 0,
                dependencyIndex: 0
            })
        });

        manifest.permitAnyExternalAddress = true;
        manifest.canSpendNativeToken = true;

        return manifest;
    }

    /// @inheritdoc BasePlugin
    function pluginMetadata() external pure virtual override returns (PluginMetadata memory) {
        PluginMetadata memory metadata;
        metadata.name = NAME;
        metadata.version = VERSION;
        metadata.author = AUTHOR;
        return metadata;
    }
}
