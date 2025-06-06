#!/bin/bash
# Graylog GELF input tester
GRAYLOG_INPUT="http://localhost:12201"

while true
do
    NUMBER=$RANDOM
    echo "Number: $NUMBER"
    curl -XPOST ${GRAYLOG_INPUT}/gelf -p0 -d '{"short_message":"Hello there: '${NUMBER}'", "host":"example.org", "facility":"test", "_foo":"bar"}'
    sleep 10
done
