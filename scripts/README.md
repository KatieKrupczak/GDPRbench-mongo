# Benchmark Scripts

## run-all-workloads.sh

Runs all YCSB workloads (a–f) under multiple GDPR feature configurations:
- Baseline (no audit, no encryption, no TTL)
- Audit only
- Encryption only (LUKS encryption-at-rest + TLS encryption-in-transit)
- TTL only (hooked, placeholder for expiration tests)
- All features on

Throughput results are recorded to CSV files.

### Prerequisites

- MongoDB installed (`brew install mongodb-community@7.0`)
- Project built (`cd src && mvn clean package -DskipTests -Dcheckstyle.skip=true -Psource-run`)
- Cryptsetup (LUKS encryption-at-rest) (`sudo apt install cryptsetup`)
- OpenSSL (`sudo apt install openssl`)

** macOS does not support LUKS natively.
This project’s encryption-at-rest feature should be run on Linux.

### TLS + LUKS Setup Scripts
These are used when encryption mode is enabled in the benchmark.

`setup-tls.sh`: creates all certificates required for TLS encryption-in-transit
- certs/ca.key, certs/ca.pem — certificate authority
- certs/server.key, certs/server.crt, certs/server.pem — MongoDB server cert
- certs/mongo-truststore.jks — Java truststore used by the YCSB client

  This script is automatically invoked by run-all-workloads.sh if the TLS materials do not already exist.

`luks-create.sh`: creates the encrypted LUKS disk image
- .luks/mongo.img

  Runs only once, the first time encryption-at-rest is requested.

`luks-open.sh`: Unlocks the LUKS volume and mounts it at
- .luks/mnt/
  
  This becomes the MongoDB --dbpath for encrypted configurations.

`luks-close.sh`

  Unmounts and closes the LUKS encrypted volume.
  Automatically run after encrypted configurations finish.


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
  workload,config,audit,encryption,ttl,throughput_ops_sec
  a,baseline,false,false,false,4562.04
  ...
  ```

- **`throughput_raw.csv`** (only when iterations > 1) - Individual run results
  ```
  workload,config,audit,encryption,ttl,iteration,throughput_ops_sec
  a,baseline,false,false,false,1,9140.77
  ...
  ```

### What it does
`run-all-workloads.sh` iterates through a set of GDPR feature configurations: baseline, audit, encryption, ttl (TBD), and all (TBD).

For each configuration, it:
1. Starts a fresh MongoDB instance with the appropriate settings for that configuration.
2. Runs all YCSB workloads (a–f), resetting the YCSB database between workloads.
3. Stops MongoDB after that configuration finishes.
4. Records throughput for each workload/config combination into CSV files.

Lastly, outputs summary to console and saves CSV files

This produces a complete comparison of workload performance under each GDPR-related feature mode.


### Sample Results

See `sample-results/` directory for example output from a 3-iteration run.
