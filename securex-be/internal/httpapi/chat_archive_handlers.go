package httpapi

import (
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/ligson/secure-x/securex-be/internal/middleware"
	"github.com/ligson/secure-x/securex-be/internal/model"
	"gorm.io/gorm"
)

const chatArchiveManifestFormatVersion = 1

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

func (h *Handler) getChatArchiveManifest(c *gin.Context) {
	userID := middleware.CurrentUserID(c)

	var conversations []model.ChatArchiveConversation
	if err := h.db.
		Where("user_id = ?", userID).
		Order("updated_at desc").
		Find(&conversations).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "加载聊天归档清单失败")
		return
	}

	items := make([]gin.H, 0, len(conversations))
	for _, conversation := range conversations {
		items = append(items, gin.H{
			"conversationId": conversation.ConversationID,
			"summaryPayload": conversation.SummaryPayload,
			"version":        conversation.Version,
			"updatedAt":      conversation.UpdatedAt,
		})
	}

	RespondSuccess(c, http.StatusOK, "聊天归档清单已加载", gin.H{
		"formatVersion": chatArchiveManifestFormatVersion,
		"conversations": items,
	})
}

func (h *Handler) listChatArchiveConversations(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	ids := splitCommaValues(c.Query("ids"))
	if len(ids) == 0 {
		RespondFailure(c, http.StatusBadRequest, "请提供会话标识")
		return
	}

	var conversations []model.ChatArchiveConversation
	if err := h.db.
		Where("user_id = ? AND conversation_id IN ?", userID, ids).
		Find(&conversations).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "加载聊天归档详情失败")
		return
	}

	byID := make(map[string]model.ChatArchiveConversation, len(conversations))
	for _, conversation := range conversations {
		byID[conversation.ConversationID] = conversation
	}

	items := make([]gin.H, 0, len(ids))
	for _, id := range ids {
		conversation, ok := byID[id]
		if !ok {
			continue
		}
		items = append(items, gin.H{
			"conversationId": conversation.ConversationID,
			"summaryPayload": conversation.SummaryPayload,
			"payload":        conversation.Payload,
			"version":        conversation.Version,
			"updatedAt":      conversation.UpdatedAt,
		})
	}

	RespondSuccess(c, http.StatusOK, "聊天归档详情已加载", gin.H{
		"conversations": items,
	})
}

func (h *Handler) upsertChatArchiveConversations(c *gin.Context) {
	var req chatArchiveBatchUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	if len(req.Conversations) == 0 && len(req.DeletedConversationID) == 0 {
		RespondFailure(c, http.StatusBadRequest, "至少需要一条会话归档变更")
		return
	}

	userID := middleware.CurrentUserID(c)
	upsertedCount := 0
	deletedCount := 0
	err := h.db.Transaction(func(tx *gorm.DB) error {
		for _, item := range req.Conversations {
			conversationID := strings.TrimSpace(item.ConversationID)
			if conversationID == "" {
				return gorm.ErrInvalidData
			}

			var conversation model.ChatArchiveConversation
			err := tx.Where(
				"user_id = ? AND conversation_id = ?",
				userID,
				conversationID,
			).First(&conversation).Error
			if errors.Is(err, gorm.ErrRecordNotFound) {
				conversation = model.ChatArchiveConversation{
					UserID:         userID,
					ConversationID: conversationID,
					SummaryPayload: strings.TrimSpace(item.SummaryPayload),
					Payload:        strings.TrimSpace(item.Payload),
					Version:        normalizeVersion(item.Version),
				}
				if err := tx.Create(&conversation).Error; err != nil {
					return err
				}
				upsertedCount++
				continue
			}
			if err != nil {
				return err
			}

			conversation.SummaryPayload = strings.TrimSpace(item.SummaryPayload)
			conversation.Payload = strings.TrimSpace(item.Payload)
			conversation.Version = normalizeVersion(item.Version)
			if err := tx.Save(&conversation).Error; err != nil {
				return err
			}
			upsertedCount++
		}

		for _, rawID := range req.DeletedConversationID {
			conversationID := strings.TrimSpace(rawID)
			if conversationID == "" {
				continue
			}
			result := tx.Where(
				"user_id = ? AND conversation_id = ?",
				userID,
				conversationID,
			).Delete(&model.ChatArchiveConversation{})
			if result.Error != nil {
				return result.Error
			}
			deletedCount += int(result.RowsAffected)
		}

		return nil
	})
	if errors.Is(err, gorm.ErrInvalidData) {
		RespondFailure(c, http.StatusBadRequest, "会话归档参数不完整")
		return
	}
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "保存会话归档失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "会话归档已保存", gin.H{
		"upsertedCount": upsertedCount,
		"deletedCount":  deletedCount,
	})
}

func splitCommaValues(raw string) []string {
	if strings.TrimSpace(raw) == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	result := make([]string, 0, len(parts))
	seen := make(map[string]struct{}, len(parts))
	for _, part := range parts {
		value := strings.TrimSpace(part)
		if value == "" {
			continue
		}
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		result = append(result, value)
	}
	return result
}
