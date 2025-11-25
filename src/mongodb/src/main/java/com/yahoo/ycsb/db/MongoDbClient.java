/**
 * Copyright (c) 2012 - 2015 YCSB contributors. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you
 * may not use this file except in compliance with the License. You
 * may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 * implied. See the License for the specific language governing
 * permissions and limitations under the License. See accompanying
 * LICENSE file.
 */

/*
 * MongoDB client binding for YCSB.
 *
 * Submitted by Yen Pai on 5/11/2010.
 *
 * https://gist.github.com/000a66b8db2caf42467b#file_mongo_database.java
 */
package com.yahoo.ycsb.db;

import com.mongodb.MongoClientSettings;
import com.mongodb.ConnectionString;
import com.mongodb.ReadPreference;
import com.mongodb.WriteConcern;
import com.mongodb.client.FindIterable;
import com.mongodb.client.MongoClient;
import com.mongodb.client.MongoClients;
import com.mongodb.client.MongoCollection;
import com.mongodb.client.MongoCursor;
import com.mongodb.client.MongoDatabase;
import com.mongodb.client.model.InsertManyOptions;
import com.mongodb.client.model.UpdateOneModel;
import com.mongodb.client.model.UpdateOptions;
import com.mongodb.client.model.ReplaceOptions;
import com.mongodb.client.result.DeleteResult;
import com.mongodb.client.result.UpdateResult;
import com.yahoo.ycsb.ByteArrayByteIterator;
import com.yahoo.ycsb.ByteIterator;
import com.yahoo.ycsb.DB;
import com.yahoo.ycsb.DBException;
import com.yahoo.ycsb.Status;

import org.bson.Document;
import org.bson.types.Binary;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.Set;
import java.util.Vector;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * MongoDB binding for YCSB framework using the MongoDB Inc. <a
 * href="http://docs.mongodb.org/ecosystem/drivers/java/">driver</a>.
 * <p>
 * See the <code>README.md</code> for configuration information.
 * </p>
 *
 * @author ypai
 * @see <a href="http://docs.mongodb.org/ecosystem/drivers/java/">MongoDB Inc.
 *      driver</a>
 */
public class MongoDbClient extends DB {

  /** Used to include a field in a response. */
  private static final Integer INCLUDE = Integer.valueOf(1);

  /** GDPR metadata field names. */
  private static String[] fieldnames = {
      "PUR", "TTL", "USR", "OBJ", "DEC", "ACL", "SHR", "SRC", "CAT", "Data"
  };

  /** The options to use for inserting many documents. */
  private static final InsertManyOptions INSERT_UNORDERED = new InsertManyOptions().ordered(false);

  /** The options to use for inserting a single document. */
  private static final UpdateOptions UPDATE_WITH_UPSERT = new UpdateOptions()
      .upsert(true);
  /** GDPR metadata field names. */
  private static final ReplaceOptions REPLACE_WITH_UPSERT = new ReplaceOptions()
      .upsert(true);

  /**
   * The database name to access.
   */
  private static String databaseName;

  /** The database name to access. */
  private static MongoDatabase database;

  /**
   * Count the number of times initialized to teardown on the last
   * {@link #cleanup()}.
   */
  private static final AtomicInteger INIT_COUNT = new AtomicInteger(0);

  /** A singleton Mongo instance. */
  private static MongoClient mongoClient;

  /** The default read preference for the test. */
  private static ReadPreference readPreference;

  /** The default write concern for the test. */
  private static WriteConcern writeConcern;

  /** The batch size to use for inserts. */
  private static int batchSize;

  /** If true then use updates with the upsert option for inserts. */
  private static boolean useUpsert;

  /** The bulk inserts pending for the thread. */
  private final List<Document> bulkInserts = new ArrayList<Document>();

  /** Cleanup thread for expired documents */
  private static Thread cleanupThread;
  private static volatile boolean cleanupRunning = false;
  private static int cleanupIntervalSeconds = 60;

