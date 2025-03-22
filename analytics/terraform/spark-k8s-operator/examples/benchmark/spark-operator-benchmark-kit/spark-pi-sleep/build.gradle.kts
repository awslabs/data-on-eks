plugins {
    id("java")
}

group = "org.example"
version = "1.0-SNAPSHOT"


repositories {
    mavenCentral()
}

dependencies {
    // https://mvnrepository.com/artifact/org.apache.spark/spark-core
    implementation("org.apache.spark:spark-core_2.13:3.5.3")
    // https://mvnrepository.com/artifact/org.apache.spark/spark-sql
    compileOnly("org.apache.spark:spark-sql_2.13:3.5.3")


    testImplementation(platform("org.junit:junit-bom:5.10.0"))
    testImplementation("org.junit.jupiter:junit-jupiter")
}

tasks.test {
    useJUnitPlatform()
}
