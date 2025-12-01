# GDPRbench - MongoDB

The General Data Protection Regulation (GDPR) was introduced in Europe to offer new rights and protections to people concerning their personal data. GDPRbench aimed to benchmark how well a given storage system responded to the common queries of GDPR. In order to do this, the authors [identified](images/gdpr-workloads.png) four key roles in GDPR--customer, controller, processor, and regulator--and composed workloads corresponding to their functionalities. The design of this benchmark was guided by their analysis of GDPR as well as the usage patterns from the real-world.

We extend GDPRbench by adding GDPR-compliant functionality to MongoDB. This includes support for encryption, time-to-live (TTL) and audit logging. We compare the performance of these modifications to MongoDB with results on Redis from the original GDPRBench. 

## Design and Implementation

The authors of GDPRbench implement their changes by adapting and extending YCSB. This [figure](images/gdprbench.png) shows the core infrastructure components of YCSB (in gray), and their modifications and extensions (in blue). They create four new workloads, a GDPR-specific workload executor, and implement DB clients (one per storage system). We add code to an open-source version of MongoDB to interface with these components, which we enumerate below. 

### Prerequisites and Benchmarking
To get started with GDPRbench, download or clone this repository. It consists of a fully functional version of YCSB together with all the functionalities of GDPRbench. Please note that you will need [Maven 3](https://maven.apache.org/) to build and use the benchmark.

- MongoDB installed (`brew install mongodb-community@7.0`)
  - if this doesn't work, first run brew tap `mongodb/brew` then try the above
- Project built (`cd src && mvn clean package -DskipTests -Dcheckstyle.skip=true -Psource-run`)
- Cryptsetup (LUKS encryption-at-rest) (`sudo apt install cryptsetup`)
- OpenSSL (`sudo apt install openssl`)

** macOS does not support LUKS natively.
This project’s encryption-at-rest feature should be run on Linux.

To further set up encryption, the followinng scripts should be run from the root directory of the repository:
``` bash
bash scripts/luks-create.sh
bash scripts/setup-tls.sh
```

And to run all workloads n times (default, n=1), after setting up all of the above, run:
``` bash
bash scripts/run-all-workloads.sh [n]
```

More details about the scripts can be found in scripts/README.md

## Report Map

#### Section 2.1.1 (Encryption):
- .gitignore (MODIFIED):
  - Lines 6-13: Added certificates.
- certs/openssl-server.cnf (NEW): OpenSSL certificate.
- certs/ca.pem (NEW): Certificates.
- setup-tls (NEW): Creates all cerificates requires for TLS encryption-in-transit.
- luks-create.sh (NEW): Creates the encrypted LUKS disk image.
- luks-open.sh (NEW): Unlocks the LUKS volume and mounts it.
- luks-close.sh (NEW): Unmounts and closes the LUKS encrypted volume.
- scripts/mongo-luks.key (NEW): MongoDB LUKS key.

#### Section 2.1.2 (Time-To-Live Deletion):
- src/mongodb/src/main/java/com/yahoo/ycsb/db/MongoDbClient.java (MODIFIED):
  - Lines 282-294: ttlEnabled and sweeperEnabled boolean logic.
  - Lines 359-368: Date object tracking.
  - Lines 408-417: TTL logic.
  - Lines 538-544: Document expiration tracking.
  - Lines 644-654: TTL metadata insertion.
- scripts/run-all-workloads.sh (NEW):
  - Lines 197-211: Enable TTL functionality.

#### Section 2.1.3 (Auditing):
- src/mongodb/src/main/java/com/yahoo/ycsb/db/MongoDbClient.java (MODIFIED):
  - Lines 287-292: Get audit log path.
  - Lines 789-859: Read and write from log path.
- src/mongodb/pom.xml (MODIFIED):
  - Lines 39-43: removed async driver.
  - Lines 71-89: removed allanbank repository.

#### Section 4 (Evaluation):
- scripts/run-all-workloads.sh (NEW): Runs all YCSB workloads (a-f) under multiple GDPR feature configurations.
- scripts/run-benchmark.sh (NEW): Runs configurable benchmark with togglable auditing and roles.
- scripts/start-mongo.sh (NEW): Starts up MongoDB.
- scripts/stop-mongo.sh (NEW): Closes down MongoDB.
- configs/mongod-nolog.yaml (NEW): Config file for MongoDB without audit logging.
- configs/mongod-log.yaml (NEW): Config file for MongoDB with audit logging.
- results/ (NEW): Folder containing snapshots and CSV-formatted output, and an Excel file used for plotting the final results


## Code Attribution
We built off of the following open-source repositories in our modified implementation of GDPRBench:
- <a href=https://github.com/GDPRbench/GDPRbench> GDPRbench </a>
- <a href=https://github.com/brianfrankcooper/YCSB> Yahoo! Cloud Serving Benchmark </a>
- <a href=https://github.com/mongodb/mongo>MongoDB Community Edition </a>

