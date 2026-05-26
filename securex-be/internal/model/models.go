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

type FileFolder struct {
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

type FileUploadSession struct {
	ID          string    `gorm:"primaryKey;size:36" json:"id"`
	UserID      string    `gorm:"index;size:36;not null" json:"userId"`
	FolderID    *string   `gorm:"index;size:36" json:"folderId,omitempty"`
	Version     int       `gorm:"not null;default:1" json:"version"`
	TotalChunks int       `gorm:"not null" json:"totalChunks"`
	CreatedAt   time.Time `json:"createdAt"`
	UpdatedAt   time.Time `json:"updatedAt"`
}

type FriendRequest struct {
	ID          string    `gorm:"primaryKey;size:36" json:"id"`
	RequesterID string    `gorm:"index;size:36;not null" json:"requesterId"`
	AddresseeID string    `gorm:"index;size:36;not null" json:"addresseeId"`
	Message     string    `gorm:"size:255" json:"message"`
	Status      string    `gorm:"index;size:24;not null" json:"status"`
	CreatedAt   time.Time `json:"createdAt"`
	UpdatedAt   time.Time `json:"updatedAt"`
}

type Friendship struct {
	ID        string    `gorm:"primaryKey;size:36" json:"id"`
	UserID    string    `gorm:"uniqueIndex:idx_friendship_pair;size:36;not null" json:"userId"`
	FriendID  string    `gorm:"uniqueIndex:idx_friendship_pair;size:36;not null" json:"friendId"`
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
}

type GroupRoom struct {
	ID                string     `gorm:"primaryKey;size:64" json:"id"`
	CreatorUserID     string     `gorm:"index;size:36;not null" json:"creatorUserId"`
	AdminUserID       string     `gorm:"index;size:36;not null" json:"adminUserId"`
	Status            string     `gorm:"index;size:24;not null;default:'active'" json:"status"`
	DissolvedAt       *time.Time `json:"dissolvedAt,omitempty"`
	DissolvedByUserID *string    `gorm:"size:36" json:"dissolvedByUserId,omitempty"`
	Version           int        `gorm:"not null;default:1" json:"version"`
	CreatedAt         time.Time  `json:"createdAt"`
	UpdatedAt         time.Time  `json:"updatedAt"`
}

type GroupMembership struct {
	ID            string    `gorm:"primaryKey;size:36" json:"id"`
	GroupID       string    `gorm:"uniqueIndex:idx_group_membership_pair;index;size:64;not null" json:"groupId"`
	UserID        string    `gorm:"uniqueIndex:idx_group_membership_pair;index;size:36;not null" json:"userId"`
	AddedByUserID string    `gorm:"size:36;not null" json:"addedByUserId"`
	CreatedAt     time.Time `json:"createdAt"`
	UpdatedAt     time.Time `json:"updatedAt"`
}

type GroupSnapshot struct {
	ID        string    `gorm:"primaryKey;size:36" json:"id"`
	GroupID   string    `gorm:"uniqueIndex:idx_group_snapshot_pair;index;size:64;not null" json:"groupId"`
	UserID    string    `gorm:"uniqueIndex:idx_group_snapshot_pair;index;size:36;not null" json:"userId"`
	Payload   string    `gorm:"type:text;not null" json:"payload"`
	Version   int       `gorm:"not null;default:1" json:"version"`
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
}

type ChatArchive struct {
	UserID    string    `gorm:"primaryKey;size:36" json:"userId"`
	Payload   string    `gorm:"type:text;not null" json:"payload"`
	Version   int       `gorm:"not null;default:1" json:"version"`
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
}

type ChatArchiveConversation struct {
	UserID         string    `gorm:"primaryKey;size:36" json:"userId"`
	ConversationID string    `gorm:"primaryKey;size:128" json:"conversationId"`
	SummaryPayload string    `gorm:"type:text;not null" json:"summaryPayload"`
	Payload        string    `gorm:"type:text;not null" json:"payload"`
	Version        int       `gorm:"not null;default:1" json:"version"`
	CreatedAt      time.Time `json:"createdAt"`
	UpdatedAt      time.Time `json:"updatedAt"`
}

type ChatDevice struct {
	ID              string    `gorm:"primaryKey;size:64" json:"id"`
	UserID          string    `gorm:"index;size:36;not null" json:"userId"`
	Protocol        string    `gorm:"size:64;not null" json:"protocol"`
	ProtocolVersion int       `gorm:"not null;default:1" json:"protocolVersion"`
	PublicKey       string    `gorm:"type:text;not null" json:"publicKey"`
	AppInstance     string    `gorm:"size:128" json:"appInstance"`
	LastSeenAt      time.Time `json:"lastSeenAt"`
	CreatedAt       time.Time `json:"createdAt"`
	UpdatedAt       time.Time `json:"updatedAt"`
}

type ChatQueuedEnvelope struct {
	ID                string    `gorm:"primaryKey;size:36" json:"id"`
	RecipientUserID   string    `gorm:"index;size:36;not null" json:"recipientUserId"`
	RecipientDeviceID string    `gorm:"index;size:64;not null" json:"recipientDeviceId"`
	SenderUserID      string    `gorm:"index;size:36;not null" json:"senderUserId"`
	SenderDeviceID    string    `gorm:"size:64;not null" json:"senderDeviceId"`
	Protocol          string    `gorm:"size:64;not null" json:"protocol"`
	Payload           string    `gorm:"type:text;not null" json:"payload"`
	CreatedAt         time.Time `json:"createdAt"`
	ExpiresAt         time.Time `json:"expiresAt"`
}
