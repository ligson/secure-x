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
	case "Payload":
		return "缺少加密负载内容"
	case "Kind":
		return "缺少条目类型"
	default:
		return "请求参数校验失败"
	}
}
