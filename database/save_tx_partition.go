package database

import (
	"encoding/base64"
	"fmt"
	"strings"

	"github.com/forbole/juno/v5/database/postgresql"
	"github.com/forbole/juno/v5/types"
	"github.com/forbole/juno/v5/types/config"
	"github.com/lib/pq"
)

// createPartitionIfNotExists tolerates concurrent CREATE of the same partition (multi-worker catch-up).
// Upstream Juno uses CREATE TABLE IF NOT EXISTS but PostgreSQL can still return "already exists" under races.
func createPartitionIfNotExists(db *postgresql.Database, table string, partitionID int64) error {
	partitionTable := fmt.Sprintf("%s_%d", table, partitionID)
	stmt := fmt.Sprintf(
		"CREATE TABLE IF NOT EXISTS %s PARTITION OF %s FOR VALUES IN (%d)",
		partitionTable,
		table,
		partitionID,
	)
	_, err := db.SQL.Exec(stmt)
	if err == nil {
		return nil
	}
	if strings.Contains(err.Error(), "already exists") {
		return nil
	}
	return err
}

// SaveTx overrides the embedded Juno implementation to use createPartitionIfNotExists above.
func (db *Db) SaveTx(tx *types.Tx) error {
	d := db.Database
	var partitionID int64
	partitionSize := config.Cfg.Database.PartitionSize
	if partitionSize > 0 {
		partitionID = tx.Height / partitionSize
		if err := createPartitionIfNotExists(d, "transaction", partitionID); err != nil {
			return err
		}
	}
	return saveTxInsidePartition(d, tx, partitionID)
}

func saveTxInsidePartition(db *postgresql.Database, tx *types.Tx, partitionID int64) error {
	sqlStatement := `
INSERT INTO transaction 
(hash, height, success, messages, memo, signatures, signer_infos, fee, gas_wanted, gas_used, raw_log, logs, partition_id) 
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13) 
ON CONFLICT (hash, partition_id) DO UPDATE 
	SET height = excluded.height, 
		success = excluded.success, 
		messages = excluded.messages,
		memo = excluded.memo, 
		signatures = excluded.signatures, 
		signer_infos = excluded.signer_infos,
		fee = excluded.fee, 
		gas_wanted = excluded.gas_wanted, 
		gas_used = excluded.gas_used,
		raw_log = excluded.raw_log, 
		logs = excluded.logs`

	var sigs = make([]string, len(tx.Signatures))
	for index, sig := range tx.Signatures {
		sigs[index] = base64.StdEncoding.EncodeToString(sig)
	}

	var msgs = make([]string, len(tx.Body.Messages))
	for index, msg := range tx.Body.Messages {
		bz, err := db.Cdc.MarshalJSON(msg)
		if err != nil {
			return err
		}
		msgs[index] = string(bz)
	}
	msgsBz := fmt.Sprintf("[%s]", strings.Join(msgs, ","))

	feeBz, err := db.Cdc.MarshalJSON(tx.AuthInfo.Fee)
	if err != nil {
		return fmt.Errorf("failed to JSON encode tx fee: %s", err)
	}

	var sigInfos = make([]string, len(tx.AuthInfo.SignerInfos))
	for index, info := range tx.AuthInfo.SignerInfos {
		bz, err := db.Cdc.MarshalJSON(info)
		if err != nil {
			return err
		}
		sigInfos[index] = string(bz)
	}
	sigInfoBz := fmt.Sprintf("[%s]", strings.Join(sigInfos, ","))

	logsBz, err := db.Amino.MarshalJSON(tx.Logs)
	if err != nil {
		return err
	}

	_, err = db.SQL.Exec(sqlStatement,
		tx.TxHash, tx.Height, tx.Successful(),
		msgsBz, tx.Body.Memo, pq.Array(sigs),
		sigInfoBz, string(feeBz),
		tx.GasWanted, tx.GasUsed, tx.RawLog, string(logsBz),
		partitionID,
	)
	return err
}

// SaveMessage overrides the embedded Juno implementation for the same partition race.
func (db *Db) SaveMessage(msg *types.Message) error {
	d := db.Database
	var partitionID int64
	partitionSize := config.Cfg.Database.PartitionSize
	if partitionSize > 0 {
		partitionID = msg.Height / partitionSize
		if err := createPartitionIfNotExists(d, "message", partitionID); err != nil {
			return err
		}
	}
	return saveMessageInsidePartition(d, msg, partitionID)
}

func saveMessageInsidePartition(db *postgresql.Database, msg *types.Message, partitionID int64) error {
	stmt := `
INSERT INTO message(transaction_hash, index, type, value, involved_accounts_addresses, height, partition_id) 
VALUES ($1, $2, $3, $4, $5, $6, $7) 
ON CONFLICT (transaction_hash, index, partition_id) DO UPDATE 
	SET height = excluded.height, 
		type = excluded.type,
		value = excluded.value,
		involved_accounts_addresses = excluded.involved_accounts_addresses`

	_, err := db.SQL.Exec(stmt, msg.TxHash, msg.Index, msg.Type, msg.Value, pq.Array(msg.Addresses), msg.Height, partitionID)
	return err
}
