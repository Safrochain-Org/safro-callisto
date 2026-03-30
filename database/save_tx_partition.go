package database

import (
	"errors"
	"strings"

	"github.com/forbole/juno/v5/types"
	"github.com/lib/pq"
)

// isDuplicateRelation reports PostgreSQL duplicate_table / "already exists" from concurrent
// CREATE TABLE ... PARTITION (multiple workers hitting the same partition at once).
func isDuplicateRelation(err error) bool {
	if err == nil {
		return false
	}
	var pqErr *pq.Error
	if errors.As(err, &pqErr) && pqErr.Code == "42P07" { // duplicate_table
		return true
	}
	return strings.Contains(err.Error(), "already exists")
}

// SaveTx retries once on partition DDL races between workers (see Juno postgresql.SaveTx).
func (db *Db) SaveTx(tx *types.Tx) error {
	err := db.Database.SaveTx(tx)
	if err != nil && isDuplicateRelation(err) {
		return db.Database.SaveTx(tx)
	}
	return err
}

// SaveMessage retries once on the same partition race as SaveTx.
func (db *Db) SaveMessage(msg *types.Message) error {
	err := db.Database.SaveMessage(msg)
	if err != nil && isDuplicateRelation(err) {
		return db.Database.SaveMessage(msg)
	}
	return err
}
