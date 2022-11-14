// Copyright 2022 The TVL Contributors
// SPDX-License-Identifier: Apache-2.0

// Filesystem storage backend for Nixery.
package storage

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"path"

	"github.com/pkg/xattr"
	log "github.com/sirupsen/logrus"
)

type FSBackend struct {
	path string
}

func NewFSBackend() (*FSBackend, error) {
	p := os.Getenv("STORAGE_PATH")
	if p == "" {
		return nil, fmt.Errorf("STORAGE_PATH must be set for filesystem storage")
	}

	p = path.Clean(p)
	err := os.MkdirAll(p, 0755)
	if err != nil {
		return nil, fmt.Errorf("failed to create storage dir: %s", err)
	}

	return &FSBackend{p}, nil
}

func (b *FSBackend) Name() string {
	return fmt.Sprintf("Filesystem (%s)", b.path)
}

func (b *FSBackend) Persist(ctx context.Context, key, contentType string, f Persister) (string, int64, error) {
	full := path.Join(b.path, key)
	dir := path.Dir(full)
	err := os.MkdirAll(dir, 0755)
	if err != nil {
		log.WithError(err).WithField("path", dir).Error("failed to create storage directory")
		return "", 0, err
	}

	file, err := os.OpenFile(full, os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0644)
	if err != nil {
		log.WithError(err).WithField("file", full).Error("failed to write file")
		return "", 0, err
	}
	defer file.Close()

	err = xattr.Set(full, "user.mime_type", []byte(contentType))
	if err != nil {
		log.WithError(err).WithField("file", full).Error("failed to store file type in xattrs")
		return "", 0, err
	}

	return f(file)
}

func (b *FSBackend) Fetch(ctx context.Context, key string) (io.ReadCloser, error) {
	full := path.Join(b.path, key)
	return os.Open(full)
}

func (b *FSBackend) Move(ctx context.Context, old, new string) error {
	newpath := path.Join(b.path, new)
	err := os.MkdirAll(path.Dir(newpath), 0755)
	if err != nil {
		return err
	}

	return os.Rename(path.Join(b.path, old), newpath)
}

func (b *FSBackend) Serve(digest string, r *http.Request, w http.ResponseWriter) error {
	p := path.Join(b.path, "layers", digest)

	log.WithFields(log.Fields{
		"digest": digest,
		"path":   p,
	}).Info("serving blob from filesystem")

	contentType, err := xattr.Get(p, "user.mime_type")
	if err != nil {
		log.WithError(err).WithField("file", p).Error("failed to read file type from xattrs")
		return err
	}
	w.Header().Add("Content-Type", string(contentType))

	http.ServeFile(w, r, p)
	return nil
}
