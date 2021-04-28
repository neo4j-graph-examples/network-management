// Add your the driver dependency to your pom.xml build.gradle etc.
// Java Driver Dependency: http://search.maven.org/#artifactdetails|org.neo4j.driver|neo4j-java-driver|4.0.1|jar
// Reactive Streams http://search.maven.org/#artifactdetails|org.reactivestreams|reactive-streams|1.0.3|jar
// download jars into current directory
// java -cp "*" Example.java

import org.neo4j.driver.*;
import static org.neo4j.driver.Values.parameters;

public class Example {

  public static void main(String...args) {

    Driver driver = GraphDatabase.driver("bolt://<HOST>:<BOLTPORT>",
              AuthTokens.basic("<USERNAME>","<PASSWORD>"));

    try (Session session = driver.session(SessionConfig.forDatabase("neo4j"))) {

      String cypherQuery =
        "MATCH (dc:DataCenter {location: $location})-[:CONTAINS]->(r:Router)-[:ROUTES]->(i:Interface)\n" +
        "RETURN i.ip as ip";

      var result = session.readTransaction(
        tx -> tx.run(cypherQuery, 
                parameters("location","Iceland"))
            .list());

      for (Record record : result) {
        System.out.println(record.get("ip").asString());
      }
    }
    driver.close();
  }
}


