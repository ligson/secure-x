package httpapi

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/ligson/secure-x/securex-be/internal/auth"
	"github.com/ligson/secure-x/securex-be/internal/middleware"
	"github.com/ligson/secure-x/securex-be/internal/storage"
	"gorm.io/gorm"
)

type Handler struct {
	db        *gorm.DB
	tokens    *auth.TokenManager
	fileStore *storage.FileStore
}

func NewRouter(db *gorm.DB, tokens *auth.TokenManager, fileStore *storage.FileStore) *gin.Engine {
	gin.SetMode(gin.ReleaseMode)

	handler := &Handler{
		db:        db,
		tokens:    tokens,
		fileStore: fileStore,
	}

	router := gin.Default()
	router.GET("/healthz", func(c *gin.Context) {
		RespondSuccess(c, http.StatusOK, "ok", gin.H{"status": "ok"})
	})

	v1 := router.Group("/api/v1")
	{
		authGroup := v1.Group("/auth")
		authGroup.POST("/register", handler.register)
		authGroup.POST("/login", handler.login)
		authGroup.GET("/me", middleware.RequireAuth(tokens), handler.me)
		authGroup.PUT("/password", middleware.RequireAuth(tokens), handler.changePassword)
		authGroup.PUT("/unlock-password", middleware.RequireAuth(tokens), handler.changeUnlockPassword)

		protected := v1.Group("/")
		protected.Use(middleware.RequireAuth(tokens))
		protected.GET("/sync/export", handler.exportVault)

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
		protected.GET("/files/:id/download", handler.downloadFile)
		protected.DELETE("/files/:id", handler.deleteFile)

		protected.POST("/file-uploads", handler.startFileUpload)
		protected.GET("/file-uploads/:id", handler.getFileUpload)
		protected.PUT("/file-uploads/:id/chunks/:index", handler.uploadFileChunk)
		protected.POST("/file-uploads/:id/complete", handler.completeFileUpload)
	}

	return router
}
