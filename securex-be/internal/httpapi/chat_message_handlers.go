package httpapi

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/ligson/secure-x/securex-be/internal/middleware"
	"github.com/ligson/secure-x/securex-be/internal/model"
	"gorm.io/gorm"
)

const (
	defaultChatEnvelopeTTL = 30 * 24 * time.Hour
	maxChatEnvelopeTTL     = 90 * 24 * time.Hour
)

func (h *Handler) getCurrentChatDevice(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	deviceID := strings.TrimSpace(c.Query("deviceId"))
	if deviceID == "" {
		RespondFailure(c, http.StatusBadRequest, "请提供设备标识")
		return
	}

	var device model.ChatDevice
	err := h.db.Where("id = ? AND user_id = ?", deviceID, userID).First(&device).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		RespondSuccess(c, http.StatusOK, "设备信息已加载", gin.H{"device": gin.H{}})
		return
	}
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "加载设备信息失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "设备信息已加载", gin.H{
		"device": chatDeviceResponse(device),
	})
}

func (h *Handler) upsertCurrentChatDevice(c *gin.Context) {
	var req chatDeviceUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	userID := middleware.CurrentUserID(c)
	now := time.Now()
	var device model.ChatDevice
	err := h.db.Where("id = ? AND user_id = ?", req.DeviceID, userID).First(&device).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		device = model.ChatDevice{
			ID:              strings.TrimSpace(req.DeviceID),
			UserID:          userID,
			Protocol:        strings.TrimSpace(req.Protocol),
			ProtocolVersion: normalizeVersion(req.ProtocolVersion),
			PublicKey:       strings.TrimSpace(req.PublicKey),
			AppInstance:     strings.TrimSpace(req.AppInstance),
			LastSeenAt:      now,
		}
		if err := h.db.Create(&device).Error; err != nil {
			RespondFailure(c, http.StatusInternalServerError, "保存设备信息失败")
			return
		}
		RespondSuccess(c, http.StatusOK, "设备信息已保存", gin.H{"device": chatDeviceResponse(device)})
		return
	}
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "保存设备信息失败")
		return
	}

	device.Protocol = strings.TrimSpace(req.Protocol)
	device.ProtocolVersion = normalizeVersion(req.ProtocolVersion)
	device.PublicKey = strings.TrimSpace(req.PublicKey)
	device.AppInstance = strings.TrimSpace(req.AppInstance)
	device.LastSeenAt = now
	if err := h.db.Save(&device).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "保存设备信息失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "设备信息已保存", gin.H{"device": chatDeviceResponse(device)})
}

func (h *Handler) listUserChatDevices(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	targetUserID := strings.TrimSpace(c.Param("id"))
	if targetUserID == "" {
		RespondFailure(c, http.StatusBadRequest, "缺少目标用户标识")
		return
	}
	if !h.canExchangeRealtime(userID, targetUserID) && userID != targetUserID {
		RespondFailure(c, http.StatusForbidden, "无权查看该用户聊天设备")
		return
	}

	var devices []model.ChatDevice
	if err := h.db.Where("user_id = ?", targetUserID).Order("updated_at desc").Find(&devices).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "加载聊天设备失败")
		return
	}

	responses := make([]gin.H, 0, len(devices))
	for _, device := range devices {
		responses = append(responses, chatDeviceResponse(device))
	}
	RespondSuccess(c, http.StatusOK, "聊天设备已加载", gin.H{"devices": responses})
}

func (h *Handler) dispatchChatMessages(c *gin.Context) {
	var req chatMessageDispatchRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}
	if len(req.Messages) == 0 {
		RespondFailure(c, http.StatusBadRequest, "至少需要一条聊天消息")
		return
	}

	userID := middleware.CurrentUserID(c)
	saved := make([]model.ChatQueuedEnvelope, 0, len(req.Messages))
	err := h.db.Transaction(func(tx *gorm.DB) error {
		for _, message := range req.Messages {
			allowed, err := h.canSendChatEnvelope(
				userID,
				strings.TrimSpace(message.RecipientUserID),
				strings.TrimSpace(message.RecipientDeviceID),
			)
			if err != nil {
				return err
			}
			if !allowed {
				return gorm.ErrInvalidData
			}
			expiresAt := time.Now().Add(defaultChatEnvelopeTTL)
			if message.ExpiresInSeconds > 0 {
				custom := time.Duration(message.ExpiresInSeconds) * time.Second
				if custom > maxChatEnvelopeTTL {
					custom = maxChatEnvelopeTTL
				}
				expiresAt = time.Now().Add(custom)
			}
			envelope := model.ChatQueuedEnvelope{
				ID:                uuid.NewString(),
				RecipientUserID:   strings.TrimSpace(message.RecipientUserID),
				RecipientDeviceID: strings.TrimSpace(message.RecipientDeviceID),
				SenderUserID:      userID,
				SenderDeviceID:    strings.TrimSpace(message.SenderDeviceID),
				Protocol:          strings.TrimSpace(message.Protocol),
				Payload:           strings.TrimSpace(message.Payload),
				ExpiresAt:         expiresAt,
			}
			if err := tx.Create(&envelope).Error; err != nil {
				return err
			}
			saved = append(saved, envelope)
		}
		return nil
	})
	if err != nil {
		if errors.Is(err, gorm.ErrInvalidData) {
			RespondFailure(c, http.StatusForbidden, "无权向目标设备发送聊天消息")
			return
		}
		RespondFailure(c, http.StatusInternalServerError, "保存聊天消息失败")
		return
	}

	for _, envelope := range saved {
		h.realtimeHub.notifyChatPending(
			envelope.RecipientUserID,
			envelope.RecipientDeviceID,
			envelope.SenderUserID,
		)
	}

	RespondSuccess(c, http.StatusOK, "聊天消息已入队", gin.H{
		"queuedCount": len(saved),
	})
}

