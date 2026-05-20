package model

import "time"

type User struct {
	ID                  string    `gorm:"primaryKey;size:36" json:"id"`
	Username            string    `gorm:"uniqueIndex;size:64;not null" json:"username"`
	Email               string    `gorm:"uniqueIndex;size:128;not null" json:"email"`
	PasswordHash        string    `gorm:"size:255;not null" json:"-"`
	KDFAlgorithm        string    `gorm:"size:32;not null" json:"kdfAlgorithm"`
	MasterKeySalt       string    `gorm:"size:255;not null" json:"masterKeySalt"`
	MasterKeyIterations int       `gorm:"not null" json:"masterKeyIterations"`
	WrappedVaultKey     string    `gorm:"type:text;not null" json:"wrappedVaultKey"`
	CreatedAt           time.Time `json:"createdAt"`
	UpdatedAt           time.Time `json:"updatedAt"`
}

type Folder struct {
	ID             string    `gorm:"primaryKey;size:36" json:"id"`
	UserID         string    `gorm:"index;size:36;not null" json:"userId"`
	ParentFolderID *string   `gorm:"index;size:36" json:"parentFolderId,omitempty"`
	Payload        string    `gorm:"type:text;not null" json:"payload"`
	Version        int       `gorm:"not null;default:1" json:"version"`
	CreatedAt      time.Time `json:"createdAt"`
	UpdatedAt      time.Time `json:"updatedAt"`
}

type VaultItem struct {
	ID        string    `gorm:"primaryKey;size:36" json:"id"`
	UserID    string    `gorm:"index;size:36;not null" json:"userId"`
	FolderID  *string   `gorm:"index;size:36" json:"folderId,omitempty"`
	Kind      string    `gorm:"size:32;not null" json:"kind"`
	Payload   string    `gorm:"type:text;not null" json:"payload"`
	Version   int       `gorm:"not null;default:1" json:"version"`
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
}

type StoredFile struct {
	ID          string    `gorm:"primaryKey;size:36" json:"id"`
	UserID      string    `gorm:"index;size:36;not null" json:"userId"`
	FolderID    *string   `gorm:"index;size:36" json:"folderId,omitempty"`
	Payload     string    `gorm:"type:text;not null" json:"payload"`
	StoragePath string    `gorm:"uniqueIndex;size:255;not null" json:"-"`
	CipherSize  int64     `gorm:"not null" json:"cipherSize"`
	Version     int       `gorm:"not null;default:1" json:"version"`
	CreatedAt   time.Time `json:"createdAt"`
	UpdatedAt   time.Time `json:"updatedAt"`
}
