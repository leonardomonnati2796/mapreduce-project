# Test Dynamic Reducers Implementation

## Changes Made

### 1. Modified `src/main.go`
- Removed hardcoded `nReduce = 10` constant
- Added `calculateDynamicReducerCount()` function that:
  - First checks `WORKER_COUNT` environment variable
  - Falls back to querying existing masters for worker count
  - Uses master count as estimation if no workers are detected
  - Defaults to 3 workers if nothing else works
- Added `queryWorkerCountFromMaster()` function to query masters for current worker count

### 2. Modified `src/rpc.go`
- Added `GetWorkerCountArgs` and `WorkerCountReply` structures for RPC communication

### 3. Modified `src/master.go`
- Added `GetWorkerCount()` RPC method that returns active and total worker counts

### 4. Modified `docker/docker-compose.yml`
- Added `WORKER_COUNT: "3"` to common variables
- Added `WORKER_COUNT: "4"` to extended variables (for additional workers)

### 5. Modified `docker/docker-compose.aws.yml`
- Added `WORKER_COUNT: "${WORKER_COUNT:-3}"` to support environment variable override

## How It Works

1. **Environment Variable Priority**: The system first checks for `WORKER_COUNT` environment variable
2. **Dynamic Detection**: If no environment variable is set, it tries to query existing masters
3. **Fallback Estimation**: If no masters are available, it estimates based on master count
4. **Default Fallback**: Finally defaults to 3 workers (typical docker-compose setup)

## Testing

To test the implementation:

1. **Set environment variable**:
   ```bash
   export WORKER_COUNT=5
   ./mapreduce master 0 "file1.txt,file2.txt"
   ```

2. **Use docker-compose with custom worker count**:
   ```bash
   WORKER_COUNT=4 docker-compose up
   ```

3. **Check the logs** for messages like:
   - "Numero di worker da variabile d'ambiente WORKER_COUNT: X"
   - "Numero di worker rilevato dal master: X"
   - "Numero di worker stimato da configurazione master: X"

## Benefits

- **Optimal Resource Utilization**: Number of reducers equals number of workers
- **Dynamic Scaling**: Automatically adjusts when worker count changes
- **Backward Compatibility**: Still works with existing configurations
- **Flexible Configuration**: Can be overridden via environment variables
