package repository

import (
	"os"
	"path/filepath"

	"github.com/glebarez/sqlite"
	"github.com/ligson/secure-x/securex-be/internal/model"
	"gorm.io/gorm"
)

func Open(databaseDSN string) (*gorm.DB, error) {
	if err := os.MkdirAll(filepath.Dir(databaseDSN), 0o755); err != nil {
		return nil, err
	}

	db, err := gorm.Open(sqlite.Open(databaseDSN), &gorm.Config{})
	if err != nil {
		return nil, err
	}

	if err := db.AutoMigrate(
		&model.User{},
		&model.Folder{},
		&model.FileFolder{},
		&model.VaultItem{},
		&model.StoredFile{},
		&model.FileUploadSession{},
		&model.FriendRequest{},
		&model.Friendship{},
		&model.FriendAlias{},
		&model.GroupRoom{},
		&model.GroupMembership{},
		&model.GroupSnapshot{},
		&model.ChatArchive{},
		&model.ChatArchiveConversation{},
		&model.ChatDevice{},
		&model.ChatQueuedEnvelope{},
	); err != nil {
		return nil, err
	}

	return db, nil
}
