package httpapi

import (
	"errors"
	"log"
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
	defaultChatEnvelopeTTL      = 30 * 24 * time.Hour
	maxChatEnvelopeTTL          = 90 * 24 * time.Hour
	activeChatDeviceWindow      = 14 * 24 * time.Hour
	maxActiveChatDevicesPerUser = 20
	fallbackChatDevicesPerUser  = 1
	maxChatMessageDispatchBatch = 500
	maxStoredChatDevicesPerUser = 100
	maxNewChatDevicesPerMinute  = 5
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
	deviceID := strings.TrimSpace(req.DeviceID)
	if deviceID == "" {
		RespondFailure(c, http.StatusBadRequest, "请提供设备标识")
		return
	}

	var device model.ChatDevice
	if err := h.db.Where("id = ? AND user_id = ?", deviceID, userID).Limit(1).Find(&device).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "保存设备信息失败")
		return
	}
	if device.ID == "" {
		if h.tooManyNewChatDevices(userID, now) {
			RespondFailure(c, http.StatusTooManyRequests, "设备注册过于频繁，请稍后重试")
			return
		}
		device = model.ChatDevice{
			ID:              deviceID,
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
		h.pruneExcessChatDevices(userID)
		RespondSuccess(c, http.StatusOK, "设备信息已保存", gin.H{"device": chatDeviceResponse(device)})
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

func (h *Handler) listOwnChatDevices(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var devices []model.ChatDevice
	if err := h.db.
		Where("user_id = ?", userID).
		Order("last_seen_at desc, updated_at desc").
		Limit(maxStoredChatDevicesPerUser).
		Find(&devices).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "加载设备列表失败")
		return
	}

	responses := make([]gin.H, 0, len(devices))
	for _, device := range devices {
		responses = append(responses, chatDeviceResponse(device))
	}
	RespondSuccess(c, http.StatusOK, "设备列表已加载", gin.H{"devices": responses})
}

func (h *Handler) deleteOwnChatDevice(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	deviceID := strings.TrimSpace(c.Param("id"))
	if deviceID == "" {
		RespondFailure(c, http.StatusBadRequest, "缺少设备标识")
		return
	}

	err := h.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.
			Where("user_id = ? AND id = ?", userID, deviceID).
			Delete(&model.ChatDevice{}).Error; err != nil {
			return err
		}
		return tx.
			Where("recipient_user_id = ? AND recipient_device_id = ?", userID, deviceID).
			Delete(&model.ChatQueuedEnvelope{}).Error
	})
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "删除设备失败")
		return
	}
	RespondSuccess(c, http.StatusOK, "设备已删除", gin.H{})
}

func (h *Handler) getChatDeviceRecovery(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var recovery model.ChatDeviceRecovery
	err := h.db.Where("user_id = ?", userID).First(&recovery).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		RespondSuccess(c, http.StatusOK, "设备恢复包已加载", gin.H{"recovery": gin.H{}})
		return
	}
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "加载设备恢复包失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "设备恢复包已加载", gin.H{
		"recovery": gin.H{
			"payload":   recovery.Payload,
			"version":   recovery.Version,
			"updatedAt": recovery.UpdatedAt,
		},
	})
}

