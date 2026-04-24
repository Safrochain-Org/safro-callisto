package main

import (
	wasm "github.com/CosmWasm/wasmd/x/wasm"
	"github.com/cosmos/cosmos-sdk/types/module"
	ica "github.com/cosmos/ibc-go/v7/modules/apps/27-interchain-accounts"
	ibcfee "github.com/cosmos/ibc-go/v7/modules/apps/29-fee"
	ibctransfer "github.com/cosmos/ibc-go/v7/modules/apps/transfer"
	ibc "github.com/cosmos/ibc-go/v7/modules/core"
	"github.com/forbole/juno/v5/cmd"
	initcmd "github.com/forbole/juno/v5/cmd/init"
	parsetypes "github.com/forbole/juno/v5/cmd/parse/types"
	startcmd "github.com/forbole/juno/v5/cmd/start"
	"github.com/forbole/juno/v5/modules/messages"

	migratecmd "github.com/forbole/callisto/v4/cmd/migrate"
	parsecmd "github.com/forbole/callisto/v4/cmd/parse"

	"github.com/forbole/callisto/v4/types/config"

	"cosmossdk.io/simapp"

	"github.com/forbole/callisto/v4/database"
	"github.com/forbole/callisto/v4/modules"
)

func main() {
	initCfg := initcmd.NewConfig().
		WithConfigCreator(config.Creator)

	parseCfg := parsetypes.NewConfig().
		WithDBBuilder(database.Builder).
		WithEncodingConfigBuilder(config.MakeEncodingConfig(getBasicManagers())).
		WithRegistrar(modules.NewRegistrar(getAddressesParser()))

	cfg := cmd.NewConfig("callisto").
		WithInitConfig(initCfg).
		WithParseConfig(parseCfg)

	// Run the command
	rootCmd := cmd.RootCmd(cfg.GetName())

	rootCmd.AddCommand(
		cmd.VersionCmd(),
		initcmd.NewInitCmd(cfg.GetInitConfig()),
		parsecmd.NewParseCmd(cfg.GetParseConfig()),
		migratecmd.NewMigrateCmd(cfg.GetName(), cfg.GetParseConfig()),
		startcmd.NewStartCmd(cfg.GetParseConfig()),
	)

	executor := cmd.PrepareRootCmd(cfg.GetName(), rootCmd)
	err := executor.Execute()
	if err != nil {
		panic(err)
	}
}

// getBasicManagers returns the various basic managers that are used to register the encoding to
// support custom messages.
// This should be edited by custom implementations if needed.
func getBasicManagers() []module.BasicManager {
	return []module.BasicManager{
		simapp.ModuleBasics,
		module.NewBasicManager(
			wasm.AppModuleBasic{},
			// Register IBC-go module basics so the codec can unpack IBC
			// messages like /ibc.core.client.v1.MsgUpdateClient,
			// /ibc.core.client.v1.MsgCreateClient and
			// /ibc.applications.transfer.v1.MsgTransfer. Without these,
			// any block containing IBC txs fails to be indexed with
			// "no concrete type registered for type URL ... against
			// interface *types.Msg".
			ibc.AppModuleBasic{},
			ibctransfer.AppModuleBasic{},
			ica.AppModuleBasic{},
			ibcfee.AppModuleBasic{},
		),
	}
}

// getAddressesParser returns the messages parser that should be used to get the users involved in
// a specific message.
// This should be edited by custom implementations if needed.
func getAddressesParser() messages.MessageAddressesParser {
	return messages.JoinMessageParsers(
		messages.CosmosMessageAddressesParser,
	)
}
