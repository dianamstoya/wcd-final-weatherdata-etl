# Streaming weather data pipeline

## Overview

This project implements a data pipeline (ETL), using OpenWeather's API (https://api.openweathermap.org) to stream weather data for a specific location. The architecture uses Apache Kafka and Spark Structure Streaming. The data is visualized with Microsoft Power BI.

## Architecture

The architecture uses the following technologies (listed in order):

1. OpenWeather's API
2. Apache Nifi to convert the API response data and write to MySQL (running on Docker in AWS EC2)
3. MySQL database instance (running on Docker with AWS EC2)
4. AWS MSK (Kafka streaming)
5. AWS S3 as storage for the data (in HUDI format)
6. AWS Athena as analytics engine on top of the data
7. Microsoft Power BI to read the data from Athena and visualize it

## Files included in repository

The following files have been included in the repository:

- bash scripts for creating the necessary resources on EC2 and AWS
- Nifi flow
- pyspark script
- Power BI dashboard

## Additional notes

The schedule for the Nifi flow is every 61 seconds. The API provides data every 60 seconds, although the weather station frequency is less than that (aka actual measurements occur at less frequent interval). The Power BI dashboard uses DirectQuery which is a type of live connection to the Athena table that allows for near realtime data to be visualized.
 