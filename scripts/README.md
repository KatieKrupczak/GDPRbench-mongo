# Benchmark Scripts

## run-all-workloads.sh

Runs YCSB workloads a-f with and without MongoDB audit logging (profiling) enabled, and records throughput results.

### Prerequisites

- MongoDB installed (`brew install mongodb-community@7.0`)
- Project built (`cd src && mvn clean package -DskipTests -Dcheckstyle.skip=true -Psource-run`)

### Usage

```bash
# Run each workload once
./scripts/run-all-workloads.sh

# Run each workload 3 times and average the results
./scripts/run-all-workloads.sh 3

# Run each workload 5 times and average the results
./scripts/run-all-workloads.sh 5
```

### Output

Results are saved to `results/`:

- **`throughput_results.csv`** - Average throughput for each workload
  ```
  workload,audit_logging,throughput_ops_sec
  a,disabled,8872.01
  a,enabled,6802.51
  ...
  ```

- **`throughput_raw.csv`** (only when iterations > 1) - Individual run results
  ```
  workload,audit_logging,iteration,throughput_ops_sec
  a,disabled,1,9140.77
  a,disabled,2,8779.63
  ...
  ```

### What it does

1. Starts MongoDB
2. For each workload (a-f):
   - **Without audit logging**: Runs load + run phases, records throughput
   - **With audit logging**: Enables profiling level 2, runs load + run phases, records throughput
3. Stops MongoDB
4. Outputs summary to console and saves CSV files

### Sample Results

See `sample-results/` directory for example output from a 3-iteration run.
