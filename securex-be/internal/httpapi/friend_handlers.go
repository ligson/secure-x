package httpapi

import (
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/ligson/secure-x/securex-be/internal/middleware"
	"github.com/ligson/secure-x/securex-be/internal/model"
	"gorm.io/gorm"
)

const (
	friendRequestPending  = "pending"
	friendRequestAccepted = "accepted"
	friendRequestRejected = "rejected"
)

func (h *Handler) listFriends(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var friendships []model.Friendship
	if err := h.db.Where("user_id = ?", userID).Order("updated_at desc").Find(&friendships).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "加载好友列表失败")
		return
	}

	friendIDs := make([]string, 0, len(friendships))
	for _, friendship := range friendships {
		friendIDs = append(friendIDs, friendship.FriendID)
	}

	var aliases []model.FriendAlias
	if err := h.db.Where("user_id = ?", userID).Order("updated_at desc").Find(&aliases).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "加载好友备注失败")
		return
	}

	aliasResponses := make([]gin.H, 0, len(aliases))
	for _, alias := range aliases {
		aliasResponses = append(aliasResponses, friendAliasResponse(alias))
	}

	RespondSuccess(c, http.StatusOK, "好友列表已加载", gin.H{
		"friends": h.publicUsersByID(friendIDs),
		"aliases": aliasResponses,
	})
}

func (h *Handler) listFriendRequests(c *gin.Context) {
	userID := middleware.CurrentUserID(c)

	var incoming []model.FriendRequest
	if err := h.db.
		Where("addressee_id = ? AND status = ?", userID, friendRequestPending).
		Order("created_at desc").
		Find(&incoming).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "加载好友申请失败")
		return
	}

	var outgoing []model.FriendRequest
	if err := h.db.
		Where("requester_id = ? AND status = ?", userID, friendRequestPending).
		Order("created_at desc").
		Find(&outgoing).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "加载好友申请失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "好友申请已加载", gin.H{
		"incoming": h.friendRequestResponses(incoming),
		"outgoing": h.friendRequestResponses(outgoing),
	})
}

func (h *Handler) createFriendRequest(c *gin.Context) {
	var req friendRequestCreateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	userID := middleware.CurrentUserID(c)
	identifier := strings.TrimSpace(strings.ToLower(req.Identifier))
	message := strings.TrimSpace(req.Message)
	if identifier == "" {
		RespondFailure(c, http.StatusBadRequest, "请输入好友用户名或邮箱")
		return
	}

	var target model.User
	err := h.db.
		Where("LOWER(username) = ? OR LOWER(email) = ?", identifier, identifier).
		First(&target).Error
	if err != nil {
		RespondFailure(c, http.StatusNotFound, "没有找到这个用户")
		return
	}
	if target.ID == userID {
		RespondFailure(c, http.StatusBadRequest, "不能添加自己为好友")
		return
	}

	if h.areFriends(userID, target.ID) {
		RespondFailure(c, http.StatusConflict, "你们已经是好友")
		return
	}

	var reverse model.FriendRequest
	err = h.db.
		Where("requester_id = ? AND addressee_id = ? AND status = ?", target.ID, userID, friendRequestPending).
		First(&reverse).Error
	if err == nil {
		if err := h.acceptFriendRequestRecord(&reverse); err != nil {
			RespondFailure(c, http.StatusInternalServerError, "同意好友申请失败")
			return
		}
		h.notifyFriendshipChanged(reverse.RequesterID, reverse.AddresseeID, friendRequestAccepted)
		RespondSuccess(c, http.StatusOK, "已同意对方的好友申请", gin.H{
			"request": h.friendRequestResponse(reverse),
		})
		return
	}
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		RespondFailure(c, http.StatusInternalServerError, "检查好友申请失败")
		return
	}

	var existing model.FriendRequest
	err = h.db.
		Where("requester_id = ? AND addressee_id = ? AND status = ?", userID, target.ID, friendRequestPending).
		First(&existing).Error
	if err == nil {
		RespondFailure(c, http.StatusConflict, "已经发送过好友申请，请等待对方处理")
		return
	}
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		RespondFailure(c, http.StatusInternalServerError, "检查好友申请失败")
		return
	}

	friendRequest := model.FriendRequest{
		ID:          uuid.NewString(),
		RequesterID: userID,
		AddresseeID: target.ID,
		Message:     message,
		Status:      friendRequestPending,
	}
	if err := h.db.Create(&friendRequest).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "发送好友申请失败")
		return
	}

	RespondSuccess(c, http.StatusCreated, "好友申请已发送", gin.H{
		"request": h.friendRequestResponse(friendRequest),
	})
}