  /**
   * Cleanup any state for this DB. Called once per DB instance; there is one DB
   * instance per client thread.
   */
  @Override
  public final void cleanup() throws DBException {
    if (INIT_COUNT.decrementAndGet() == 0) {
      try {
        // Stop the background cleanup thread
        if (cleanupThread != null) {
          System.out.println("[MongoDB Cleanup] Stopping background thread...");
          cleanupRunning = false;
          cleanupThread.interrupt();

          try {
            cleanupThread.join(5000);
          } catch (InterruptedException e) {
            System.err.println("[MongoDB Cleanup] Thread did not stop gracefully");
          }

          cleanupThread = null;
        }

        // Run final cleanup before closing connection
        System.out.println("[MongoDB Cleanup] Running final cleanup...");
        try {
          for (String collectionName : database.listCollectionNames()) {
            if (!collectionName.startsWith("system.") &&
                !collectionName.equals("audit_log")) {
              cleanupExpiredDocuments(collectionName);
            }
          }
        } catch (Exception e) {
          System.err.println("[MongoDB Cleanup] Error during final cleanup: " + e);
        }

        mongoClient.close();
      } catch (Exception e1) {
        System.err.println("Could not close MongoDB connection pool: "
            + e1.toString());
        e1.printStackTrace();
        return;
      } finally {
        database = null;
        mongoClient = null;
      }
    }
  }

  /**
   * Delete a record from the database.
   *
   * @param table
   *              The name of the table
   * @param key
   *              The record key of the record to delete.
   * @return Zero on success, a non-zero error code on error. See the {@link DB}
   *         class's description for a discussion of error codes.
   */
  @Override
  public final Status delete(final String table, final String key) {
    try {
      MongoCollection<Document> collection = database.getCollection(table);

      Document query = new Document("_id", key);
      DeleteResult result = collection.withWriteConcern(writeConcern).deleteOne(query);
      if (result.wasAcknowledged() && result.getDeletedCount() == 0) {
        System.err.println("Nothing deleted for key " + key);
        return Status.NOT_FOUND;
      }
      return Status.OK;
    } catch (Exception e) {
      System.err.println(e.toString());
      return Status.ERROR;
    }
  }

  /**
   * Initialize any state for this DB. Called once per DB instance; there is one
   * DB instance per client thread.
   */
  @Override
  public final void init() throws DBException {
    INIT_COUNT.incrementAndGet();
    synchronized (INCLUDE) {
      if (mongoClient != null) {
        return;
      }

      Properties props = getProperties();

      // Set insert batchsize, default 1 - to be YCSB-original equivalent
      batchSize = Integer.parseInt(props.getProperty("batchsize", "1"));

      // Set is inserts are done as upserts. Defaults to false.
      useUpsert = Boolean.parseBoolean(
          props.getProperty("mongodb.upsert", "false"));

      // Just use the standard connection format URL
      // http://docs.mongodb.org/manual/reference/connection-string/
      // to configure the client.
      String url = props.getProperty("mongodb.url", null);
      boolean defaultedUrl = false;
      if (url == null) {
        defaultedUrl = true;
        url = "mongodb://localhost:27017/ycsb?w=1";
      }

      url = OptionsSupport.updateUrl(url, props);

      if (!url.startsWith("mongodb://") && !url.startsWith("mongodb+srv://")) {
        System.err.println("ERROR: Invalid URL: '"
            + url
            + "'");
        System.err.println("Must be of the form 'mongodb://<host1>:<port1>,"
            + "<host2>:<port2>/"
            + "database?options' or 'mongodb+srv://<host>/database?options'.");
        System.err.println("See http://docs.mongodb.org/manual/"
            + "reference/connection-string/");
        System.exit(1);
      }

      try {
        ConnectionString uri = new ConnectionString(url);
        MongoClientSettings.Builder csb = MongoClientSettings.builder()
            .applyConnectionString(uri);

        String uriDb = uri.getDatabase();
        if (!defaultedUrl && (uriDb != null) && !uriDb.isEmpty()
            && !"admin".equals(uriDb)) {
          databaseName = uriDb;
        } else {
          // If no database is specified in URI, use "ycsb"
          databaseName = "ycsb";

        }

        mongoClient = MongoClients.create(csb.build());
        database = mongoClient.getDatabase(databaseName);

        // Ensure non-null defaults for read preference and write concern
        writeConcern = database.getWriteConcern();
        if (writeConcern == null) {
          writeConcern = WriteConcern.ACKNOWLEDGED;
        }
        readPreference = database.getReadPreference();
        if (readPreference == null) {
          readPreference = ReadPreference.primary();
        }
        // Get cleanup interval from properties
        cleanupIntervalSeconds = Integer.parseInt(
            props.getProperty("mongodb.cleanup.interval", "60"));

        // Start automatic cleanup thread
        if (cleanupThread == null) {
          startCleanupThread();
        }

        // Get audit log path from properties (for readLog functionality)
        auditLogPath = props.getProperty("mongodb.auditlog.path", null);
        if (auditLogPath != null) {
          System.out.println("Audit log path configured: " + auditLogPath);
        }

        System.out.println("mongo client connection created with " + url + "\n");
      } catch (Exception e1) {
        System.err
            .println("Could not initialize MongoDB connection pool for Loader: "
                + e1.toString());
        e1.printStackTrace();
        return;
      }
    }
  }

