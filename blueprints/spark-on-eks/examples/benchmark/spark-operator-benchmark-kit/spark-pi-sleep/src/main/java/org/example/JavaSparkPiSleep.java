package org.example;

import org.apache.spark.api.java.JavaRDD;
import org.apache.spark.api.java.JavaSparkContext;
import org.apache.spark.sql.SparkSession;

import java.lang.Thread;
import java.util.ArrayList;
import java.util.List;


public final class JavaSparkPiSleep {

    public static void main(String[] args) throws Exception {
        SparkSession spark = SparkSession
                .builder()
                .appName("JavaSparkPiSleep")
                .getOrCreate();

        JavaSparkContext jsc = new JavaSparkContext(spark.sparkContext());

        int slices = (args.length > 0) ? Integer.parseInt(args[0]) : 2;
        List<Integer> l = new ArrayList<>(slices);
        for (int i = 0; i < slices; i++) {
            l.add(i);
        }

        int sleepMilliSeconds = (args.length > 1) ? Integer.parseInt(args[1]) * 1000 : 1000;

        JavaRDD<Integer> dataSet = jsc.parallelize(l, slices);

        int count = dataSet.map(integer -> {
            System.out.println("Sleeping for " + sleepMilliSeconds + " milliseconds");
            Thread.sleep(sleepMilliSeconds);
            double x = Math.random() * 2 - 1;
            double y = Math.random() * 2 - 1;
            return (x * x + y * y <= 1) ? 1 : 0;
        }).reduce((integer, integer2) -> integer + integer2);

        System.out.println("Pi is roughly " + 4.0 * count / slices);

        spark.stop();
    }
}
