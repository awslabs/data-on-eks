Run the *taxi-trip-execute.sh* script with the following input. You will use the *S3_BUCKET* variable created earlier. Additionally, you must change YOUR_REGION_HERE with the region of your choice, *us-west-2* for example.

This script will download some example taxi trip data and create duplicates of
it in order to increase the size a bit. This will take a bit of time and will
require a relatively fast internet connection.

```bash
cd ${DOEKS_HOME}/analytics/scripts/
chmod +x taxi-trip-execute.sh
./taxi-trip-execute.sh ${S3_BUCKET} YOUR_REGION_HERE
```

You can return to the blueprint directory and continue with the example
```bash
cd ${DOEKS_HOME}/analytics/terraform/spark-k8s-operator
```
