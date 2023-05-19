# on EC2, creating docker containers
docker run -dit --name mysql -p 3306:3306 -e MYSQL_ROOT_PASSWORD=debezium -e MYSQL_USER=mysqluser -e MYSQL_PASSWORD=mysqlpw debezium/example-mysql:1.6

docker run --name nifi -p 8080:8080 -p 8443:8443 --link mysql:mysql -d apache/nifi:1.12.0

# the following requires the bootstrap servers for MSK
docker run -dit --name connect-msk \
  -p 8083:8083 \
  -e GROUP_ID=1 \
  -e CONFIG_STORAGE_TOPIC=my-connect-configs \
  -e OFFSET_STORAGE_TOPIC=my-connect-offsets \
  -e STATUS_STORAGE_TOPIC=my_connect_statuses \
  -e BOOTSTRAP_SERVERS=$BOOTSTRAP_SERVERS \
  -e KAFKA_VERSION=2.8.1 \
  -e CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR=2 \
  -e CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR=2 \
  -e CONNECT_STATUS_STORAGE_REPLICATION_FACTOR=2 \
  --link mysql:mysql debezium/connect:1.8.0.Final

# connector for weather data
curl -i -X POST \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  localhost:8083/connectors/ \
  -d '{
	"name": "weather-connector",
	"config": {
	  "connector.class": "io.debezium.connector.mysql.MySqlConnector",
	  "tasks.max": "1",
	  "database.hostname": "mysql",
	  "database.port": "3306",
	  "database.user": "root",
	  "database.password": "debezium",
	  "database.server.id": "184054",
	  "database.server.name": "dbserver1",
	  "database.include.list": "project",
	  "database.history.kafka.bootstrap.servers": "'"$BOOTSTRAP_SERVERS"'",
	  "database.history.kafka.topic": "dbhistory.demo"
	  }
	}'

# next: creation of the AWS resources
# MSK cluster
aws kafka create-cluster \
  --cluster-name final-project-msk1 \
  --broker-node-group-info file://broker_node_group_info.json \
  --client-authentication file://client_auth.json \
  --encryption-info file://myencryptioninfo.json \
  --kafka-version "2.8.1" \
  --number-of-broker-nodes 3 \
  --enhanced-monitoring DEFAULT \
  --configuration-info file://my_conf_arn.json 

# EMR cluster 
aws emr create-cluster \
  --name "final-cluster-v1" \
  --release-label "emr-6.8.0" \
  --service-role "arn:aws:iam::196727404096:role/service-role/AmazonEMR-ServiceRole-20230512T150617" \
  --ec2-attributes '{"InstanceProfile":"final-ec2-role-v1","EmrManagedMasterSecurityGroup":"sg-0cadc6a6c8c53ba3b","EmrManagedSlaveSecurityGroup":"sg-05cd6641948da8a1a","KeyName":"secondec2kpname","AdditionalMasterSecurityGroups":[],"AdditionalSlaveSecurityGroups":[],"SubnetId":"subnet-0046b7de766fb2451"}' \
  --tags 'for-use-with-amazon-emr-managed-policies=true' \
  --applications Name=Hadoop Name=Hive Name=Hue Name=Pig Name=Spark \
  --configurations '[{"Classification":"hive-site","Properties":{"hive.metastore.client.factory.class":"com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory"}},{"Classification":"spark-hive-site","Properties":{"hive.metastore.client.factory.class":"com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory"}}]' \
  --instance-groups '[{"InstanceCount":1,"InstanceGroupType":"MASTER","Name":"Primary","InstanceType":"m5.xlarge","EbsConfiguration":{"EbsBlockDeviceConfigs":[{"VolumeSpecification":{"VolumeType":"gp2","SizeInGB":32},"VolumesPerInstance":2}]}},{"InstanceCount":1,"InstanceGroupType":"CORE","Name":"Core","InstanceType":"m5.xlarge","EbsConfiguration":{"EbsBlockDeviceConfigs":[{"VolumeSpecification":{"VolumeType":"gp2","SizeInGB":32},"VolumesPerInstance":2}]}}]' \
  --scale-down-behavior "TERMINATE_AT_TASK_COMPLETION" \
  --auto-termination-policy '{"IdleTimeout":3600}' \
  --os-release-label "2.0.20230418.0" \
  --region "eu-central-1"

# next we need to SSH into the EMR cluster and submit our script for processing
spark-submit \
  --master yarn \
  --deploy-mode client \
  --name wcd-streaming-app \
  --jars /usr/lib/hudi/hudi-spark-bundle.jar,/usr/lib/spark/external/lib/spark-avro.jar \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.3.1 \
  --conf "spark.serializer=org.apache.spark.serializer.KryoSerializer" \
  --conf "spark.sql.hive.convertMetastoreParquet=false" \
  s3://dianaawsbucketwcd1/code/pyspark_job_v4.py \
  --msk_bootstrap_servers "<b-...,b-...,b-...>" \
  --kafka_topic "dbserver1.project.WeatherData2" \
  --s3_path "s3://bus-service-wcd-eu-west-1-diana/msk/openweather" \
  --data_schema "s3://dianaawsbucketwcd1/code/new_weather_schema.json"
