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
	groupStatusActive    = "active"
	groupStatusDissolved = "dissolved"
)

func (h *Handler) listGroups(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	groups, err := h.groupResponsesForUser(userID)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "加载群聊列表失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "群聊列表已加载", gin.H{"groups": groups})
}

func (h *Handler) createGroup(c *gin.Context) {
	var req groupUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	userID := middleware.CurrentUserID(c)
	groupID := strings.TrimSpace(req.GroupID)
	if groupID == "" {
		groupID = "group-" + uuid.NewString()
	}
	memberIDs := normalizeGroupMemberIDs(userID, req.MemberIDs)
	if len(memberIDs) < 2 {
		RespondFailure(c, http.StatusBadRequest, "群聊至少需要包含一位其他成员")
		return
	}
	if err := h.ensureUsersExist(memberIDs); err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			RespondFailure(c, http.StatusBadRequest, "群成员不存在")
			return
		}
		RespondFailure(c, http.StatusInternalServerError, "校验群成员失败")
		return
	}
	if ok, err := h.ensureInvitableMembers(userID, uniqueWithout(memberIDs, userID)); err != nil {
		RespondFailure(c, http.StatusInternalServerError, "校验群成员关系失败")
		return
	} else if !ok {
		RespondFailure(c, http.StatusBadRequest, "只能邀请自己的好友加入群聊")
		return
	}

	room := model.GroupRoom{
		ID:            groupID,
		CreatorUserID: userID,
		AdminUserID:   userID,
		Status:        groupStatusActive,
		Version:       normalizeVersion(req.Version),
	}

	err := h.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&room).Error; err != nil {
			return err
		}
		if err := h.replaceGroupMemberships(tx, room.ID, nil, memberIDs, userID); err != nil {
			return err
		}
		return h.upsertGroupSnapshotRecord(tx, room.ID, userID, req.Payload, req.Version)
	})
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "创建群聊失败")
		return
	}

	response, err := h.groupResponseForUser(room.ID, userID)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "加载群聊详情失败")
		return
	}
	RespondSuccess(c, http.StatusCreated, "群聊已创建", gin.H{"group": response})
}

func (h *Handler) updateGroup(c *gin.Context) {
	var req groupUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	userID := middleware.CurrentUserID(c)
	room, memberIDs, err := h.groupRoomWithMemberIDs(c.Param("id"), userID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			RespondFailure(c, http.StatusNotFound, "群聊不存在")
			return
		}
		RespondFailure(c, http.StatusInternalServerError, "加载群聊失败")
		return
	}
	if h.groupRoomDissolved(room) {
		RespondFailure(c, http.StatusConflict, "群聊已解散，无法继续修改成员")
		return
	}

	nextMemberIDs := normalizeGroupMemberIDs(userID, req.MemberIDs)
	if len(nextMemberIDs) < 2 {
		RespondFailure(c, http.StatusBadRequest, "群聊至少需要包含一位其他成员")
		return
	}
	if err := h.ensureUsersExist(nextMemberIDs); err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			RespondFailure(c, http.StatusBadRequest, "群成员不存在")
			return
		}
		RespondFailure(c, http.StatusInternalServerError, "校验群成员失败")
		return
	}

	addedIDs, removedIDs := diffIDs(memberIDs, nextMemberIDs)
	isAdmin := room.AdminUserID == userID
	if !isAdmin && len(removedIDs) > 0 {
		RespondFailure(c, http.StatusForbidden, "只有群管理才能移除群成员")
		return
	}
	if ok, err := h.ensureInvitableMembers(userID, addedIDs); err != nil {
		RespondFailure(c, http.StatusInternalServerError, "校验群成员关系失败")
		return
	} else if !ok {
		RespondFailure(c, http.StatusBadRequest, "只能邀请自己的好友加入群聊")
		return
	}

	nextAdminUserID := room.AdminUserID
	if strings.TrimSpace(req.AdminUserID) != "" {
		if !isAdmin {
			RespondFailure(c, http.StatusForbidden, "只有群管理才能修改群管理")
			return
		}
		nextAdminUserID = strings.TrimSpace(req.AdminUserID)
	}
	if !containsID(nextMemberIDs, nextAdminUserID) {
		RespondFailure(c, http.StatusBadRequest, "群管理必须是当前群成员")
		return
	}
	if containsID(removedIDs, room.AdminUserID) && nextAdminUserID == room.AdminUserID {
		RespondFailure(c, http.StatusBadRequest, "移除当前群管理前请先指定新的群管理")
		return
	}

	err = h.db.Transaction(func(tx *gorm.DB) error {
		room.AdminUserID = nextAdminUserID
		room.Version = normalizeVersion(req.Version)
		if err := tx.Save(&room).Error; err != nil {
			return err
		}
		if err := h.replaceGroupMemberships(tx, room.ID, memberIDs, nextMemberIDs, userID); err != nil {
			return err
		}
		return h.upsertGroupSnapshotRecord(tx, room.ID, userID, req.Payload, req.Version)
	})
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "更新群聊失败")
		return
	}

	response, err := h.groupResponseForUser(room.ID, userID)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "加载群聊详情失败")
		return
	}
	RespondSuccess(c, http.StatusOK, "群聊已更新", gin.H{"group": response})
}