func (h *Handler) listPendingChatMessages(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	deviceID := strings.TrimSpace(c.Query("deviceId"))
	if deviceID == "" {
		RespondFailure(c, http.StatusBadRequest, "请提供设备标识")
		return
	}
	if ok, err := h.ownsChatDevice(userID, deviceID); err != nil {
		RespondFailure(c, http.StatusInternalServerError, "校验设备失败")
		return
	} else if !ok {
		RespondFailure(c, http.StatusForbidden, "该设备不属于当前用户")
		return
	}

	var envelopes []model.ChatQueuedEnvelope
	if err := h.db.
		Where("recipient_user_id = ? AND recipient_device_id = ? AND expires_at > ?", userID, deviceID, time.Now()).
		Order("created_at asc").
		Limit(500).
		Find(&envelopes).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "加载待同步聊天消息失败")
		return
	}

	responses := make([]gin.H, 0, len(envelopes))
	for _, envelope := range envelopes {
		responses = append(responses, gin.H{
			"id":             envelope.ID,
			"senderUserId":   envelope.SenderUserID,
			"senderDeviceId": envelope.SenderDeviceID,
			"protocol":       envelope.Protocol,
			"payload":        envelope.Payload,
			"createdAt":      envelope.CreatedAt,
		})
	}
	RespondSuccess(c, http.StatusOK, "待同步聊天消息已加载", gin.H{
		"messages": responses,
	})
}

func (h *Handler) ackChatMessages(c *gin.Context) {
	var req chatMessageAckRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}
	if len(req.MessageIDs) == 0 {
		RespondFailure(c, http.StatusBadRequest, "至少需要一条待确认消息")
		return
	}

	userID := middleware.CurrentUserID(c)
	deviceID := strings.TrimSpace(req.DeviceID)
	if ok, err := h.ownsChatDevice(userID, deviceID); err != nil {
		RespondFailure(c, http.StatusInternalServerError, "校验设备失败")
		return
	} else if !ok {
		RespondFailure(c, http.StatusForbidden, "该设备不属于当前用户")
		return
	}

	if err := h.db.
		Where(
			"recipient_user_id = ? AND recipient_device_id = ? AND id IN ?",
			userID,
			deviceID,
			normalizeUniqueIDs(req.MessageIDs),
		).
		Delete(&model.ChatQueuedEnvelope{}).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "确认聊天消息失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "聊天消息已确认", gin.H{})
}

func chatDeviceResponse(device model.ChatDevice) gin.H {
	return gin.H{
		"id":              device.ID,
		"userId":          device.UserID,
		"protocol":        device.Protocol,
		"protocolVersion": device.ProtocolVersion,
		"publicKey":       device.PublicKey,
		"appInstance":     device.AppInstance,
		"lastSeenAt":      device.LastSeenAt,
		"createdAt":       device.CreatedAt,
		"updatedAt":       device.UpdatedAt,
	}
}

func (h *Handler) canSendChatEnvelope(senderUserID, recipientUserID, recipientDeviceID string) (bool, error) {
	if recipientUserID == "" || recipientDeviceID == "" {
		return false, nil
	}
	if ok, err := h.chatDeviceBelongsToUser(recipientUserID, recipientDeviceID); err != nil {
		return false, err
	} else if !ok {
		return false, nil
	}
	if senderUserID == recipientUserID {
		return true, nil
	}
	return h.canExchangeRealtime(senderUserID, recipientUserID), nil
}

func (h *Handler) ownsChatDevice(userID, deviceID string) (bool, error) {
	return h.chatDeviceBelongsToUser(userID, deviceID)
}

func (h *Handler) chatDeviceBelongsToUser(userID, deviceID string) (bool, error) {
	var count int64
	if err := h.db.Model(&model.ChatDevice{}).
		Where("id = ? AND user_id = ?", deviceID, userID).
		Count(&count).Error; err != nil {
		return false, err
	}
	return count > 0, nil
}
