package httpapi

import (
	"errors"
	"log"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/ligson/secure-x/securex-be/internal/middleware"
	"github.com/ligson/secure-x/securex-be/internal/model"
)

var liveKitRoomNamePattern = regexp.MustCompile(`[^a-zA-Z0-9_-]+`)

func (h *Handler) createLiveKitCallToken(c *gin.Context) {
	if !h.liveKitEnabled() {
		RespondFailure(c, http.StatusServiceUnavailable, "音视频通话服务暂未配置")
		return
	}

	var req liveKitCallTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	userID := middleware.CurrentUserID(c)
	peerUserID := strings.TrimSpace(req.PeerUserID)
	if peerUserID == "" || peerUserID == userID {
		log.Printf(
			"LiveKit 通话凭证拒绝：user=%s, peer=%s, reason=无效好友",
			diagnosticID(userID),
			diagnosticID(peerUserID),
		)
		RespondFailure(c, http.StatusBadRequest, "请选择有效的通话好友")
		return
	}
	if !h.canExchangeRealtime(userID, peerUserID) {
		log.Printf(
			"LiveKit 通话凭证拒绝：user=%s, peer=%s, reason=无实时权限",
			diagnosticID(userID),
			diagnosticID(peerUserID),
		)
		RespondFailure(c, http.StatusForbidden, "无权与该用户发起通话")
		return
	}

	identity, err := h.liveKitParticipantIdentity(userID, req.DeviceID)
	if err != nil {
		log.Printf(
			"LiveKit 通话凭证拒绝：user=%s, peer=%s, device=%s, reason=设备校验失败",
			diagnosticID(userID),
			diagnosticID(peerUserID),
			diagnosticID(req.DeviceID),
		)
		RespondFailure(c, http.StatusBadRequest, err.Error())
		return
	}

	roomName := liveKitRoomName(userID, peerUserID, req.CallID)
	token, err := h.issueLiveKitToken(identity, roomName)
	if err != nil {
		log.Printf(
			"LiveKit 通话凭证生成失败：user=%s, peer=%s, call=%s, media=%s, err=%v",
			diagnosticID(userID),
			diagnosticID(peerUserID),
			diagnosticID(req.CallID),
			normalizeCallMedia(req.Media),
			err,
		)
		RespondFailure(c, http.StatusInternalServerError, "生成通话凭证失败")
		return
	}
	log.Printf(
		"LiveKit 通话凭证已签发：user=%s, peer=%s, device=%s, call=%s, media=%s, identity=%s",
		diagnosticID(userID),
		diagnosticID(peerUserID),
		diagnosticID(req.DeviceID),
		diagnosticID(req.CallID),
		normalizeCallMedia(req.Media),
		diagnosticID(identity),
	)

	RespondSuccess(c, http.StatusOK, "通话凭证已生成", gin.H{
		"livekit": gin.H{
			"url":       strings.TrimSpace(h.realtime.LiveKit.URL),
			"token":     token,
			"room":      roomName,
			"identity":  identity,
			"turnMode":  strings.TrimSpace(h.realtime.LiveKit.TurnMode),
			"media":     normalizeCallMedia(req.Media),
			"expiresIn": 2 * 60 * 60,
		},
	})
}

func (h *Handler) liveKitParticipantIdentity(userID string, deviceID string) (string, error) {
	deviceID = strings.TrimSpace(deviceID)
	if deviceID == "" {
		return userID, nil
	}
	var count int64
	if err := h.db.Model(&model.ChatDevice{}).
		Where("id = ? AND user_id = ?", deviceID, userID).
		Count(&count).Error; err != nil {
		return "", err
	}
	if count == 0 {
		return "", errors.New("通话设备未注册，请重新登录后再试")
	}
	identity := liveKitRoomNamePattern.ReplaceAllString(userID+"_"+deviceID, "-")
	if identity == "" {
		return userID, nil
	}
	return identity, nil
}

func (h *Handler) issueLiveKitToken(identity string, roomName string) (string, error) {
	now := time.Now()
	claims := jwt.MapClaims{
		"iss": h.realtime.LiveKit.APIKey,
		"sub": identity,
		"nbf": now.Unix(),
		"exp": now.Add(2 * time.Hour).Unix(),
		"video": map[string]any{
			"roomJoin":     true,
			"room":         roomName,
			"canPublish":   true,
			"canSubscribe": true,
		},
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).
		SignedString([]byte(h.realtime.LiveKit.APISecret))
}

func liveKitRoomName(userID string, peerUserID string, callID string) string {
	parts := []string{strings.TrimSpace(userID), strings.TrimSpace(peerUserID)}
	if parts[0] > parts[1] {
		parts[0], parts[1] = parts[1], parts[0]
	}
	call := liveKitRoomNamePattern.ReplaceAllString(strings.TrimSpace(callID), "-")
	if call == "" {
		call = "call"
	}
	return "securex-" + parts[0] + "-" + parts[1] + "-" + call
}

func normalizeCallMedia(media string) string {
	if strings.EqualFold(strings.TrimSpace(media), "video") {
		return "video"
	}
	return "audio"
}