func (h *Handler) acceptFriendRequest(c *gin.Context) {
	var request model.FriendRequest
	if err := h.db.
		Where("id = ? AND addressee_id = ? AND status = ?", c.Param("id"), middleware.CurrentUserID(c), friendRequestPending).
		First(&request).Error; err != nil {
		RespondFailure(c, http.StatusNotFound, "好友申请不存在")
		return
	}

	if err := h.acceptFriendRequestRecord(&request); err != nil {
		RespondFailure(c, http.StatusInternalServerError, "同意好友申请失败")
		return
	}
	h.notifyFriendshipChanged(request.RequesterID, request.AddresseeID, friendRequestAccepted)
	h.notifyCurrentPresenceBetweenUsers(request.RequesterID, request.AddresseeID)

	RespondSuccess(c, http.StatusOK, "已添加好友", gin.H{
		"request": h.friendRequestResponse(request),
	})
}

func (h *Handler) rejectFriendRequest(c *gin.Context) {
	var request model.FriendRequest
	if err := h.db.
		Where("id = ? AND addressee_id = ? AND status = ?", c.Param("id"), middleware.CurrentUserID(c), friendRequestPending).
		First(&request).Error; err != nil {
		RespondFailure(c, http.StatusNotFound, "好友申请不存在")
		return
	}

	request.Status = friendRequestRejected
	if err := h.db.Save(&request).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "拒绝好友申请失败")
		return
	}
	h.notifyFriendshipChanged(request.RequesterID, request.AddresseeID, friendRequestRejected)

	RespondSuccess(c, http.StatusOK, "已拒绝好友申请", gin.H{
		"request": h.friendRequestResponse(request),
	})
}

func (h *Handler) deleteFriend(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	friendID := c.Param("id")
	if !h.areFriends(userID, friendID) {
		RespondFailure(c, http.StatusNotFound, "好友不存在")
		return
	}

	if err := h.db.
		Where("(user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)", userID, friendID, friendID, userID).
		Delete(&model.Friendship{}).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "删除好友失败")
		return
	}
	if err := h.db.
		Where("(user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)", userID, friendID, friendID, userID).
		Delete(&model.FriendAlias{}).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "删除好友备注失败")
		return
	}
	h.notifyFriendshipChanged(userID, friendID, "deleted")

	RespondSuccess(c, http.StatusOK, "好友已删除", gin.H{})
}

func (h *Handler) upsertFriendAlias(c *gin.Context) {
	var req friendAliasUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	userID := middleware.CurrentUserID(c)
	friendID := strings.TrimSpace(c.Param("id"))
	if friendID == "" || !h.areFriends(userID, friendID) {
		RespondFailure(c, http.StatusNotFound, "好友不存在")
		return
	}

	alias := model.FriendAlias{
		ID:       uuid.NewString(),
		UserID:   userID,
		FriendID: friendID,
		Payload:  strings.TrimSpace(req.Payload),
		Version:  normalizeVersion(req.Version),
	}
	if alias.Payload == "" {
		RespondFailure(c, http.StatusBadRequest, "缺少加密负载内容")
		return
	}

	var existing model.FriendAlias
	err := h.db.Where("user_id = ? AND friend_id = ?", userID, friendID).First(&existing).Error
	if err == nil {
		existing.Payload = alias.Payload
		existing.Version = alias.Version
		if err := h.db.Save(&existing).Error; err != nil {
			RespondFailure(c, http.StatusInternalServerError, "保存好友备注失败")
			return
		}
		RespondSuccess(c, http.StatusOK, "好友备注已保存", gin.H{
			"alias": friendAliasResponse(existing),
		})
		return
	}
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		RespondFailure(c, http.StatusInternalServerError, "保存好友备注失败")
		return
	}

	if err := h.db.Create(&alias).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "保存好友备注失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "好友备注已保存", gin.H{
		"alias": friendAliasResponse(alias),
	})
}