func (h *Handler) upsertGroupSnapshot(c *gin.Context) {
	var req groupSnapshotUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	userID := middleware.CurrentUserID(c)
	room, _, err := h.groupRoomWithMemberIDs(c.Param("id"), userID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			RespondFailure(c, http.StatusNotFound, "群聊不存在")
			return
		}
		RespondFailure(c, http.StatusInternalServerError, "加载群聊失败")
		return
	}
	if h.groupRoomDissolved(room) {
		RespondFailure(c, http.StatusConflict, "群聊已解散，无法继续保存群快照")
		return
	}

	if err := h.upsertGroupSnapshotRecord(h.db, room.ID, userID, req.Payload, req.Version); err != nil {
		RespondFailure(c, http.StatusInternalServerError, "保存群聊快照失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "群聊快照已保存", gin.H{})
}

func (h *Handler) dissolveGroup(c *gin.Context) {
	var req groupDissolveRequest
	_ = c.ShouldBindJSON(&req)

	userID := middleware.CurrentUserID(c)
	room, memberIDs, err := h.groupRoomWithMemberIDs(c.Param("id"), userID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			RespondFailure(c, http.StatusNotFound, "群聊不存在")
			return
		}
		RespondFailure(c, http.StatusInternalServerError, "加载群聊失败")
		return
	}
	if room.AdminUserID != userID {
		RespondFailure(c, http.StatusForbidden, "只有群管理可以解散群聊")
		return
	}
	if h.groupRoomDissolved(room) {
		RespondSuccess(c, http.StatusOK, "群聊已处于解散状态", gin.H{
			"groupId":   room.ID,
			"memberIds": uniqueWithout(memberIDs, userID),
		})
		return
	}

	now := time.Now()
	dissolvedByUserID := userID
	remainingMemberIDs := uniqueWithout(memberIDs, userID)
	err = h.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("group_id = ? AND user_id = ?", room.ID, userID).Delete(&model.GroupMembership{}).Error; err != nil {
			return err
		}
		if err := tx.Where("group_id = ? AND user_id = ?", room.ID, userID).Delete(&model.GroupSnapshot{}).Error; err != nil {
			return err
		}
		if len(remainingMemberIDs) == 0 {
			if err := tx.Where("group_id = ?", room.ID).Delete(&model.GroupMembership{}).Error; err != nil {
				return err
			}
			if err := tx.Where("group_id = ?", room.ID).Delete(&model.GroupSnapshot{}).Error; err != nil {
				return err
			}
			return tx.Delete(&room).Error
		}
		room.Status = groupStatusDissolved
		room.DissolvedAt = &now
		room.DissolvedByUserID = &dissolvedByUserID
		room.Version++
		return tx.Save(&room).Error
	})
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "解散群聊失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "群聊已解散", gin.H{
		"groupId":   room.ID,
		"memberIds": remainingMemberIDs,
	})
}

