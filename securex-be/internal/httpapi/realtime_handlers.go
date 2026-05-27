package httpapi

import (
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/ligson/secure-x/securex-be/internal/middleware"
	"github.com/ligson/secure-x/securex-be/internal/model"
)

const (
	realtimeWriteWait = 10 * time.Second
	realtimePongWait  = 75 * time.Second
	realtimePingEvery = 25 * time.Second
)

func (h *Handler) realtimeConfig(c *gin.Context) {
	scheme := "ws"
	if strings.EqualFold(c.GetHeader("X-Forwarded-Proto"), "https") || c.Request.TLS != nil {
		scheme = "wss"
	}
	host := c.Request.Host
	if forwardedHost := strings.TrimSpace(c.GetHeader("X-Forwarded-Host")); forwardedHost != "" {
		host = firstForwardedValue(forwardedHost)
	}
	prefix := h.publicBasePath(c)

	RespondSuccess(c, http.StatusOK, "实时服务配置已加载", gin.H{
		"transport":        "websocket_e2ee",
		"signalingEnabled": true,
		"signalingUrl":     scheme + "://" + host + prefix + "/api/v1/realtime/ws",
		"iceServers":       []string{},
		"relayMode":        "encrypted_websocket_primary",
		"messageStorage":   "user_encrypted_archive",
	})
}

func (h *Handler) publicBasePath(c *gin.Context) string {
	if forwardedPrefix := normalizeForwardedPrefix(c.GetHeader("X-Forwarded-Prefix")); forwardedPrefix != "" {
		return forwardedPrefix
	}
	return normalizeForwardedPrefix(h.server.PublicBasePath)
}

func firstForwardedValue(raw string) string {
	parts := strings.Split(raw, ",")
	for _, part := range parts {
		value := strings.TrimSpace(part)
		if value != "" {
			return value
		}
	}
	return strings.TrimSpace(raw)
}

func normalizeForwardedPrefix(raw string) string {
	value := strings.TrimSpace(raw)
	if value == "" || value == "/" {
		return ""
	}
	if !strings.HasPrefix(value, "/") {
		value = "/" + value
	}
	return strings.TrimRight(value, "/")
}

func (h *Handler) realtimePresence(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	rawIDs := c.QueryArray("userIds")
	if len(rawIDs) == 0 {
		if single := strings.TrimSpace(c.Query("userIds")); single != "" {
			rawIDs = strings.Split(single, ",")
		}
	}

	peerIDs := normalizeUniqueIDs(rawIDs)
	statuses := make([]gin.H, 0, len(peerIDs))
	for _, peerID := range peerIDs {
		if peerID == "" {
			continue
		}
		if peerID != userID && !h.canExchangeRealtime(userID, peerID) {
			continue
		}
		lastSeenAt := h.latestChatDeviceSeenAt(peerID)
		statuses = append(statuses, gin.H{
			"userId":     peerID,
			"online":     h.realtimeHub.isOnline(peerID),
			"lastSeenAt": lastSeenAt,
		})
	}

	RespondSuccess(c, http.StatusOK, "在线状态快照已加载", gin.H{
		"statuses": statuses,
	})
}

var realtimeUpgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

type realtimeHub struct {
	mu      sync.RWMutex
	clients map[string]map[*realtimeClient]struct{}
}

type realtimeClient struct {
	userID   string
	deviceID string
	conn     *websocket.Conn
	send     chan realtimeSignal
	hub      *realtimeHub
	writeMu  sync.Mutex
}

type realtimeSignal struct {
	Type    string         `json:"type"`
	From    string         `json:"from,omitempty"`
	To      string         `json:"to,omitempty"`
	Payload map[string]any `json:"payload,omitempty"`
}

func newRealtimeHub() *realtimeHub {
	return &realtimeHub{clients: map[string]map[*realtimeClient]struct{}{}}
}