  /**
   * Start the background cleanup thread.
   */
  private void startCleanupThread() {
    cleanupRunning = true;
    cleanupThread = new Thread(() -> {
      System.out.println("[MongoDB Cleanup] Background thread started, " +
          "interval: " + cleanupIntervalSeconds + "s");

      while (cleanupRunning) {
        try {
          Thread.sleep(cleanupIntervalSeconds * 1000L);

          // Clean all user collections
          for (String collectionName : database.listCollectionNames()) {
            if (!collectionName.startsWith("system.") &&
                !collectionName.equals("audit_log")) {
              cleanupExpiredDocuments(collectionName);
            }
          }
        } catch (InterruptedException e) {
          System.out.println("[MongoDB Cleanup] Thread interrupted");
          break;
        } catch (Exception e) {
          System.err.println("[MongoDB Cleanup] Error: " + e);
        }
      }

      System.out.println("[MongoDB Cleanup] Background thread stopped");
    }, "MongoDB-TTL-Cleanup");

    cleanupThread.setDaemon(true);
    cleanupThread.start();
  }

  /**
   * Manually delete all expired documents from a table.
   * Can be called manually or used by the background cleanup thread.
   * 
   * @param table The name of the table to clean up
   * @return Status.OK on success, Status.ERROR on error
   */
  public final Status cleanupExpiredDocuments(final String table) {
    try {
      MongoCollection<Document> collection = database.getCollection(table);
      long currentTimeSeconds = System.currentTimeMillis() / 1000;

      Document query = new Document("expiresAt",
          new Document("$lte", currentTimeSeconds));

      DeleteResult result = collection.deleteMany(query);

      if (result.getDeletedCount() > 0) {
        System.out.println("[MongoDB Cleanup] Deleted " + result.getDeletedCount() +
            " expired documents from " + table);
      }

      return Status.OK;
    } catch (Exception e) {
      System.err.println("[MongoDB Cleanup] Error cleaning " + table + ": " + e);
      return Status.ERROR;
    }
  }