func (h *Handler) leaveGroup(c *gin.Context) {
	var req groupLeaveRequest
	_ = c.ShouldBindJSON(&req)

	userID := middleware.CurrentUserID(c)
	room, memberIDs, err := h.groupRoomWithMemberIDs(c.Param("id"), userID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			RespondFailure(c, http.StatusNotFound, "群聊不存在")
			return
		}
		RespondFailure(c, http.StatusInternalServerError, "加载群聊失败")
		return
	}

	remaining := make([]string, 0, len(memberIDs))
	for _, memberID := range memberIDs {
		if memberID != userID {
			remaining = append(remaining, memberID)
		}
	}

	nextAdminUserID := room.AdminUserID
	if !h.groupRoomDissolved(room) && room.AdminUserID == userID {
		nextAdminUserID = strings.TrimSpace(req.NextAdminUserID)
		if nextAdminUserID == "" || !containsID(remaining, nextAdminUserID) {
			nextAdminUserID = h.nextGroupAdminID(room.ID, remaining)
		}
	}

	err = h.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("group_id = ? AND user_id = ?", room.ID, userID).Delete(&model.GroupMembership{}).Error; err != nil {
			return err
		}
		if err := tx.Where("group_id = ? AND user_id = ?", room.ID, userID).Delete(&model.GroupSnapshot{}).Error; err != nil {
			return err
		}
		if len(remaining) == 0 {
			if err := tx.Where("group_id = ?", room.ID).Delete(&model.GroupMembership{}).Error; err != nil {
				return err
			}
			if err := tx.Where("group_id = ?", room.ID).Delete(&model.GroupSnapshot{}).Error; err != nil {
				return err
			}
			return tx.Delete(&room).Error
		}
		if h.groupRoomDissolved(room) {
			return nil
		}

		if nextAdminUserID == "" || !containsID(remaining, nextAdminUserID) {
			nextAdminUserID = remaining[0]
		}
		room.AdminUserID = nextAdminUserID
		room.Version = room.Version + 1
		return tx.Save(&room).Error
	})
	if err != nil {
		if h.groupRoomDissolved(room) {
			RespondFailure(c, http.StatusInternalServerError, "删除已解散群聊会话失败")
			return
		}
		RespondFailure(c, http.StatusInternalServerError, "退出群聊失败")
		return
	}

	successMessage := "已退出群聊"
	if h.groupRoomDissolved(room) {
		successMessage = "已删除已解散群聊会话"
	}
	RespondSuccess(c, http.StatusOK, successMessage, gin.H{
		"groupId":         room.ID,
		"memberIds":       remaining,
		"nextAdminUserId": nextAdminUserID,
		"isDissolved":     h.groupRoomDissolved(room),
	})
}

func (h *Handler) groupResponsesForUser(userID string) ([]gin.H, error) {
	var memberships []model.GroupMembership
	if err := h.db.Where("user_id = ?", userID).Order("updated_at desc").Find(&memberships).Error; err != nil {
		return nil, err
	}
	if len(memberships) == 0 {
		return []gin.H{}, nil
	}

	groupIDs := make([]string, 0, len(memberships))
	for _, membership := range memberships {
		groupIDs = append(groupIDs, membership.GroupID)
	}

	responses := make([]gin.H, 0, len(groupIDs))
	for _, groupID := range normalizeUniqueIDs(groupIDs) {
		response, err := h.groupResponseForUser(groupID, userID)
		if err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				continue
			}
			return nil, err
		}
		responses = append(responses, response)
	}
	return responses, nil
}

func (h *Handler) groupResponseForUser(groupID, userID string) (gin.H, error) {
	room, memberIDs, err := h.groupRoomWithMemberIDs(groupID, userID)
	if err != nil {
		return nil, err
	}

	users := h.publicUsersByID(memberIDs)
	var snapshot model.GroupSnapshot
	snapshotErr := h.db.Where("group_id = ? AND user_id = ?", groupID, userID).First(&snapshot).Error
	if snapshotErr != nil && !errors.Is(snapshotErr, gorm.ErrRecordNotFound) {
		return nil, snapshotErr
	}

	response := gin.H{
		"id":                room.ID,
		"creatorUserId":     room.CreatorUserID,
		"adminUserId":       room.AdminUserID,
		"status":            h.normalizedGroupStatus(room.Status),
		"isDissolved":       h.groupRoomDissolved(room),
		"dissolvedAt":       room.DissolvedAt,
		"dissolvedByUserId": room.DissolvedByUserID,
		"version":           room.Version,
		"snapshotPayload":   "",
		"snapshotVersion":   0,
		"members":           users,
	}
	if snapshotErr == nil {
		response["snapshotPayload"] = snapshot.Payload
		response["snapshotVersion"] = snapshot.Version
	}
	return response, nil
}

