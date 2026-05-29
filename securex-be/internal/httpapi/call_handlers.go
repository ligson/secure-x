package httpapi

import (
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/ligson/secure-x/securex-be/internal/middleware"
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
		RespondFailure(c, http.StatusBadRequest, "请选择有效的通话好友")
		return
	}
	if !h.canExchangeRealtime(userID, peerUserID) {
		RespondFailure(c, http.StatusForbidden, "无权与该用户发起通话")
		return
	}

	roomName := liveKitRoomName(userID, peerUserID, req.CallID)
	token, err := h.issueLiveKitToken(userID, roomName)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "生成通话凭证失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "通话凭证已生成", gin.H{
		"livekit": gin.H{
			"url":       strings.TrimSpace(h.realtime.LiveKit.URL),
			"token":     token,
			"room":      roomName,
			"turnMode":  strings.TrimSpace(h.realtime.LiveKit.TurnMode),
			"media":     normalizeCallMedia(req.Media),
			"expiresIn": 2 * 60 * 60,
		},
	})
}

func (h *Handler) issueLiveKitToken(userID string, roomName string) (string, error) {
	now := time.Now()
	claims := jwt.MapClaims{
		"iss": h.realtime.LiveKit.APIKey,
		"sub": userID,
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