  /**
   * Insert a record in the database. Any field/value pairs in the specified
   * values HashMap will be written into the record with the specified record
   * key.
   *
   * @param table
   *               The name of the table
   * @param key
   *               The record key of the record to insert.
   * @param values
   *               A HashMap of field/value pairs to insert in the record
   * @return Zero on success, a non-zero error code on error. See the {@link DB}
   *         class's description for a discussion of error codes.
   */
  @Override
  public final Status insert(final String table, final String key,
      final Map<String, ByteIterator> values) {
    try {
      MongoCollection<Document> collection = database.getCollection(table);
      Document toInsert = new Document("_id", key);
      for (Map.Entry<String, ByteIterator> entry : values.entrySet()) {
        toInsert.put(entry.getKey(), entry.getValue().toArray());
      }

      if (batchSize == 1) {
        if (useUpsert) {
          // this is effectively an insert, but using an upsert instead due
          // to current inability of the framework to clean up after itself
          // between test runs.
          collection.replaceOne(new Document("_id", toInsert.get("_id")),
              toInsert, REPLACE_WITH_UPSERT);
        } else {
          collection.insertOne(toInsert);
        }
      } else {
        bulkInserts.add(toInsert);
        if (bulkInserts.size() == batchSize) {
          if (useUpsert) {
            List<UpdateOneModel<Document>> updates = new ArrayList<UpdateOneModel<Document>>(bulkInserts.size());
            for (Document doc : bulkInserts) {
              updates.add(new UpdateOneModel<Document>(
                  new Document("_id", doc.get("_id")),
                  new Document("$set", doc), UPDATE_WITH_UPSERT));
            }
            collection.bulkWrite(updates);
          } else {
            collection.insertMany(bulkInserts, INSERT_UNORDERED);
          }
          bulkInserts.clear();
        } else {
          return Status.BATCHED_OK;
        }
      }
      return Status.OK;
    } catch (Exception e) {
      System.err.println("Exception while trying bulk insert with "
          + bulkInserts.size());
      e.printStackTrace();
      return Status.ERROR;
    }

  }

  /**
   * Read a record from the database. Each field/value pair from the result will
   * be stored in a HashMap.
   *
   * @param table
   *               The name of the table
   * @param key
   *               The record key of the record to read.
   * @param fields
   *               The list of fields to read, or null for all of them
   * @param result
   *               A HashMap of field/value pairs for the result
   * @return Zero on success, a non-zero error code on error or "not found".
   */
  @Override
  public final Status read(final String table,
      final String key, final Set<String> fields,
      final Map<String, ByteIterator> result) {
    try {
      MongoCollection<Document> collection = database.getCollection(table);
      Document query = new Document("_id", key);

      FindIterable<Document> findIterable = collection.find(query);

      if (fields != null) {
        Document projection = new Document();
        for (String field : fields) {
          projection.put(field, INCLUDE);
        }
        findIterable.projection(projection);
      }

      Document queryResult = findIterable.first();

      if (queryResult != null) {
        if (queryResult.containsKey("expiresAt")) {
          long expiresAt = queryResult.getLong("expiresAt");
          long currentTimeSec = System.currentTimeMillis() / 1000;

          if (currentTimeSec >= expiresAt) {
            // Document is logically expired, even if not yet deleted by TTL monitor
            return Status.NOT_FOUND;
          }
        }
        fillMap(result, queryResult);
      }
      if (queryResult != null) {
        return Status.OK;
      }
      return Status.NOT_FOUND;
    } catch (Exception e) {
      System.err.println(e.toString());
      return Status.ERROR;
    }
  }