func (h *Handler) groupRoomWithMemberIDs(groupID, userID string) (model.GroupRoom, []string, error) {
	var room model.GroupRoom
	if err := h.db.Where("id = ?", groupID).First(&room).Error; err != nil {
		return room, nil, err
	}

	var memberships []model.GroupMembership
	if err := h.db.Where("group_id = ?", groupID).Order("created_at asc").Find(&memberships).Error; err != nil {
		return room, nil, err
	}
	memberIDs := make([]string, 0, len(memberships))
	for _, membership := range memberships {
		memberIDs = append(memberIDs, membership.UserID)
	}
	if !containsID(memberIDs, userID) {
		return room, nil, gorm.ErrRecordNotFound
	}
	return room, memberIDs, nil
}

func (h *Handler) replaceGroupMemberships(
	tx *gorm.DB,
	groupID string,
	current []string,
	next []string,
	addedByUserID string,
) error {
	addedIDs, removedIDs := diffIDs(current, next)
	for _, addedID := range addedIDs {
		record := model.GroupMembership{
			ID:            uuid.NewString(),
			GroupID:       groupID,
			UserID:        addedID,
			AddedByUserID: addedByUserID,
		}
		if err := tx.Create(&record).Error; err != nil {
			return err
		}
	}
	if len(removedIDs) == 0 {
		return nil
	}
	if err := tx.Where("group_id = ? AND user_id IN ?", groupID, removedIDs).Delete(&model.GroupMembership{}).Error; err != nil {
		return err
	}
	return tx.Where("group_id = ? AND user_id IN ?", groupID, removedIDs).Delete(&model.GroupSnapshot{}).Error
}

func (h *Handler) upsertGroupSnapshotRecord(
	tx *gorm.DB,
	groupID string,
	userID string,
	payload string,
	version int,
) error {
	var snapshot model.GroupSnapshot
	err := tx.Where("group_id = ? AND user_id = ?", groupID, userID).First(&snapshot).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		snapshot = model.GroupSnapshot{
			ID:      uuid.NewString(),
			GroupID: groupID,
			UserID:  userID,
			Payload: payload,
			Version: normalizeVersion(version),
		}
		return tx.Create(&snapshot).Error
	}
	if err != nil {
		return err
	}

	snapshot.Payload = payload
	snapshot.Version = normalizeVersion(version)
	return tx.Save(&snapshot).Error
}

func (h *Handler) ensureUsersExist(userIDs []string) error {
	normalized := normalizeUniqueIDs(userIDs)
	var count int64
	if err := h.db.Model(&model.User{}).Where("id IN ?", normalized).Count(&count).Error; err != nil {
		return err
	}
	if count != int64(len(normalized)) {
		return gorm.ErrRecordNotFound
	}
	return nil
}

func (h *Handler) ensureInvitableMembers(userID string, memberIDs []string) (bool, error) {
	for _, memberID := range normalizeUniqueIDs(memberIDs) {
		if memberID == userID {
			continue
		}
		if !h.areFriends(userID, memberID) {
			return false, nil
		}
	}
	return true, nil
}

func (h *Handler) nextGroupAdminID(groupID string, remaining []string) string {
	if len(remaining) == 0 {
		return ""
	}

	var memberships []model.GroupMembership
	if err := h.db.
		Where("group_id = ? AND user_id IN ?", groupID, remaining).
		Order("created_at asc").
		Find(&memberships).Error; err != nil {
		return remaining[0]
	}
	for _, membership := range memberships {
		if containsID(remaining, membership.UserID) {
			return membership.UserID
		}
	}
	return remaining[0]
}

func (h *Handler) normalizedGroupStatus(status string) string {
	if strings.EqualFold(strings.TrimSpace(status), groupStatusDissolved) {
		return groupStatusDissolved
	}
	return groupStatusActive
}

func (h *Handler) groupRoomDissolved(room model.GroupRoom) bool {
	return h.normalizedGroupStatus(room.Status) == groupStatusDissolved
}
