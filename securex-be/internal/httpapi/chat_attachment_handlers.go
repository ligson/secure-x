package httpapi

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/ligson/secure-x/securex-be/internal/middleware"
	"github.com/ligson/secure-x/securex-be/internal/model"
	"gorm.io/gorm"
)

const maxChatAttachmentCipherBytes = 25 * 1024 * 1024

type chatAttachmentMetadata struct {
	AllowedUserIDs []string `json:"allowedUserIds"`
}

func (h *Handler) uploadChatAttachment(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	metadataRaw := strings.TrimSpace(c.PostForm("metadata"))
	if metadataRaw == "" {
		RespondFailure(c, http.StatusBadRequest, "请提供聊天附件元数据")
		return
	}

	var metadata chatAttachmentMetadata
	if err := json.Unmarshal([]byte(metadataRaw), &metadata); err != nil {
		RespondFailure(c, http.StatusBadRequest, "聊天附件元数据格式不正确")
		return
	}
	allowedUserIDs := normalizeUniqueIDs(metadata.AllowedUserIDs)
	for _, allowedUserID := range allowedUserIDs {
		if allowedUserID == "" || allowedUserID == userID {
			continue
		}
		if !h.canExchangeRealtime(userID, allowedUserID) {
			RespondFailure(c, http.StatusForbidden, "无权给目标用户发送聊天附件")
			return
		}
	}

	fileHeader, err := c.FormFile("cipher_file")
	if err != nil {
		RespondFailure(c, http.StatusBadRequest, "请上传聊天附件密文")
		return
	}
	if fileHeader.Size <= 0 || fileHeader.Size > maxChatAttachmentCipherBytes {
		RespondFailure(c, http.StatusBadRequest, "聊天附件大小不符合要求")
		return
	}
	file, err := fileHeader.Open()
	if err != nil {
		RespondFailure(c, http.StatusBadRequest, "读取聊天附件失败")
		return
	}
	defer file.Close()

	attachmentID := uuid.NewString()
	relativePath := "chat-attachments/" + userID + "/" + attachmentID + ".bin"
	written, fullPath, err := h.fileStore.Save(relativePath, file)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "保存聊天附件失败")
		return
	}
	if written <= 0 || written > maxChatAttachmentCipherBytes {
		_ = h.fileStore.Delete(fullPath)
		RespondFailure(c, http.StatusBadRequest, "聊天附件大小不符合要求")
		return
	}

	allowedJSON, err := json.Marshal(allowedUserIDs)
	if err != nil {
		_ = h.fileStore.Delete(fullPath)
		RespondFailure(c, http.StatusInternalServerError, "保存聊天附件失败")
		return
	}
	attachment := model.ChatAttachment{
		ID:             attachmentID,
		OwnerUserID:    userID,
		AllowedUserIDs: string(allowedJSON),
		StoragePath:    fullPath,
		CipherSize:     written,
	}
	if err := h.db.Create(&attachment).Error; err != nil {
		_ = h.fileStore.Delete(fullPath)
		RespondFailure(c, http.StatusInternalServerError, "保存聊天附件失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "聊天附件密文已保存", gin.H{
		"attachment": gin.H{
			"id":         attachment.ID,
			"cipherSize": attachment.CipherSize,
		},
	})
}

func (h *Handler) downloadChatAttachment(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	attachmentID := strings.TrimSpace(c.Param("id"))
	if attachmentID == "" {
		RespondFailure(c, http.StatusBadRequest, "缺少聊天附件标识")
		return
	}

	var attachment model.ChatAttachment
	err := h.db.Where("id = ?", attachmentID).First(&attachment).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		RespondFailure(c, http.StatusNotFound, "聊天附件不存在")
		return
	}
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "加载聊天附件失败")
		return
	}
	if !h.canAccessChatAttachment(userID, attachment) {
		RespondFailure(c, http.StatusForbidden, "无权下载该聊天附件")
		return
	}

	cipherBytes, err := os.ReadFile(attachment.StoragePath)
	if err != nil {
		RespondFailure(c, http.StatusNotFound, "聊天附件密文不存在")
		return
	}
	RespondSuccess(c, http.StatusOK, "聊天附件密文已加载", gin.H{
		"attachment": gin.H{
			"id":               attachment.ID,
			"cipherSize":       attachment.CipherSize,
			"cipherTextBase64": base64.StdEncoding.EncodeToString(cipherBytes),
		},
	})
}

func (h *Handler) canAccessChatAttachment(userID string, attachment model.ChatAttachment) bool {
	if strings.TrimSpace(userID) == "" {
		return false
	}
	if userID == attachment.OwnerUserID {
		return true
	}
	var allowedUserIDs []string
	if err := json.Unmarshal([]byte(attachment.AllowedUserIDs), &allowedUserIDs); err != nil {
		return false
	}
	for _, allowedUserID := range allowedUserIDs {
		if allowedUserID == userID && h.canExchangeRealtime(attachment.OwnerUserID, userID) {
			return true
		}
	}
	return false
}
