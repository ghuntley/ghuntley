// Copyright 2022 The TVL Contributors
// SPDX-License-Identifier: Apache-2.0
package builder

// This file implements logic for walking through a directory and creating a
// tarball of it.
//
// The tarball is written straight to the supplied reader, which makes it
// possible to create an image layer from the specified store paths, hash it and
// upload it in one reading pass.
import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/google/nixery/layers"
)

// Create a new compressed tarball from each of the paths in the list
// and write it to the supplied writer.
//
// The uncompressed tarball is hashed because image manifests must
// contain both the hashes of compressed and uncompressed layers.
func packStorePaths(l *layers.Layer, w io.Writer) (string, error) {
	shasum := sha256.New()
	gz := gzip.NewWriter(w)
	multi := io.MultiWriter(shasum, gz)
	t := tar.NewWriter(multi)

	for _, path := range l.Contents {
		err := filepath.Walk(path, tarStorePath(t))
		if err != nil {
			return "", err
		}
	}

	if err := t.Close(); err != nil {
		return "", err
	}

	if err := gz.Close(); err != nil {
		return "", err
	}

	return fmt.Sprintf("sha256:%x", shasum.Sum([]byte{})), nil
}

func tarStorePath(w *tar.Writer) filepath.WalkFunc {
	return func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		// If the entry is not a symlink or regular file, skip it.
		if info.Mode()&os.ModeSymlink == 0 && !info.Mode().IsRegular() {
			return nil
		}

		// the symlink target is read if this entry is a symlink, as it
		// is required when creating the file header
		var link string
		if info.Mode()&os.ModeSymlink != 0 {
			link, err = os.Readlink(path)
			if err != nil {
				return err
			}
		}

		header, err := tar.FileInfoHeader(info, link)
		if err != nil {
			return err
		}

		// The name retrieved from os.FileInfo only contains the file's
		// basename, but the full path is required within the layer
		// tarball.
		header.Name = path
		if err = w.WriteHeader(header); err != nil {
			return err
		}

		// At this point, return if no file content needs to be written
		if !info.Mode().IsRegular() {
			return nil
		}

		f, err := os.Open(path)
		if err != nil {
			return err
		}

		if _, err := io.Copy(w, f); err != nil {
			return err
		}

		f.Close()

		return nil
	}
}