  /**
   * Perform a range scan for a set of records in the database. Each field/value
   * pair from the result will be stored in a HashMap.
   *
   * @param table       The name of the table
   * @param startkey    The record key of the first record to read.
   * @param recordcount The number of records to read
   * @param fields      The list of fields to read, or null for all of them
   * @param result      A Vector of HashMaps, where each HashMap is a set
   *                    field/value
   *                    pairs for one record
   * @return Zero on success, a non-zero error code on error. See the {@link DB}
   *         class's description for a discussion of error codes.
   */
  @Override
  public final Status scan(final String table,
      final String startkey, final int recordcount,
      final Set<String> fields,
      final Vector<HashMap<String, ByteIterator>> result) {
    MongoCursor<Document> cursor = null;
    try {
      MongoCollection<Document> collection = database.getCollection(table);

      Document scanRange = new Document("$gte", startkey);
      Document query = new Document("_id", scanRange);

      // Exclude expired documents
      long currentTimeSeconds = System.currentTimeMillis() / 1000;
      query.append("$or", java.util.Arrays.asList(
          new Document("expiresAt", new Document("$exists", false)), // No TTL
          new Document("expiresAt", new Document("$gt", currentTimeSeconds)) // Not expired
      ));

      Document sort = new Document("_id", INCLUDE);

      FindIterable<Document> findIterable = collection.find(query).sort(sort).limit(recordcount);

      if (fields != null) {
        Document projection = new Document();
        for (String fieldName : fields) {
          projection.put(fieldName, INCLUDE);
        }
        findIterable.projection(projection);
      }

      cursor = findIterable.iterator();

      if (!cursor.hasNext()) {
        System.err.println("Nothing found in scan for key " + startkey);
        return Status.ERROR;
      }

      result.ensureCapacity(recordcount);

      while (cursor.hasNext()) {
        HashMap<String, ByteIterator> resultMap = new HashMap<String, ByteIterator>();

        Document obj = cursor.next();
        fillMap(resultMap, obj);

        result.add(resultMap);
      }

      return Status.OK;
    } catch (Exception e) {
      System.err.println(e.toString());
      return Status.ERROR;
    } finally {
      if (cursor != null) {
        cursor.close();
      }
    }
  }

  /**
   * Update a record in the database. Any field/value pairs in the specified
   * values HashMap will be written into the record with the specified record
   * key, overwriting any existing values with the same field name.
   *
   * @param table  The name of the table
   * @param key    The record key of the record to write.
   * @param values A HashMap of field/value pairs to update in the record
   * @return Zero on success, a non-zero error code on error. See this class's
   *         description for a discussion of error codes.
   */
  @Override
  public final Status update(final String table, final String key,
      final Map<String, ByteIterator> values) {
    try {
      MongoCollection<Document> collection = database.getCollection(table);

      Document query = new Document("_id", key);
      Document fieldsToSet = new Document();
      for (Map.Entry<String, ByteIterator> entry : values.entrySet()) {
        fieldsToSet.put(entry.getKey(), entry.getValue().toArray());
      }
      Document update = new Document("$set", fieldsToSet);

      UpdateResult result = collection.updateOne(query, update);
      if (result.wasAcknowledged() && result.getMatchedCount() == 0) {
        System.err.println("Nothing updated for key " + key);
        return Status.NOT_FOUND;
      }
      return Status.OK;
    } catch (Exception e) {
      System.err.println(e.toString());
      return Status.ERROR;
    }
  }

