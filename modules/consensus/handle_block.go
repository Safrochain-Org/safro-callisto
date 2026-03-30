package consensus

import (
	"errors"
	"fmt"
	"strings"

	"github.com/forbole/callisto/v4/database"
	junotypes "github.com/forbole/juno/v5/types"

	"github.com/rs/zerolog/log"

	tmctypes "github.com/cometbft/cometbft/rpc/core/types"
)

// HandleBlock implements modules.Module
func (m *Module) HandleBlock(
	b *tmctypes.ResultBlock, _ *tmctypes.ResultBlockResults, _ []*junotypes.Tx, _ *tmctypes.ResultValidators,
) error {
	err := m.updateBlockTimeFromGenesis(b)
	if err != nil {
		log.Error().Str("module", "consensus").Int64("height", b.Block.Height).
			Err(err).Msg("error while updating block time from genesis")
	}

	return nil
}

// updateBlockTimeFromGenesis inserts average block time from genesis.
// If height 0 has not been indexed yet (parallel workers), genesis row is missing — skip quietly.
func (m *Module) updateBlockTimeFromGenesis(block *tmctypes.ResultBlock) error {
	log.Trace().Str("module", "consensus").Int64("height", block.Block.Height).
		Msg("updating block time from genesis")

	genesis, err := m.db.GetGenesis()
	if err != nil {
		if errors.Is(err, database.ErrNoGenesisRows) || strings.Contains(err.Error(), "no rows inside the genesis table") {
			return nil
		}
		return fmt.Errorf("error while getting genesis: %s", err)
	}
	if genesis == nil {
		return nil
	}

	denom := block.Block.Height - genesis.InitialHeight
	if denom <= 0 {
		return nil
	}

	newBlockTime := block.Block.Time.Sub(genesis.Time).Seconds() / float64(denom)
	return m.db.SaveAverageBlockTimeGenesis(newBlockTime, block.Block.Height)
}