func (h *Handler) deleteFriendAlias(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	friendID := strings.TrimSpace(c.Param("id"))
	if friendID == "" || !h.areFriends(userID, friendID) {
		RespondFailure(c, http.StatusNotFound, "好友不存在")
		return
	}

	if err := h.db.Where("user_id = ? AND friend_id = ?", userID, friendID).Delete(&model.FriendAlias{}).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "删除好友备注失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "好友备注已清除", gin.H{})
}

func (h *Handler) notifyFriendshipChanged(userID, friendID, status string) {
	signal := realtimeSignal{
		Type: "friendship-updated",
		Payload: map[string]any{
			"status":   status,
			"friendId": friendID,
		},
	}
	signal.From = friendID
	h.realtimeHub.forward(userID, signal)

	signal.From = userID
	signal.Payload = map[string]any{
		"status":   status,
		"friendId": userID,
	}
	h.realtimeHub.forward(friendID, signal)
}

func (h *Handler) notifyCurrentPresenceBetweenUsers(userID, friendID string) {
	h.realtimeHub.forward(userID, realtimeSignal{
		Type: "presence",
		From: friendID,
		Payload: map[string]any{
			"online": h.realtimeHub.isOnline(friendID),
		},
	})
	h.realtimeHub.forward(friendID, realtimeSignal{
		Type: "presence",
		From: userID,
		Payload: map[string]any{
			"online": h.realtimeHub.isOnline(userID),
		},
	})
}

func (h *Handler) acceptFriendRequestRecord(request *model.FriendRequest) error {
	return h.db.Transaction(func(tx *gorm.DB) error {
		request.Status = friendRequestAccepted
		if err := tx.Save(request).Error; err != nil {
			return err
		}

		pairs := []model.Friendship{
			{ID: uuid.NewString(), UserID: request.RequesterID, FriendID: request.AddresseeID},
			{ID: uuid.NewString(), UserID: request.AddresseeID, FriendID: request.RequesterID},
		}
		for _, pair := range pairs {
			if err := tx.Where("user_id = ? AND friend_id = ?", pair.UserID, pair.FriendID).
				FirstOrCreate(&pair).Error; err != nil {
				return err
			}
		}

		return nil
	})
}

func (h *Handler) areFriends(userID, friendID string) bool {
	var count int64
	if err := h.db.Model(&model.Friendship{}).
		Where("user_id = ? AND friend_id = ?", userID, friendID).
		Count(&count).Error; err != nil {
		return false
	}
	return count > 0
}

func (h *Handler) publicUsersByID(ids []string) []gin.H {
	if len(ids) == 0 {
		return []gin.H{}
	}

	var users []model.User
	if err := h.db.Where("id IN ?", ids).Order("username asc").Find(&users).Error; err != nil {
		return []gin.H{}
	}

	result := make([]gin.H, 0, len(users))
	for _, user := range users {
		result = append(result, publicUserResponse(user))
	}
	return result
}

func (h *Handler) friendRequestResponses(requests []model.FriendRequest) []gin.H {
	result := make([]gin.H, 0, len(requests))
	for _, request := range requests {
		result = append(result, h.friendRequestResponse(request))
	}
	return result
}

func (h *Handler) friendRequestResponse(request model.FriendRequest) gin.H {
	var requester model.User
	var addressee model.User
	_ = h.db.First(&requester, "id = ?", request.RequesterID).Error
	_ = h.db.First(&addressee, "id = ?", request.AddresseeID).Error

	return gin.H{
		"id":        request.ID,
		"requester": publicUserResponse(requester),
		"addressee": publicUserResponse(addressee),
		"message":   request.Message,
		"status":    request.Status,
		"createdAt": request.CreatedAt,
		"updatedAt": request.UpdatedAt,
	}
}

func publicUserResponse(user model.User) gin.H {
	return gin.H{
		"id":           user.ID,
		"username":     user.Username,
		"nickname":     user.Nickname,
		"avatarPreset": defaultAvatarPreset(user.AvatarPreset),
		"email":        user.Email,
	}
}
