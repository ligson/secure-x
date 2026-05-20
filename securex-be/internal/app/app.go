package app

import (
	"github.com/gin-gonic/gin"
	"github.com/ligson/secure-x/securex-be/internal/auth"
	"github.com/ligson/secure-x/securex-be/internal/config"
	"github.com/ligson/secure-x/securex-be/internal/httpapi"
	"github.com/ligson/secure-x/securex-be/internal/repository"
	"github.com/ligson/secure-x/securex-be/internal/storage"
)

type Server struct {
	config config.Config
	router *gin.Engine
}

func NewServer() (*Server, error) {
	cfg := config.Load()

	db, err := repository.Open(cfg.DatabaseDSN)
	if err != nil {
		return nil, err
	}

	fileStore, err := storage.NewFileStore(cfg.FileDir)
	if err != nil {
		return nil, err
	}

	tokens := auth.NewTokenManager(cfg.JWTSecret)
	router := httpapi.NewRouter(db, tokens, fileStore)

	return &Server{
		config: cfg,
		router: router,
	}, nil
}

func (s *Server) Run() error {
	return s.router.Run(s.config.ServerAddr)
}
