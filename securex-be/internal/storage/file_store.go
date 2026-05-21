package storage

import (
	"io"
	"os"
	"path/filepath"
)

type FileStore struct {
	baseDir string
}

func NewFileStore(baseDir string) (*FileStore, error) {
	if err := os.MkdirAll(baseDir, 0o755); err != nil {
		return nil, err
	}

	return &FileStore{baseDir: baseDir}, nil
}

func (s *FileStore) Save(relativePath string, source io.Reader) (int64, string, error) {
	fullPath := s.Resolve(relativePath)
	if err := os.MkdirAll(filepath.Dir(fullPath), 0o755); err != nil {
		return 0, "", err
	}

	file, err := os.Create(fullPath)
	if err != nil {
		return 0, "", err
	}
	defer file.Close()

	written, err := io.Copy(file, source)
	if err != nil {
		return 0, "", err
	}

	return written, fullPath, nil
}

func (s *FileStore) Resolve(relativePath string) string {
	return filepath.Join(s.baseDir, relativePath)
}

func (s *FileStore) Delete(fullPath string) error {
	if fullPath == "" {
		return nil
	}
	if err := os.Remove(fullPath); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}
