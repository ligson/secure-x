package httpapi

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/ligson/secure-x/securex-be/internal/middleware"
	"github.com/ligson/secure-x/securex-be/internal/model"
	"gorm.io/gorm"
)

func (h *Handler) getChatArchive(c *gin.Context) {
	userID := middleware.CurrentUserID(c)

	var archive model.ChatArchive
	err := h.db.Where("user_id = ?", userID).First(&archive).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		RespondSuccess(c, http.StatusOK, "聊天归档已加载", gin.H{
			"payload": "",
			"version": 0,
		})
		return
	}
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "加载聊天归档失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "聊天归档已加载", gin.H{
		"payload": archive.Payload,
		"version": archive.Version,
	})
}

func (h *Handler) upsertChatArchive(c *gin.Context) {
	var req chatArchiveUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	userID := middleware.CurrentUserID(c)
	var archive model.ChatArchive
	err := h.db.Where("user_id = ?", userID).First(&archive).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		archive = model.ChatArchive{
			UserID:  userID,
			Payload: req.Payload,
			Version: normalizeVersion(req.Version),
		}
		if err := h.db.Create(&archive).Error; err != nil {
			RespondFailure(c, http.StatusInternalServerError, "保存聊天归档失败")
			return
		}
		RespondSuccess(c, http.StatusOK, "聊天归档已保存", gin.H{})
		return
	}
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "保存聊天归档失败")
		return
	}

	archive.Payload = req.Payload
	archive.Version = normalizeVersion(req.Version)
	if err := h.db.Save(&archive).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "保存聊天归档失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "聊天归档已保存", gin.H{})
}
