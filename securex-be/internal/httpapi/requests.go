package httpapi

import (
	"errors"

	"github.com/go-playground/validator/v10"
)

type registerRequest struct {
	Username            string `json:"username" binding:"required"`
	Email               string `json:"email" binding:"required,email"`
	Password            string `json:"password" binding:"required,min=8"`
	KDFAlgorithm        string `json:"kdfAlgorithm" binding:"required"`
	MasterKeySalt       string `json:"masterKeySalt" binding:"required"`
	MasterKeyIterations int    `json:"masterKeyIterations" binding:"required"`
	WrappedVaultKey     string `json:"wrappedVaultKey" binding:"required"`
}

type loginRequest struct {
	Identifier string `json:"identifier" binding:"required"`
	Password   string `json:"password" binding:"required"`
}

type changePasswordRequest struct {
	CurrentPassword string `json:"currentPassword" binding:"required"`
	NewPassword     string `json:"newPassword" binding:"required,min=8"`
}

type changeUnlockPasswordRequest struct {
	KDFAlgorithm        string `json:"kdfAlgorithm" binding:"required"`
	MasterKeySalt       string `json:"masterKeySalt" binding:"required"`
	MasterKeyIterations int    `json:"masterKeyIterations" binding:"required"`
	WrappedVaultKey     string `json:"wrappedVaultKey" binding:"required"`
}

type updateProfileRequest struct {
	Nickname     string `json:"nickname"`
	AvatarPreset string `json:"avatarPreset"`
}

type folderUpsertRequest struct {
	ParentFolderID *string `json:"parentFolderId"`
	Payload        string  `json:"payload" binding:"required"`
	Version        int     `json:"version"`
}

type itemUpsertRequest struct {
	FolderID *string `json:"folderId"`
	Kind     string  `json:"kind" binding:"required"`
	Payload  string  `json:"payload" binding:"required"`
	Version  int     `json:"version"`
}

type fileMetadataRequest struct {
	FolderID *string `json:"folderId"`
	Payload  string  `json:"payload" binding:"required"`
	Version  int     `json:"version"`
}

type fileUploadStartRequest struct {
	FolderID    *string `json:"folderId"`
	Version     int     `json:"version"`
	TotalChunks int     `json:"totalChunks" binding:"required"`
}

type fileUploadCompleteRequest struct {
	Payload string `json:"payload" binding:"required"`
}

type friendRequestCreateRequest struct {
	Identifier string `json:"identifier" binding:"required"`
	Message    string `json:"message"`
}

type friendAliasUpsertRequest struct {
	Payload string `json:"payload" binding:"required"`
	Version int    `json:"version"`
}

type groupUpsertRequest struct {
	GroupID     string   `json:"groupId"`
	Payload     string   `json:"payload" binding:"required"`
	Version     int      `json:"version"`
	MemberIDs   []string `json:"memberIds"`
	AdminUserID string   `json:"adminUserId"`
}

type groupSnapshotUpsertRequest struct {
	Payload string `json:"payload" binding:"required"`
	Version int    `json:"version"`
}

type groupLeaveRequest struct {
	NextAdminUserID string `json:"nextAdminUserId"`
}

type groupDissolveRequest struct{}

type chatArchiveUpsertRequest struct {
	Payload string `json:"payload" binding:"required"`
	Version int    `json:"version"`
}

type chatArchiveConversationUpsertRequest struct {
	ConversationID string `json:"conversationId" binding:"required"`
	SummaryPayload string `json:"summaryPayload" binding:"required"`
	Payload        string `json:"payload" binding:"required"`
	Version        int    `json:"version"`
}

type chatArchiveBatchUpsertRequest struct {
	Conversations         []chatArchiveConversationUpsertRequest `json:"conversations"`
	DeletedConversationID []string                               `json:"deletedConversationIds"`
}

type chatDeviceUpsertRequest struct {
	DeviceID        string `json:"deviceId" binding:"required"`
	Protocol        string `json:"protocol" binding:"required"`
	ProtocolVersion int    `json:"protocolVersion"`
	PublicKey       string `json:"publicKey" binding:"required"`
	AppInstance     string `json:"appInstance"`
}

type chatDeviceRecoveryUpsertRequest struct {
	Payload string `json:"payload" binding:"required"`
	Version int    `json:"version"`
}

type chatMessageDispatchRequest struct {
	Messages []chatEnvelopeDispatchRequest `json:"messages" binding:"required"`
}

type chatEnvelopeDispatchRequest struct {
	RecipientUserID   string `json:"recipientUserId" binding:"required"`
	RecipientDeviceID string `json:"recipientDeviceId" binding:"required"`
	SenderDeviceID    string `json:"senderDeviceId" binding:"required"`
	Protocol          string `json:"protocol" binding:"required"`
	Payload           string `json:"payload" binding:"required"`
	ExpiresInSeconds  int    `json:"expiresInSeconds"`
}

type chatMessageAckRequest struct {
	DeviceID   string   `json:"deviceId" binding:"required"`
	MessageIDs []string `json:"messageIds" binding:"required"`
}

func bindErrorMessage(err error) string {
	var validationErrors validator.ValidationErrors
	if errors.As(err, &validationErrors) {
		for _, fieldErr := range validationErrors {
			return validationErrorMessage(fieldErr)
		}
	}

	return "请求参数格式不正确"
}

func validationErrorMessage(fieldErr validator.FieldError) string {
	switch fieldErr.Field() {
	case "Username":
		return "用户名不能为空"
	case "Email":
		if fieldErr.Tag() == "email" {
			return "请输入有效的邮箱地址"
		}
		return "邮箱不能为空"
	case "Password":
		if fieldErr.Tag() == "min" {
			return "登录密码至少需要 8 位"
		}
		return "登录密码不能为空"
	case "CurrentPassword":
		return "请输入当前登录密码"
	case "NewPassword":
		if fieldErr.Tag() == "min" {
			return "新登录密码至少需要 8 位"
		}
		return "请输入新登录密码"
	case "Identifier":
		return "请输入用户名或邮箱"
	case "KDFAlgorithm":
		return "缺少密钥派生算法参数"
	case "MasterKeySalt":
		return "缺少主密钥盐值参数"
	case "MasterKeyIterations":
		return "缺少主密钥迭代次数参数"
	case "WrappedVaultKey":
		return "缺少封装后的保险库密钥"
	case "Nickname":
		return "请输入昵称"
	case "Payload":
		return "缺少加密负载内容"
	case "ConversationID":
		return "缺少会话标识"
	case "Kind":
		return "缺少条目类型"
	case "MemberIDs":
		return "缺少群成员信息"
	case "DeviceID":
		return "缺少设备标识"
	case "Protocol":
		return "缺少聊天协议标识"
	case "PublicKey":
		return "缺少设备公钥"
	case "Messages":
		return "缺少聊天消息"
	case "RecipientUserID":
		return "缺少接收用户标识"
	case "RecipientDeviceID":
		return "缺少接收设备标识"
	case "SenderDeviceID":
		return "缺少发送设备标识"
	case "MessageIDs":
		return "缺少待确认消息标识"
	default:
		return "请求参数校验失败"
	}
}
