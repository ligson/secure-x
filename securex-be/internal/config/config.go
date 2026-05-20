package config

import "os"

type Config struct {
	ServerAddr  string
	DatabaseDSN string
	FileDir     string
	JWTSecret   string
}

func Load() Config {
	return Config{
		ServerAddr:  getEnv("SECUREX_SERVER_ADDR", ":8080"),
		DatabaseDSN: getEnv("SECUREX_DATABASE_DSN", "data/securex.db"),
		FileDir:     getEnv("SECUREX_FILE_DIR", "data/files"),
		JWTSecret:   getEnv("SECUREX_JWT_SECRET", "securex-dev-secret"),
	}
}

func getEnv(key, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}

	return value
}
