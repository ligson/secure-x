package httpapi

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/ligson/secure-x/securex-be/internal/auth"
	"github.com/ligson/secure-x/securex-be/internal/config"
	"github.com/ligson/secure-x/securex-be/internal/middleware"
	"github.com/ligson/secure-x/securex-be/internal/storage"
	"gorm.io/gorm"
)

type Handler struct {
	db          *gorm.DB
	tokens      *auth.TokenManager
	fileStore   *storage.FileStore
	realtimeHub *realtimeHub
	server      config.ServerConfig
	realtime    config.RealtimeConfig
}

func NewRouter(
	db *gorm.DB,
	tokens *auth.TokenManager,
	fileStore *storage.FileStore,
	server config.ServerConfig,
	realtime config.RealtimeConfig,
) *gin.Engine {
	gin.SetMode(gin.ReleaseMode)

	handler := &Handler{
		db:        db,
		tokens:    tokens,
		fileStore: fileStore,
		server:    server,
		realtime:  realtime,
	}
	handler.realtimeHub = newRealtimeHub()

	router := gin.Default()
	router.GET("/healthz", func(c *gin.Context) {
		RespondSuccess(c, http.StatusOK, "ok", gin.H{"status": "ok"})
	})

	v1 := router.Group("/api/v1")
	{
		v1.GET("/avatars/:userID/:filename", handler.serveAvatar)

		authGroup := v1.Group("/auth")
		authGroup.POST("/register", handler.register)
		authGroup.POST("/login", handler.login)
		authGroup.GET("/me", middleware.RequireAuth(tokens), handler.me)
		authGroup.PUT("/profile", middleware.RequireAuth(tokens), handler.updateProfile)
		authGroup.POST("/profile/avatar", middleware.RequireAuth(tokens), handler.uploadProfileAvatar)
		authGroup.PUT("/password", middleware.RequireAuth(tokens), handler.changePassword)
		authGroup.PUT("/unlock-password", middleware.RequireAuth(tokens), handler.changeUnlockPassword)

		protected := v1.Group("/")
		protected.Use(middleware.RequireAuth(tokens))
		protected.GET("/sync/export", handler.exportVault)
		protected.GET("/realtime/config", handler.realtimeConfig)
		protected.GET("/realtime/presence", handler.realtimePresence)
		protected.GET("/realtime/ws", handler.realtimeWebSocket)

		protected.GET("/friends", handler.listFriends)
		protected.DELETE("/friends/:id", handler.deleteFriend)
		protected.PUT("/friends/:id/alias", handler.upsertFriendAlias)
		protected.DELETE("/friends/:id/alias", handler.deleteFriendAlias)
		protected.GET("/friend-requests", handler.listFriendRequests)
		protected.POST("/friend-requests", handler.createFriendRequest)
		protected.PUT("/friend-requests/:id/accept", handler.acceptFriendRequest)
		protected.PUT("/friend-requests/:id/reject", handler.rejectFriendRequest)
		protected.GET("/groups", handler.listGroups)
		protected.POST("/groups", handler.createGroup)
		protected.PUT("/groups/:id", handler.updateGroup)
		protected.PUT("/groups/:id/snapshot", handler.upsertGroupSnapshot)
		protected.POST("/groups/:id/dissolve", handler.dissolveGroup)
		protected.POST("/groups/:id/leave", handler.leaveGroup)
		protected.GET("/chat/archive/manifest", handler.getChatArchiveManifest)
		protected.GET("/chat/archive/conversations", handler.listChatArchiveConversations)
		protected.PUT("/chat/archive/conversations", handler.upsertChatArchiveConversations)
		protected.GET("/chat/archive", handler.getChatArchive)
		protected.PUT("/chat/archive", handler.upsertChatArchive)
		protected.GET("/chat/devices/current", handler.getCurrentChatDevice)
		protected.PUT("/chat/devices/current", handler.upsertCurrentChatDevice)
		protected.GET("/chat/devices", handler.listOwnChatDevices)
		protected.DELETE("/chat/devices/:id", handler.deleteOwnChatDevice)
		protected.GET("/chat/device-recovery", handler.getChatDeviceRecovery)
		protected.PUT("/chat/device-recovery", handler.upsertChatDeviceRecovery)
		protected.GET("/chat/users/:id/devices", handler.listUserChatDevices)
		protected.POST("/chat/attachments", handler.uploadChatAttachment)
		protected.GET("/chat/attachments/:id/download", handler.downloadChatAttachment)
		protected.POST("/chat/messages", handler.dispatchChatMessages)
		protected.GET("/chat/messages/pending", handler.listPendingChatMessages)
		protected.POST("/chat/messages/ack", handler.ackChatMessages)
		protected.POST("/calls/livekit-token", handler.createLiveKitCallToken)
		protected.POST("/calls/events", handler.recordCallEvent)

		protected.GET("/folders", handler.listFolders)
		protected.POST("/folders", handler.createFolder)
		protected.PUT("/folders/:id", handler.updateFolder)
		protected.DELETE("/folders/:id", handler.deleteFolder)

		protected.GET("/file-folders", handler.listFileFolders)
		protected.POST("/file-folders", handler.createFileFolder)
		protected.PUT("/file-folders/:id", handler.updateFileFolder)
		protected.DELETE("/file-folders/:id", handler.deleteFileFolder)

		protected.GET("/items", handler.listItems)
		protected.POST("/items", handler.createItem)
		protected.PUT("/items/:id", handler.updateItem)
		protected.DELETE("/items/:id", handler.deleteItem)

		protected.GET("/files", handler.listFiles)
		protected.GET("/files/:id", handler.getFileMetadata)
		protected.POST("/files", handler.uploadFile)
		protected.PUT("/files/:id", handler.updateFileMetadata)
		protected.POST("/files/:id/share", handler.shareFile)
		protected.GET("/files/:id/download", handler.downloadFile)
		protected.DELETE("/files/:id", handler.deleteFile)

		protected.POST("/file-uploads", handler.startFileUpload)
		protected.GET("/file-uploads/:id", handler.getFileUpload)
		protected.PUT("/file-uploads/:id/chunks/:index", handler.uploadFileChunk)
		protected.POST("/file-uploads/:id/complete", handler.completeFileUpload)
	}

	return router
}