  /**
   * Fills the map with the values from the DBObject.
   *
   * @param resultMap The map to fill
   * @param obj       The object to copy values from.
   */
  /**
   * Insert a record with a TTL field. Any field/value pairs in the specified
   * values HashMap will be written into the record with the specified record
   * key.
   */
  @Override
  public final Status insertTTL(final String table, final String key,
      final Map<String, ByteIterator> values, final int ttl) {
    try {
      MongoCollection<Document> collection = database.getCollection(table);
      Document toInsert = new Document("_id", key);
      for (Map.Entry<String, ByteIterator> entry : values.entrySet()) {
        toInsert.put(entry.getKey(), entry.getValue().toArray());
      }

      // FIXED: Add timestamp fields for TTL verification
      long currentTimeSeconds = System.currentTimeMillis() / 1000;
      toInsert.put("createdAt", currentTimeSeconds); // When created
      toInsert.put("TTL", ttl); // TTL duration in seconds
      toInsert.put("expiresAt", currentTimeSeconds + ttl); // When it expires

      if (batchSize == 1) {
        if (useUpsert) {
          collection.replaceOne(new Document("_id", toInsert.get("_id")),
              toInsert, REPLACE_WITH_UPSERT);
        } else {
          collection.insertOne(toInsert);
        }
      } else {
        bulkInserts.add(toInsert);
        if (bulkInserts.size() == batchSize) {
          if (useUpsert) {
            List<UpdateOneModel<Document>> updates = new ArrayList<UpdateOneModel<Document>>(bulkInserts.size());
            for (Document doc : bulkInserts) {
              updates.add(new UpdateOneModel<Document>(
                  new Document("_id", doc.get("_id")),
                  new Document("$set", doc), UPDATE_WITH_UPSERT));
            }
            collection.bulkWrite(updates);
          } else {
            collection.insertMany(bulkInserts, INSERT_UNORDERED);
          }
          bulkInserts.clear();
        } else {
          return Status.BATCHED_OK;
        }
      }
      return Status.OK;
    } catch (Exception e) {
      System.err.println("Exception while trying bulk insert with TTL");
      e.printStackTrace();
      return Status.ERROR;
    }
  }

  @Override
  public final Status readMeta(final String table, final int fieldnum,
      final String condition, final String keymatch,
      final Vector<HashMap<String, ByteIterator>> result) {
    try {
      MongoCollection<Document> collection = database.getCollection(table);
      Document query = new Document();
      if (keymatch != null && !keymatch.isEmpty()) {
        query.put("_id", new Document("$regex", keymatch));
      }
      query.put(fieldnames[fieldnum], condition);

      FindIterable<Document> findIterable = collection.find(query);
      MongoCursor<Document> cursor = findIterable.iterator();

      while (cursor.hasNext()) {
        Document obj = cursor.next();
        HashMap<String, ByteIterator> resultMap = new HashMap<String, ByteIterator>();
        fillMap(resultMap, obj);
        result.add(resultMap);
      }
      return Status.OK;
    } catch (Exception e) {
      System.err.println(e.toString());
      return Status.ERROR;
    }
  }

  @Override
  public final Status updateMeta(final String table, final int fieldnum,
      final String condition,
      final String keymatch, final String newfieldname,
      final String newmetadatavalue) {
    try {
      MongoCollection<Document> collection = database.getCollection(table);
      Document query = new Document();
      if (keymatch != null && !keymatch.isEmpty()) {
        query.put("_id", new Document("$regex", keymatch));
      }
      query.put(fieldnames[fieldnum], condition);

      Document update = new Document("$set",
          new Document(newfieldname, newmetadatavalue));

      UpdateResult result = collection.updateMany(query, update);
      return Status.OK;
    } catch (Exception e) {
      System.err.println(e.toString());
      return Status.ERROR;
    }
  }

  @Override
  public final Status deleteMeta(final String table, final int fieldnum,
      final String condition, final String keymatch) {
    try {
      MongoCollection<Document> collection = database.getCollection(table);
      Document query = new Document();
      if (keymatch != null && !keymatch.isEmpty()) {
        query.put("_id", new Document("$regex", keymatch));
      }
      query.put(fieldnames[fieldnum], condition);

      DeleteResult result = collection.deleteMany(query);
      return Status.OK;
    } catch (Exception e) {
      System.err.println(e.toString());
      return Status.ERROR;
    }
  }

  /**
   * Fills the map with the values from the DBObject.
   * 
   * @param resultMap The map to fill
   * @param obj       The object to copy values from.
   */
  protected final void fillMap(final Map<String, ByteIterator> resultMap,
      final Document obj) {
    for (Map.Entry<String, Object> entry : obj.entrySet()) {
      if (entry.getValue() instanceof Binary) {
        resultMap.put(entry.getKey(),
            new ByteArrayByteIterator(((Binary) entry.getValue()).getData()));
      }
    }
  }