func (h *Handler) upsertChatDeviceRecovery(c *gin.Context) {
	var req chatDeviceRecoveryUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	userID := middleware.CurrentUserID(c)
	version := normalizeVersion(req.Version)
	var recovery model.ChatDeviceRecovery
	if err := h.db.Where("user_id = ?", userID).Limit(1).Find(&recovery).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "保存设备恢复包失败")
		return
	}
	if recovery.UserID == "" {
		recovery = model.ChatDeviceRecovery{
			UserID:  userID,
			Payload: strings.TrimSpace(req.Payload),
			Version: version,
		}
		if err := h.db.Create(&recovery).Error; err != nil {
			RespondFailure(c, http.StatusInternalServerError, "保存设备恢复包失败")
			return
		}
		RespondSuccess(c, http.StatusOK, "设备恢复包已保存", gin.H{})
		return
	}
	if version < recovery.Version {
		RespondSuccess(c, http.StatusOK, "设备恢复包已保存", gin.H{})
		return
	}
	recovery.Payload = strings.TrimSpace(req.Payload)
	recovery.Version = version
	if err := h.db.Save(&recovery).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "保存设备恢复包失败")
		return
	}
	RespondSuccess(c, http.StatusOK, "设备恢复包已保存", gin.H{})
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

	devices, err := h.activeChatDevices(targetUserID)
	if err != nil {
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
	if len(req.Messages) > maxChatMessageDispatchBatch {
		RespondFailure(c, http.StatusBadRequest, "单次发送的聊天消息过多，请稍后重试")
		return
	}

	userID := middleware.CurrentUserID(c)
	allowedMessages := make([]chatEnvelopeDispatchRequest, 0, len(req.Messages))
	skippedCount := 0
	for _, message := range req.Messages {
		recipientUserID := strings.TrimSpace(message.RecipientUserID)
		recipientDeviceID := strings.TrimSpace(message.RecipientDeviceID)
		if recipientUserID == "" ||
			recipientDeviceID == "" ||
			strings.TrimSpace(message.SenderDeviceID) == "" ||
			strings.TrimSpace(message.Protocol) == "" ||
			strings.TrimSpace(message.Payload) == "" {
			skippedCount++
			continue
		}
		allowed, err := h.canSendChatEnvelope(
			userID,
			recipientUserID,
			recipientDeviceID,
		)
		if err != nil {
			RespondFailure(c, http.StatusInternalServerError, "保存聊天消息失败")
			return
		}
		if !allowed {
			deviceExists, err := h.chatDeviceBelongsToUser(recipientUserID, recipientDeviceID)
			if err != nil {
				RespondFailure(c, http.StatusInternalServerError, "保存聊天消息失败")
				return
			}
			if deviceExists {
				RespondFailure(c, http.StatusForbidden, "无权向目标设备发送聊天消息")
				return
			}
			skippedCount++
			log.Printf(
				"聊天消息跳过无效目标设备：sender=%s, recipient=%s, device=%s",
				userID,
				recipientUserID,
				recipientDeviceID,
			)
			continue
		}
		message.RecipientUserID = recipientUserID
		message.RecipientDeviceID = recipientDeviceID
		message.SenderDeviceID = strings.TrimSpace(message.SenderDeviceID)
		message.Protocol = strings.TrimSpace(message.Protocol)
		message.Payload = strings.TrimSpace(message.Payload)
		allowedMessages = append(allowedMessages, message)
	}
	if len(allowedMessages) == 0 {
		RespondSuccess(c, http.StatusOK, "聊天消息未入队，目标设备暂不可用", gin.H{
			"queuedCount":  0,
			"skippedCount": skippedCount,
		})
		return
	}

	saved := make([]model.ChatQueuedEnvelope, 0, len(allowedMessages))
	now := time.Now()
	err := h.db.Transaction(func(tx *gorm.DB) error {
		for _, message := range allowedMessages {
			expiresAt := now.Add(defaultChatEnvelopeTTL)
			if message.ExpiresInSeconds > 0 {
				custom := time.Duration(message.ExpiresInSeconds) * time.Second
				if custom > maxChatEnvelopeTTL {
					custom = maxChatEnvelopeTTL
				}
				expiresAt = now.Add(custom)
			}
			envelope := model.ChatQueuedEnvelope{
				ID:                uuid.NewString(),
				RecipientUserID:   message.RecipientUserID,
				RecipientDeviceID: message.RecipientDeviceID,
				SenderUserID:      userID,
				SenderDeviceID:    message.SenderDeviceID,
				Protocol:          message.Protocol,
				Payload:           message.Payload,
				ExpiresAt:         expiresAt,
			}
			saved = append(saved, envelope)
		}
		return tx.CreateInBatches(&saved, 100).Error
	})
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "保存聊天消息失败")
		return
	}

	for _, envelope := range saved {
		h.realtimeHub.notifyChatPending(
			envelope.RecipientUserID,
			envelope.RecipientDeviceID,
			envelope.SenderUserID,
		)
		h.realtimeHub.forwardToDevice(envelope.RecipientUserID, envelope.RecipientDeviceID, realtimeSignal{
			Type: "chat-envelope",
			From: envelope.SenderUserID,
			Payload: map[string]any{
				"envelopeId":        envelope.ID,
				"recipientDeviceId": envelope.RecipientDeviceID,
				"senderUserId":      envelope.SenderUserID,
				"senderDeviceId":    envelope.SenderDeviceID,
				"protocol":          envelope.Protocol,
				"payload":           envelope.Payload,
				"createdAt":         envelope.CreatedAt,
			},
		})
	}

	RespondSuccess(c, http.StatusOK, "聊天消息已入队", gin.H{
		"queuedCount":  len(saved),
		"skippedCount": skippedCount,
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

	senderUserID := strings.TrimSpace(c.Query("senderUserId"))
	query := h.db.
		Where("recipient_user_id = ? AND recipient_device_id = ? AND expires_at > ?", userID, deviceID, time.Now())
	if senderUserID != "" {
		query = query.Where("sender_user_id = ?", senderUserID)
	}

	var envelopes []model.ChatQueuedEnvelope
	if err := query.
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

func (h *Handler) activeChatDevices(userID string) ([]model.ChatDevice, error) {
	cutoff := time.Now().Add(-activeChatDeviceWindow)
	devices := []model.ChatDevice{}
	if err := h.db.
		Where("user_id = ? AND last_seen_at >= ?", userID, cutoff).
		Order("last_seen_at desc, updated_at desc").
		Limit(maxActiveChatDevicesPerUser).
		Find(&devices).Error; err != nil {
		return nil, err
	}
	if len(devices) > 0 {
		return devices, nil
	}

	// 离线很久的用户保留最后一个设备作为兜底，避免完全无法投递加密离线消息。
	if err := h.db.
		Where("user_id = ?", userID).
		Order("last_seen_at desc, updated_at desc").
		Limit(fallbackChatDevicesPerUser).
		Find(&devices).Error; err != nil {
		return nil, err
	}
	return devices, nil
}

func (h *Handler) pruneExcessChatDevices(userID string) {
	if strings.TrimSpace(userID) == "" {
		return
	}

	_ = h.db.
		Exec(
			`DELETE FROM chat_devices
			  WHERE user_id = ?
			    AND id NOT IN (
			      SELECT id FROM chat_devices
			      WHERE user_id = ?
			      ORDER BY last_seen_at DESC, updated_at DESC
			      LIMIT ?
			    )
			    AND NOT EXISTS (
			      SELECT 1 FROM chat_queued_envelopes
			      WHERE recipient_user_id = chat_devices.user_id
			        AND recipient_device_id = chat_devices.id
			        AND expires_at > ?
			    )`,
			userID,
			userID,
			maxStoredChatDevicesPerUser,
			time.Now(),
		).
		Error
}

func (h *Handler) tooManyNewChatDevices(userID string, now time.Time) bool {
	if strings.TrimSpace(userID) == "" {
		return true
	}
	var count int64
	if err := h.db.Model(&model.ChatDevice{}).
		Where("user_id = ? AND created_at >= ?", userID, now.Add(-time.Minute)).
		Count(&count).Error; err != nil {
		return true
	}
	return count >= maxNewChatDevicesPerMinute
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
