# pip3 install neo4j
# python3 example.py

from neo4j import GraphDatabase, basic_auth

driver = GraphDatabase.driver(
  "neo4j://<HOST>:<BOLTPORT>",
  auth=basic_auth("<USERNAME>", "<PASSWORD>"))

cypher_query = '''
MATCH (dc:DataCenter {location: $location})-[:CONTAINS]->(r:Router)-[:ROUTES]->(i:Interface)
RETURN i.ip as ip
'''

with driver.session(database="neo4j") as session:
  results = session.read_transaction(
    lambda tx: tx.run(cypher_query,
                      location="Iceland").data())
  for record in results:
    print(record['ip'])

driver.close()