func (h *Handler) realtimeWebSocket(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	conn, err := realtimeUpgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("实时信令连接升级失败：userID=%s, err=%v", userID, err)
		return
	}

	wasOnline := h.realtimeHub.isOnline(userID)
	client := &realtimeClient{
		userID:   userID,
		deviceID: strings.TrimSpace(c.Query("deviceId")),
		conn:     conn,
		send:     make(chan realtimeSignal, 16),
		hub:      h.realtimeHub,
	}
	h.realtimeHub.add(client)
	if client.deviceID != "" {
		_ = h.db.Model(&model.ChatDevice{}).
			Where("id = ? AND user_id = ?", client.deviceID, userID).
			Update("last_seen_at", time.Now()).
			Error
	}
	log.Printf("实时信令已连接：userID=%s", userID)
	go client.writeLoop()

	peerIDs := h.realtimePeerIDs(userID)
	h.realtimeHub.sendPresenceSnapshot(client, peerIDs)
	if !wasOnline {
		h.realtimeHub.broadcastPresence(userID, true, peerIDs)
	}
	defer func() {
		h.realtimeHub.remove(client)
		log.Printf("实时信令已断开：userID=%s", userID)
		if !h.realtimeHub.isOnline(userID) {
			h.realtimeHub.broadcastPresence(userID, false, peerIDs)
		}
	}()

	client.readLoop(h)
}

func (h *realtimeHub) add(client *realtimeClient) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.clients[client.userID] == nil {
		h.clients[client.userID] = map[*realtimeClient]struct{}{}
	}
	h.clients[client.userID][client] = struct{}{}
}

func (h *realtimeHub) remove(client *realtimeClient) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.clients[client.userID] != nil {
		delete(h.clients[client.userID], client)
		if len(h.clients[client.userID]) == 0 {
			delete(h.clients, client.userID)
		}
	}
	close(client.send)
	_ = client.conn.Close()
}

func (h *realtimeHub) isOnline(userID string) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()

	return len(h.clients[userID]) > 0
}

func (h *realtimeHub) broadcastPresence(userID string, online bool, friendIDs []string) {
	signal := realtimeSignal{
		Type: "presence",
		From: userID,
		Payload: map[string]any{
			"online": online,
		},
	}
	for _, friendID := range friendIDs {
		h.forward(friendID, signal)
	}
}

func (h *realtimeHub) sendPresenceSnapshot(client *realtimeClient, friendIDs []string) {
	for _, friendID := range friendIDs {
		client.send <- realtimeSignal{
			Type: "presence",
			From: friendID,
			Payload: map[string]any{
				"online": h.isOnline(friendID),
			},
		}
	}
}

func (h *realtimeHub) forward(to string, signal realtimeSignal) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()

	clients := h.clients[to]
	if len(clients) == 0 {
		log.Printf("实时信令未投递：to=%s, type=%s, reason=用户不在线", to, signal.Type)
		return false
	}
	for client := range clients {
		select {
		case client.send <- signal:
		default:
			log.Printf("实时信令未投递：to=%s, type=%s, reason=发送队列已满", to, signal.Type)
		}
	}
	return true
}

func (h *realtimeHub) notifyChatPending(
	recipientUserID string,
	recipientDeviceID string,
	senderUserID string,
) {
	h.forward(recipientUserID, realtimeSignal{
		Type: "chat-pending",
		From: senderUserID,
		Payload: map[string]any{
			"recipientDeviceId": recipientDeviceID,
		},
	})
}

func (h *realtimeHub) forwardToDevice(userID, deviceID string, signal realtimeSignal) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()

	clients := h.clients[userID]
	if len(clients) == 0 {
		return false
	}

	delivered := false
	for client := range clients {
		if client.deviceID == "" || client.deviceID != deviceID {
			continue
		}
		delivered = true
		select {
		case client.send <- signal:
		default:
			log.Printf("实时信令未投递：to=%s, device=%s, type=%s, reason=发送队列已满", userID, deviceID, signal.Type)
		}
	}
	return delivered
}

func (h *Handler) friendIDs(userID string) []string {
	var friendships []model.Friendship
	if err := h.db.Where("user_id = ?", userID).Find(&friendships).Error; err != nil {
		return []string{}
	}

	friendIDs := make([]string, 0, len(friendships))
	for _, friendship := range friendships {
		friendIDs = append(friendIDs, friendship.FriendID)
	}
	return friendIDs
}

func (h *Handler) realtimePeerIDs(userID string) []string {
	ids := h.friendIDs(userID)

	var memberships []model.GroupMembership
	if err := h.db.Where("user_id = ?", userID).Find(&memberships).Error; err != nil {
		return normalizeUniqueIDs(ids)
	}
	if len(memberships) == 0 {
		return normalizeUniqueIDs(ids)
	}

	groupIDs := make([]string, 0, len(memberships))
	for _, membership := range memberships {
		groupIDs = append(groupIDs, membership.GroupID)
	}

	var peers []model.GroupMembership
	if err := h.db.
		Where("group_id IN ? AND user_id <> ?", normalizeUniqueIDs(groupIDs), userID).
		Find(&peers).Error; err != nil {
		return normalizeUniqueIDs(ids)
	}
	for _, peer := range peers {
		ids = append(ids, peer.UserID)
	}
	return normalizeUniqueIDs(ids)
}

