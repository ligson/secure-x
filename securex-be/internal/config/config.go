package config

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/goccy/go-yaml"
)

type Config struct {
	Server   ServerConfig   `yaml:"server"`
	Database DatabaseConfig `yaml:"database"`
	Storage  StorageConfig  `yaml:"storage"`
	Logging  LoggingConfig  `yaml:"logging"`
	Auth     AuthConfig     `yaml:"auth"`
}

type ServerConfig struct {
	Addr string `yaml:"addr"`
}

type DatabaseConfig struct {
	DSN string `yaml:"dsn"`
}

type StorageConfig struct {
	FileDir string `yaml:"fileDir"`
}

type LoggingConfig struct {
	Dir        string `yaml:"dir"`
	AppFile    string `yaml:"appFile"`
	AccessFile string `yaml:"accessFile"`
}

type AuthConfig struct {
	JWTSecret string `yaml:"jwtSecret"`
}

func Default() Config {
	return Config{
		Server: ServerConfig{
			Addr: ":8080",
		},
		Database: DatabaseConfig{
			DSN: "data/securex.db",
		},
		Storage: StorageConfig{
			FileDir: "data/files",
		},
		Logging: LoggingConfig{
			Dir:        "logs",
			AppFile:    "secure-x.log",
			AccessFile: "access.log",
		},
		Auth: AuthConfig{
			JWTSecret: "securex-dev-secret",
		},
	}
}

func Load(path string) (Config, error) {
	cfg := Default()
	if path == "" {
		return cfg, nil
	}

	content, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return Config{}, fmt.Errorf("config file not found: %s", path)
		}
		return Config{}, fmt.Errorf("read config file: %w", err)
	}
	if err := yaml.Unmarshal(content, &cfg); err != nil {
		return Config{}, fmt.Errorf("parse config file: %w", err)
	}
	cfg.applyDefaults()
	cfg.resolveRelativePaths(filepath.Dir(path))
	return cfg, nil
}

func (c *Config) applyDefaults() {
	defaults := Default()
	if c.Server.Addr == "" {
		c.Server.Addr = defaults.Server.Addr
	}
	if c.Database.DSN == "" {
		c.Database.DSN = defaults.Database.DSN
	}
	if c.Storage.FileDir == "" {
		c.Storage.FileDir = defaults.Storage.FileDir
	}
	if c.Logging.Dir == "" {
		c.Logging.Dir = defaults.Logging.Dir
	}
	if c.Logging.AppFile == "" {
		c.Logging.AppFile = defaults.Logging.AppFile
	}
	if c.Logging.AccessFile == "" {
		c.Logging.AccessFile = defaults.Logging.AccessFile
	}
	if c.Auth.JWTSecret == "" {
		c.Auth.JWTSecret = defaults.Auth.JWTSecret
	}
}

func (c *Config) resolveRelativePaths(baseDir string) {
	if baseDir == "" || baseDir == "." {
		return
	}
	if c.Database.DSN != "" && !filepath.IsAbs(c.Database.DSN) {
		c.Database.DSN = filepath.Join(baseDir, c.Database.DSN)
	}
	if c.Storage.FileDir != "" && !filepath.IsAbs(c.Storage.FileDir) {
		c.Storage.FileDir = filepath.Join(baseDir, c.Storage.FileDir)
	}
	if c.Logging.Dir != "" && !filepath.IsAbs(c.Logging.Dir) {
		c.Logging.Dir = filepath.Join(baseDir, c.Logging.Dir)
	}
}
