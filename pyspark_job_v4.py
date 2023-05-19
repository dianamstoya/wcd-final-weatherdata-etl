from pyspark.sql import SparkSession
from pyspark.sql.types import *
from pyspark.sql.functions import *
import argparse

# parse the arguments from the spark submit command
parser = argparse.ArgumentParser()
parser.add_argument("--msk_bootstrap_servers")
parser.add_argument("--kafka_topic")
parser.add_argument("--s3_path")
parser.add_argument("--data_schema")
args = parser.parse_args()

BOOTSTRAP_SERVERS= args.msk_bootstrap_servers

if __name__ == "__main__":
    spark = SparkSession.builder.getOrCreate()

    # pull the schema from s3
    schema = spark.read.json(args.data_schema).schema

    # connect to the bootstrap servers
    df = spark \
        .readStream \
        .format("kafka") \
        .option("kafka.bootstrap.servers", BOOTSTRAP_SERVERS) \
        .option("subscribe", args.kafka_topic) \
        .option("startingOffsets", "latest") \
        .option("failOnDataLoss", "false") \
        .load()

    transform_df = df.select(col("value").cast("string")).alias("value") \
        .withColumn("jsonData",from_json(col("value"),schema)) \
        .select("jsonData.payload.after.*")
    
    # transformations specific to the weather data 
    transform_df = transform_df.withColumn("dt", from_unixtime("dt")) \
        .withColumn("sunrise", from_unixtime("sunrise")) \
        .withColumn('sunset', from_unixtime('sunset')) \
        .withColumn("temp", col("temp") - 273.15) \
        .withColumn("feels_like", col("feels_like") - 273.15) \
        .withColumn("temp_min", col("temp_min") - 273.15) \
        .withColumn("temp_max", col("temp_max") - 273.15)

    # set S3 checkpoint location
    checkpoint_location = "s3://bus-service-wcd-eu-west-1-diana/msk/checkpoint/sparkjob"
    table_name = 'bus_stats_msk'
    record_key = 'record_id'
    partition_path = 'country'
    pre_combine = 'dt'
    hudi_options = {
        'hoodie.table.name': table_name,
        "hoodie.datasource.write.table.type": "COPY_ON_WRITE",
        'hoodie.datasource.write.recordkey.field': record_key,
        'hoodie.datasource.write.partitionpath.field': partition_path,
        'hoodie.datasource.write.table.name': table_name,
        'hoodie.datasource.write.operation': 'upsert',
        'hoodie.datasource.write.precombine.field': pre_combine,
        'hoodie.upsert.shuffle.parallelism': 100,
        'hoodie.insert.shuffle.parallelism': 100
    }


    def write_batch(batch_df, batch_id):
        batch_df.write.format("org.apache.hudi") \
        .options(**hudi_options) \
        .mode("append") \
        .save(args.s3_path)


    # start the streaming 
    transform_df.writeStream \
        .option("checkpointLocation", checkpoint_location) \
        .queryName("wcd-bus-streaming") \
        .foreachBatch(write_batch) \
        .start() \
        .awaitTermination()