func (h *Handler) canExchangeRealtime(userID, peerID string) bool {
	if userID == peerID {
		return false
	}
	if h.areFriends(userID, peerID) {
		return true
	}

	var memberships []model.GroupMembership
	if err := h.db.Where("user_id = ?", userID).Find(&memberships).Error; err != nil {
		return false
	}
	if len(memberships) == 0 {
		return false
	}

	groupIDs := make([]string, 0, len(memberships))
	for _, membership := range memberships {
		groupIDs = append(groupIDs, membership.GroupID)
	}
	var count int64
	if err := h.db.Model(&model.GroupMembership{}).
		Where("user_id = ? AND group_id IN ?", peerID, normalizeUniqueIDs(groupIDs)).
		Count(&count).Error; err != nil {
		return false
	}
	return count > 0
}

func (c *realtimeClient) readLoop(handler *Handler) {
	c.conn.SetReadLimit(1 << 20)
	_ = c.conn.SetReadDeadline(time.Now().Add(realtimePongWait))
	c.conn.SetPingHandler(func(appData string) error {
		_ = c.conn.SetReadDeadline(time.Now().Add(realtimePongWait))
		handler.touchChatDeviceActivity(c.userID, c.deviceID)
		return c.writeControl(websocket.PongMessage, []byte(appData))
	})
	c.conn.SetPongHandler(func(appData string) error {
		_ = c.conn.SetReadDeadline(time.Now().Add(realtimePongWait))
		handler.touchChatDeviceActivity(c.userID, c.deviceID)
		return nil
	})

	for {
		var signal realtimeSignal
		if err := c.conn.ReadJSON(&signal); err != nil {
			log.Printf("实时信令读取失败：userID=%s, err=%v", c.userID, err)
			return
		}
		if signal.To == "" || signal.To == c.userID {
			continue
		}
		if !handler.canExchangeRealtime(c.userID, signal.To) {
			continue
		}

		signal.From = c.userID
		if signal.Payload == nil {
			signal.Payload = map[string]any{}
		}
		handler.touchChatDeviceActivity(c.userID, c.deviceID)
		handler.realtimeHub.forward(signal.To, signal)
	}
}

func (c *realtimeClient) writeLoop() {
	ticker := time.NewTicker(realtimePingEvery)
	defer ticker.Stop()

	for {
		select {
		case signal, ok := <-c.send:
			if !ok {
				return
			}
			if err := c.writeJSON(signal); err != nil {
				log.Printf(
					"实时信令写入失败：userID=%s, type=%s, err=%v",
					c.userID,
					signal.Type,
					err,
				)
				return
			}
		case <-ticker.C:
			if err := c.writeControl(websocket.PingMessage, nil); err != nil {
				log.Printf("实时信令心跳发送失败：userID=%s, err=%v", c.userID, err)
				return
			}
		}
	}
}

func (c *realtimeClient) writeJSON(signal realtimeSignal) error {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()

	_ = c.conn.SetWriteDeadline(time.Now().Add(realtimeWriteWait))
	return c.conn.WriteJSON(signal)
}

func (c *realtimeClient) writeControl(messageType int, data []byte) error {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()

	return c.conn.WriteControl(
		messageType,
		data,
		time.Now().Add(realtimeWriteWait),
	)
}

func (h *Handler) touchChatDeviceActivity(userID, deviceID string) {
	if strings.TrimSpace(userID) == "" || strings.TrimSpace(deviceID) == "" {
		return
	}
	_ = h.db.Model(&model.ChatDevice{}).
		Where("id = ? AND user_id = ?", deviceID, userID).
		Update("last_seen_at", time.Now()).
		Error
}

func (h *Handler) latestChatDeviceSeenAt(userID string) string {
	if strings.TrimSpace(userID) == "" {
		return ""
	}

	var device model.ChatDevice
	if err := h.db.
		Where("user_id = ?", userID).
		Order("last_seen_at desc").
		First(&device).Error; err != nil {
		return ""
	}
	if device.LastSeenAt.IsZero() {
		return ""
	}
	return device.LastSeenAt.Format(time.RFC3339)
}