  /**
   * Verify the TTL for a given document.
   * 
   * @param key         The record key of the document to check
   * @param currentTime The current time in milliseconds
   * @return Status.OK if the document exists and TTL is valid, Status.NOT_FOUND
   *         if expired or doesn't exist,
   *         Status.ERROR on error
   */
  @Override
  public final Status verifyTTL(final String table, final long recordcount) {
    try {
      MongoCollection<Document> collection = database.getCollection(table);
      String key = String.valueOf(recordcount);
      Document query = new Document("_id", key);
      Document result = collection.find(query).first();
      if (result == null) {
        return Status.NOT_FOUND;
      }

      if (result.containsKey("expiresAt")) {
        long expiresAt = result.getLong("expiresAt");
        long currentTimeSeconds = System.currentTimeMillis() / 1000; // Convert ms to seconds

        if (currentTimeSeconds >= expiresAt) {
          return Status.NOT_FOUND; // Document has expired
        }
      }
      return Status.OK;
    } catch (Exception e) {
      System.err.println("Error verifying TTL: " + e.toString());
      return Status.ERROR;
    }
  }

  /** Path to the audit log file (configurable via mongodb.auditlog.path property) */
  private static String auditLogPath;

  @Override
  public final Status readLog(final String table, final int logCount) {
    try {
      System.out.println("\n[MongoDB] readLog called for table: " + table +
          ", requesting " + logCount + " entries");

      // If audit log path is configured, read from the file
      if (auditLogPath != null && !auditLogPath.isEmpty()) {
        java.io.File auditFile = new java.io.File(auditLogPath);
        if (auditFile.exists() && auditFile.canRead()) {
          // Force flush to ensure audit log is up to date
          try {
            database.runCommand(new Document("fsync", 1));
          } catch (Exception e) {
            // fsync may not be available in all configurations
            System.out.println("[MongoDB] fsync skipped: " + e.getMessage());
          }

          // Read last N lines from audit log (tail)
          java.util.List<String> lines = new java.util.ArrayList<>();
          try (java.io.RandomAccessFile raf = new java.io.RandomAccessFile(auditFile, "r")) {
            long fileLength = raf.length();
            if (fileLength > 0) {
              // Start from end and work backwards
              long pos = fileLength - 1;
              int lineCount = 0;
              StringBuilder sb = new StringBuilder();

              while (pos >= 0 && lineCount < logCount) {
                raf.seek(pos);
                char c = (char) raf.readByte();
                if (c == '\n') {
                  if (sb.length() > 0) {
                    lines.add(0, sb.reverse().toString());
                    sb = new StringBuilder();
                    lineCount++;
                  }
                } else {
                  sb.append(c);
                }
                pos--;
              }
              // Don't forget the first line
              if (sb.length() > 0 && lineCount < logCount) {
                lines.add(0, sb.reverse().toString());
              }
            }
          }

          System.out.println("[MongoDB] Read " + lines.size() + " audit log entries");
          for (String line : lines) {
            System.out.println("  " + line);
          }
          return Status.OK;
        } else {
          System.out.println("[MongoDB] Audit log file not found or not readable: " + auditLogPath);
        }
      }

      // Fallback: Try reading from system.profile collection (operation profiling)
      MongoCollection<Document> profileCollection = database.getCollection("system.profile");
      FindIterable<Document> profiles = profileCollection.find()
          .sort(new Document("ts", -1))
          .limit(logCount);

      int count = 0;
      for (Document profile : profiles) {
        System.out.println("  Profile: " + profile.toJson());
        count++;
      }

      if (count > 0) {
        System.out.println("[MongoDB] Read " + count + " profile entries");
      } else {
        System.out.println("[MongoDB] No profile entries found. " +
            "Enable profiling with: db.setProfilingLevel(2)");
      }

      return Status.OK;
    } catch (Exception e) {
      System.err.println("\nError in readLog: " + e.toString());
      e.printStackTrace();
      return Status.ERROR;
    }
  }

}
