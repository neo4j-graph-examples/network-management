// Data Center

CREATE (dc:DataCenter {name:"DC1",location:"Iceland, Rekjavik"})-[:CONTAINS]->(re:Router:Egress {name:"DC1-RE"})
CREATE (re)-[:ROUTES]->(:Interface {ip:"10.0.0.254"});

// Zones
// The datacenter consists of 4 zones, each of which has it's own separate `Network` `10.zone.*/16`, and it's own `Router`.


WITH 4 AS zones
MATCH (dc:DataCenter {name:"DC1"})-[:CONTAINS]->(re:Router:Egress)-[:ROUTES]->(rei:Interface)

// for each zone
WITH * UNWIND range(1,zones) AS zid

// create zone network
CREATE (nr:Network:Zone {ip:"10."+zid, size: 16, zone:zid})<-[:CONNECTS]-(rei)

// create router in DC, connect it via an interface to the zone network
CREATE (dc)-[:CONTAINS]->(r:Router {name:"DC1-R-"+zid, zone:zid})-[:ROUTES]->(ri:Interface {ip:nr.ip+".0.254"})-[:CONNECTS]->(nr);


// Racks

WITH 10 as racks
MATCH (dc:DataCenter {name:"DC1"})
MATCH (nr:Network:Zone) // one per zone

WITH * UNWIND range(1,racks) AS rackid

CREATE (dc)-[:CONTAINS]->(rack:Rack {name:"DC1-RCK-"+nr.zone+"-"+rackid, rack:rackid, zone:nr.zone})-[:HOLDS]->(s:Switch {ip:nr.ip+"."+rackid, rack:rackid})-[:ROUTES]->(si:Interface {ip:s.ip+".254"})<-[:ROUTES]-(nr);

// Machine types

// Similar to the machines you can rent on AWS we use machine types, for which we auto-create some reasonable capacities for CPU, RAM and DISK.

WITH ["xs","s","m","l","xl","xxl"] as typeNames
UNWIND range(0,size(typeNames)-1) as idx
CREATE (t:Type {id:idx, cpu: toInteger(2^idx), ram:toInteger(4^idx), disk:toInteger(5^idx), type: typeNames[idx]}) 
   SET t.name = typeNames[idx]+"-"+t.cpu + "/"+t.ram+"/"+t.disk
RETURN t.name, t.id, t.cpu, t.ram, t.disk;


// Machines

// Each Rack contains 200 machines of the types we just introduced, so that in total we get 8000 servers in our datacenter.
// The distribution of the types is inverse to their capabilities.

MATCH (t:Type)
WITH collect(t) as types, 200 as machines

MATCH (rack:Rack)-[:HOLDS]->(s:Switch)-[:ROUTES]->(si:Interface)

UNWIND (range(1,machines)) AS machineid

CREATE (rack)-[:HOLDS]->(m:Machine {id:rack.id * 1000 + machineid, name: rack.name + "-M-" +machineid })-[:ROUTES]->(i:Interface {ip:s.ip+"."+machineid})-[:CONNECTS]->(si)
WITH m,types,size(types)-toInteger(log(machines - machineid + 1)) -1 as idx
WITH m, types[idx] as t
CREATE (m)-[:TYPE]->(t);


// Create OS and Software

// https://en.wikipedia.org/wiki/Red_Hat_Enterprise_Linux#Version_history
// https://wiki.ubuntu.com/Releases
// https://en.wikipedia.org/wiki/Debian_version_history


WITH
     [{name:"RHEL",versions:["7.1","7.2","7.3"]},{name:"Ubuntu",versions:["14.04","16.04","16.10","17.04"]},{name:"Debian",versions:["6-Squeeze","7-Wheezy","8-Jessie"]}] as osNames,
     [
      {name:"java",versions:["8"]},
      {name:"neo4j",ports:[7474,7473,7687],versions:["3.0","3.1"],dependencies:["java/8"]},
      {name:"postgres",ports:[5432],versions:["9.4","9.5","9.6"]},
      {name:"couchbase",ports:[8091,8092,11207,11209,11210,11211,11214,11215,18091,18092,4369],versions:["3.0","4.0","4.5","4.6"]},
      {name:"elasticsearch",ports:[9200,9300,9500,9700],versions:["2.4","5.0","5.1","5.2"],dependencies:["java/8"]}
     ] as services,
     [{name:"webserver",ports:[80,443],dependencies:["postgres/9.4"]},
      {name:"crm",ports:[80,443],dependencies:["java/8","neo4j/3.1"]},
      {name:"cms",ports:[8080],dependencies:["php","webserver","couchbase"]},
      {name:"webapp",ports:[8080],dependencies:["java","neo4j"]},
      {name:"logstash",ports:[5000],dependencies:["elasticsearch/5.2"]}
     ] as applications

UNWIND osNames + services + applications AS sw

CREATE (s:Software) SET s = sw
FOREACH (sw in [x IN osNames where x.name = sw.name | x] | SET s:OS)
FOREACH (sw in [x IN services where x.name = sw.name | x] | SET s:Service)
FOREACH (sw in [x IN applications where x.name = sw.name | x] | SET s:Application)

FOREACH (idx in range(0,size(coalesce(sw.versions,[]))-2) | 
  MERGE (s)-[:VERSION]->(v0:Version {name:sw.versions[idx]})
  MERGE (s)-[:VERSION]->(v:Version {name:sw.versions[idx+1]})
  MERGE (v0)<-[:PREVIOUS]-(v)
)
WITH *
UNWIND sw.dependencies as dep
WITH *,split(dep,"/") as parts
MERGE (d:Software {name:parts[0]})
FOREACH (v IN case size(parts) when 1 then [] else [parts[1]] end |
   MERGE (d)-[:VERSION]->(:Version {name:v})
)
WITH *
OPTIONAL MATCH (d)-[:VERSION]->(v:Version {name:parts[1]})
WITH s, coalesce(v,d) as d
MERGE (s)-[:DEPENDS_ON]->(d);


// Install Software

create index on :Software(name);

WITH [(:Software:OS)-[:VERSION]->(v) | v] as osVersions
MATCH (a:Application:Software)
WITH osVersions, collect(a) as apps
MATCH (m:Machine)-[:ROUTES]->(i:Interface)
WITH m,i, osVersions[toInteger(rand()*size(osVersions))] as os, apps[toInteger(rand()*size(apps))] as app
CREATE (m)-[:RUNS]->(op:OS:Process {name:os.name, startTime:timestamp() - toInteger( (rand() * 10 + 5) *24*3600*1000)})-[:INSTANCE]->(os)
CREATE (m)-[:RUNS]->(ap:Application:Process {name: app.name, pid: toInteger(rand()*10000), startTime:timestamp() - toInteger(rand() * 10*24*3600*1000) })-[:INSTANCE]->(app)

FOREACH (portNo in app.ports |
   MERGE (port:Port {port:portNo})<-[:EXPOSES]-(i)
   CREATE (ap)-[:LISTENS]->(port)
)
WITH *
MATCH (app)-[:DEPENDS_ON]->(dep)
CREATE (m)-[:RUNS]->(dp:Service:Process {name: dep.name, pid: toInteger(rand()*10000), startTime:timestamp() - toInteger(rand() * 10*24*3600*1000) })-[:INSTANCE]->(dep)
CREATE (ap)-[:DEPENDS_ON]->(dp)
FOREACH (portNo in dep.ports |
   MERGE (port:Port {port:portNo})<-[:EXPOSES]-(i)
   CREATE (dp)-[:LISTENS]->(port)
);