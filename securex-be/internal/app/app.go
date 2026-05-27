package app

import (
	"log"

	"github.com/gin-gonic/gin"
	"github.com/ligson/secure-x/securex-be/internal/auth"
	"github.com/ligson/secure-x/securex-be/internal/config"
	"github.com/ligson/secure-x/securex-be/internal/httpapi"
	"github.com/ligson/secure-x/securex-be/internal/logging"
	"github.com/ligson/secure-x/securex-be/internal/repository"
	"github.com/ligson/secure-x/securex-be/internal/storage"
)

type Server struct {
	config config.Config
	router *gin.Engine
	logs   *logging.Handles
}

func NewServer(configPath string) (*Server, error) {
	cfg, err := config.Load(configPath)
	if err != nil {
		return nil, err
	}

	logs, err := logging.Setup(cfg.Logging)
	if err != nil {
		return nil, err
	}
	log.Printf("Secure X 后端正在初始化，监听地址：%s，日志目录：%s", cfg.Server.Addr, cfg.Logging.Dir)

	db, err := repository.Open(cfg.Database.DSN)
	if err != nil {
		_ = logs.Close()
		return nil, err
	}
	log.Printf("数据库已连接：%s", cfg.Database.DSN)

	fileStore, err := storage.NewFileStore(cfg.Storage.FileDir)
	if err != nil {
		_ = logs.Close()
		return nil, err
	}
	log.Printf("密文文件目录已准备：%s", cfg.Storage.FileDir)

	tokens := auth.NewTokenManager(cfg.Auth.JWTSecret)
	router := httpapi.NewRouter(db, tokens, fileStore, cfg.Server)

	return &Server{
		config: cfg,
		router: router,
		logs:   logs,
	}, nil
}

func (s *Server) Run() error {
	defer func() {
		if err := s.logs.Close(); err != nil {
			log.Printf("关闭日志文件失败：%v", err)
		}
	}()
	log.Printf("Secure X 后端启动完成：http://%s", s.config.Server.Addr)
	return s.router.Run(s.config.Server.Addr)
}
