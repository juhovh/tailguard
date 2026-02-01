package env

import (
	"os"
	"strconv"
	"testing"
	"time"
)

func TestGetEpochAsDateString_ValidEpoch(t *testing.T) {
	tmpfile, err := os.CreateTemp("", "epoch-*.txt")
	if err != nil {
		t.Fatalf("Failed to create temp file: %v", err)
	}
	defer os.Remove(tmpfile.Name())
	epoch := time.Date(2023, 1, 2, 3, 4, 5, 0, time.UTC).Unix()
	if _, err := tmpfile.WriteString(strconv.FormatInt(epoch, 10)); err != nil {
		t.Fatalf("Failed to write to temp file: %v", err)
	}
	tmpfile.Close()

	dateStr := getEpochAsDateString(tmpfile.Name())
	if dateStr == nil {
		t.Fatalf("Expected non-nil date string")
	}
	parsed, err := time.Parse(time.RFC3339, *dateStr)
	if err != nil {
		t.Fatalf("Returned string is not RFC3339: %v", err)
	}
	if !parsed.Equal(time.Date(2023, 1, 2, 3, 4, 5, 0, time.UTC)) {
		t.Errorf("Expected UTC time 2023-01-02T03:04:05Z, got %s", parsed.UTC().Format(time.RFC3339))
	}
}

func TestGetEpochAsDateString_FileNotExist(t *testing.T) {
	dateStr := getEpochAsDateString("/tmp/nonexistent-epoch-file.txt")
	if dateStr != nil {
		t.Errorf("Expected nil for non-existent file, got %v", *dateStr)
	}
}

func TestGetEpochAsDateString_EpochWithNewline(t *testing.T) {
	tmpfile, err := os.CreateTemp("", "epoch-nl-*.txt")
	if err != nil {
		t.Fatalf("Failed to create temp file: %v", err)
	}
	defer os.Remove(tmpfile.Name())
	epoch := time.Date(2024, 6, 1, 12, 0, 0, 0, time.UTC).Unix()
	if _, err := tmpfile.WriteString(strconv.FormatInt(epoch, 10) + "\n"); err != nil {
		t.Fatalf("Failed to write to temp file: %v", err)
	}
	tmpfile.Close()

	dateStr := getEpochAsDateString(tmpfile.Name())
	if dateStr == nil {
		t.Fatalf("Expected non-nil date string")
	}
	parsed, err := time.Parse(time.RFC3339, *dateStr)
	if err != nil {
		t.Fatalf("Returned string is not RFC3339: %v", err)
	}
	if !parsed.Equal(time.Date(2024, 6, 1, 12, 0, 0, 0, time.UTC)) {
		t.Errorf("Expected UTC time 2024-06-01T12:00:00Z, got %s", parsed.UTC().Format(time.RFC3339))
	}
}
