package handlers

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"
)

var testCounter int

func TestLatestAPKPicksNewest(t *testing.T) {
	dir := apkTestDir(t)
	defer os.RemoveAll(dir)

	oldPath := filepath.Join(dir, "whereabouts-v1.apk")
	writeT(t, oldPath, "v1")
	time.Sleep(110 * time.Millisecond)
	newPath := filepath.Join(dir, "whereabouts-v2.apk")
	writeT(t, newPath, "v2")

	got, err := latestAPK(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got != newPath {
		t.Fatal("expected " + newPath + ", got " + got)
	}
}

func TestLatestApkIgnoresNonApk(t *testing.T) {
	dir := apkTestDir(t)
	defer os.RemoveAll(dir)

	writeT(t, filepath.Join(dir, "notes.txt"), "not an apk")
	apkPath := filepath.Join(dir, "whereabouts.apk")
	writeT(t, apkPath, "real apk")

	got, err := latestAPK(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got != apkPath {
		t.Fatal("expected " + apkPath + ", got " + got)
	}
}

func TestLatestApkMissingDir(t *testing.T) {
	_, err := latestAPK(filepath.Join(os.TempDir(), "wb-apk-does-not-exist"))
	if err == nil {
		t.Fatal("expected error for a missing dir, got nil")
	}
}

// apkTestDir returns a fresh, empty temp dir unique to this test file.
func apkTestDir(t *testing.T) string {
	testCounter++
	dir := filepath.Join(os.TempDir(), "wb-apk-" + fmt.Sprint(testCounter))
	os.RemoveAll(dir)
	if err := os.Mkdir(dir, 0o755); err != nil {
		t.Fatalf("mkdir: %s", err)
	}
	return dir
}

// writeT writes the given string as UTF-8 bytes to path.
func writeT(t *testing.T, path, contents string) {
	f, ferr := os.Create(path)
	if ferr != nil {
		t.Fatalf("create: %s", ferr)
	}
	f.Write([]byte(contents))
	f.Close()
}