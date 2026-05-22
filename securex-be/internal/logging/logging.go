package logging

import (
	"io"
	"log"
	"os"
	"path/filepath"

	"github.com/gin-gonic/gin"
	"github.com/ligson/secure-x/securex-be/internal/config"
)

type Handles struct {
	appFile    *os.File
	accessFile *os.File
}

func Setup(cfg config.LoggingConfig) (*Handles, error) {
	if err := os.MkdirAll(cfg.Dir, 0o755); err != nil {
		return nil, err
	}

	appFile, err := openLogFile(filepath.Join(cfg.Dir, cfg.AppFile))
	if err != nil {
		return nil, err
	}

	accessFile, err := openLogFile(filepath.Join(cfg.Dir, cfg.AccessFile))
	if err != nil {
		_ = appFile.Close()
		return nil, err
	}

	// 应用日志同时输出到控制台和文件，便于 systemd/journalctl 与文件排障都能看到。
	appWriter := io.MultiWriter(os.Stdout, appFile)
	accessWriter := io.MultiWriter(os.Stdout, accessFile)
	log.SetOutput(appWriter)
	log.SetFlags(log.LstdFlags | log.Lmicroseconds | log.Lshortfile)

	// Gin 的访问日志和异常日志分别写入访问日志、应用日志。
	gin.DefaultWriter = accessWriter
	gin.DefaultErrorWriter = appWriter

	return &Handles{
		appFile:    appFile,
		accessFile: accessFile,
	}, nil
}

func (h *Handles) Close() error {
	var firstErr error
	if h == nil {
		return nil
	}
	if h.accessFile != nil {
		if err := h.accessFile.Close(); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	if h.appFile != nil {
		if err := h.appFile.Close(); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}

func openLogFile(path string) (*os.File, error) {
	return os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o640)
}
