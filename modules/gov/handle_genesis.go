package gov

import (
	"encoding/json"
	"fmt"

	tmtypes "github.com/cometbft/cometbft/types"

	"github.com/forbole/callisto/v4/types"

	gov "github.com/cosmos/cosmos-sdk/x/gov/types"
	govtypesv1 "github.com/cosmos/cosmos-sdk/x/gov/types/v1"
	"github.com/rs/zerolog/log"
)

// govParamsKeysAllowedInSDK047 are JSON keys for x/gov v1.Params in cosmos-sdk v0.47.x.
// Newer chains add fields (e.g. min_deposit_ratio); the amino/codec rejects unknown keys.
var govParamsKeysAllowedInSDK047 = map[string]struct{}{
	"min_deposit":                   {},
	"max_deposit_period":            {},
	"voting_period":                 {},
	"quorum":                        {},
	"threshold":                     {},
	"veto_threshold":                {},
	"min_initial_deposit_ratio":     {},
	"burn_vote_quorum":              {},
	"burn_proposal_deposit_prevote": {},
	"burn_vote_veto":                {},
}

// govGenesisRootKeysAllowed are top-level JSON keys for x/gov v1.GenesisState in SDK 0.47.x.
// Chains may add fields (e.g. constitution); the codec rejects them.
var govGenesisRootKeysAllowed = map[string]struct{}{
	"starting_proposal_id": {},
	"deposits":             {},
	"votes":                {},
	"proposals":            {},
	"deposit_params":       {},
	"voting_params":        {},
	"tally_params":         {},
	"params":               {},
}

func filterGovParamsJSON(paramsRaw json.RawMessage) (json.RawMessage, error) {
	var params map[string]interface{}
	if err := json.Unmarshal(paramsRaw, &params); err != nil {
		return paramsRaw, nil
	}
	filtered := make(map[string]interface{}, len(params))
	for k, v := range params {
		if _, ok := govParamsKeysAllowedInSDK047[k]; ok {
			filtered[k] = v
		}
	}
	return json.Marshal(filtered)
}

// sanitizeGovGenesisJSON drops gov genesis keys unknown to the linked SDK (root + params).
func sanitizeGovGenesisJSON(raw json.RawMessage) (json.RawMessage, error) {
	var doc map[string]json.RawMessage
	if err := json.Unmarshal(raw, &doc); err != nil {
		return nil, err
	}
	out := make(map[string]json.RawMessage)
	for k, v := range doc {
		if _, ok := govGenesisRootKeysAllowed[k]; !ok {
			continue
		}
		if k == "params" {
			pv, err := filterGovParamsJSON(v)
			if err != nil {
				return nil, err
			}
			v = pv
		}
		out[k] = v
	}
	return json.Marshal(out)
}

// HandleGenesis implements modules.Module
func (m *Module) HandleGenesis(doc *tmtypes.GenesisDoc, appState map[string]json.RawMessage) error {
	log.Debug().Str("module", "gov").Msg("parsing genesis")

	sanitized, err := sanitizeGovGenesisJSON(appState[gov.ModuleName])
	if err != nil {
		return fmt.Errorf("error while sanitizing gov genesis data: %s", err)
	}

	var genStatev1beta1 govtypesv1.GenesisState
	if err := m.cdc.UnmarshalJSON(sanitized, &genStatev1beta1); err != nil {
		return fmt.Errorf("error while reading gov genesis data: %s", err)
	}

	// Save the proposals
	if err := m.saveGenesisProposals(genStatev1beta1.Proposals, doc); err != nil {
		return fmt.Errorf("error while storing genesis governance proposals: %s", err)
	}

	// Save the params
	if err := m.db.SaveGovParams(types.NewGovParams(genStatev1beta1.Params, doc.InitialHeight)); err != nil {
		return fmt.Errorf("error while storing genesis governance params: %s", err)
	}

	return nil
}

// saveGenesisProposals save proposals from genesis file
func (m *Module) saveGenesisProposals(slice govtypesv1.Proposals, genDoc *tmtypes.GenesisDoc) error {
	proposals := make([]types.Proposal, len(slice))
	tallyResults := make([]types.TallyResult, len(slice))
	deposits := make([]types.Deposit, len(slice))

	for index, proposal := range slice {
		// Since it's not possible to get the proposer, set it to nil
		proposals[index] = types.NewProposal(
			proposal.Id,
			proposal.Title,
			proposal.Summary,
			proposal.Metadata,
			proposal.Messages,
			proposal.Status.String(),
			*proposal.SubmitTime,
			*proposal.DepositEndTime,
			proposal.VotingStartTime,
			proposal.VotingEndTime,
			"",
		)

		tallyResults[index] = types.NewTallyResult(
			proposal.Id,
			proposal.FinalTallyResult.YesCount,
			proposal.FinalTallyResult.AbstainCount,
			proposal.FinalTallyResult.NoCount,
			proposal.FinalTallyResult.NoWithVetoCount,
			genDoc.InitialHeight,
		)

		deposits[index] = types.NewDeposit(
			proposal.Id,
			"",
			proposal.TotalDeposit,
			genDoc.GenesisTime,
			"",
			genDoc.InitialHeight,
		)
	}

	// Save the proposals
	err := m.db.SaveProposals(proposals)
	if err != nil {
		return err
	}

	// Save the deposits
	err = m.db.SaveDeposits(deposits)
	if err != nil {
		return err
	}

	// Save the tally results
	return m.db.SaveTallyResults(tallyResults)
}
