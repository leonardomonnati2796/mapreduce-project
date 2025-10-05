package main

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestReduceResumeFromCheckpoint verifies that executeReduceTask resumes from a provided checkpoint
func TestReduceResumeFromCheckpoint(t *testing.T) {
	baseDir := t.TempDir()
	if err := os.Setenv("TMP_PATH", baseDir); err != nil {
		t.Fatalf("set TMP_PATH: %v", err)
	}

	// Prepare intermediate for reduceID=0 across two map tasks
	// map 0 -> keys: a, b
	// map 1 -> keys: a, c
	writeKV := func(path string, kvs []KeyValue) {
		f, err := os.Create(path)
		if err != nil {
			t.Fatalf("create %s: %v", path, err)
		}
		enc := json.NewEncoder(f)
		for _, kv := range kvs {
			_ = enc.Encode(kv)
		}
		_ = f.Close()
	}

	inter0 := filepath.Join(baseDir, "mr-intermediate-0-0")
	inter1 := filepath.Join(baseDir, "mr-intermediate-1-0")
	writeKV(inter0, []KeyValue{{Key: "a", Value: "1"}, {Key: "b", Value: "1"}})
	writeKV(inter1, []KeyValue{{Key: "a", Value: "1"}, {Key: "c", Value: "1"}})

	// Create checkpoint that indicates last processed key is "a"
	checkpoint := filepath.Join(baseDir, "mr-out-0.checkpoint.json")
	saveReduceCheckpoint(checkpoint, "a", 1)

	// Execute reduce with checkpoint provided in Task
	task := &Task{Type: ReduceTask, TaskID: 0, NMap: 2, Checkpoint: checkpoint}
	executeReduceTask(task, Reduce)

	// Verify output contains only b and c (not a)
	out := filepath.Join(baseDir, "mr-out-0")
	f, err := os.Open(out)
	if err != nil {
		t.Fatalf("open output: %v", err)
	}
	defer f.Close()

	s := bufio.NewScanner(f)
	foundB := false
	foundC := false
	foundA := false
	for s.Scan() {
		line := strings.TrimSpace(s.Text())
		if strings.HasPrefix(line, "a ") {
			foundA = true
		}
		if strings.HasPrefix(line, "b ") {
			foundB = true
		}
		if strings.HasPrefix(line, "c ") {
			foundC = true
		}
	}
	if err := s.Err(); err != nil {
		t.Fatalf("scan output: %v", err)
	}

	if foundA {
		t.Fatalf("expected to skip key 'a' due to checkpoint, but found it in output")
	}
	if !foundB || !foundC {
		t.Fatalf("expected to find keys 'b' and 'c' in output, foundB=%v foundC=%v", foundB, foundC)
	}
}
