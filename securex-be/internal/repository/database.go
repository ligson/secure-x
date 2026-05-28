package repository

import (
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/glebarez/sqlite"
	"github.com/ligson/secure-x/securex-be/internal/model"
	"gorm.io/gorm"
)

func Open(databaseDSN string) (*gorm.DB, error) {
	if err := os.MkdirAll(filepath.Dir(databaseDSN), 0o755); err != nil {
		return nil, err
	}

	db, err := gorm.Open(sqlite.Open(sqliteDSN(databaseDSN)), &gorm.Config{})
	if err != nil {
		return nil, err
	}
	if sqlDB, err := db.DB(); err == nil {
		// SQLite 只有单写者；串行化连接可避免高频聊天写入在多连接间互相抢锁。
		sqlDB.SetMaxOpenConns(1)
		sqlDB.SetMaxIdleConns(1)
		sqlDB.SetConnMaxLifetime(0)
		sqlDB.SetConnMaxIdleTime(5 * time.Minute)
	} else {
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
		&model.ChatDeviceRecovery{},
		&model.ChatQueuedEnvelope{},
	); err != nil {
		return nil, err
	}

	return db, nil
}

func sqliteDSN(databaseDSN string) string {
	separator := "?"
	if strings.Contains(databaseDSN, "?") {
		separator = "&"
	}
	return databaseDSN + separator +
		"_pragma=busy_timeout(30000)" +
		"&_pragma=journal_mode(WAL)" +
		"&_pragma=synchronous(NORMAL)" +
		"&_pragma=foreign_keys(1)"
}
