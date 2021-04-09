#!/bin/sh

NAMESPACE="mongo"

echo "Configuring Config Server's & each Shard's Replica Sets"

kubectl exec mongod-configdb-0 -c mongod-configdb-container -- mongo --eval "rs.initiate({
  _id: 'ConfigDBReplicaSet',
  configsvr: true,
  version: 1,
  members: [
    {
      _id: 0,
      host: 'mongod-configdb-0.mongodb-configdb-service.$NAMESPACE.svc.cluster.local:27017',
      arbiterOnly: false,
      buildIndexes: true,
      hidden: false,
      priority: 1,
      slaveDelay: NumberLong(0),
      votes: 1
    },
    {
      _id: 1,
      host: 'mongod-configdb-1.mongodb-configdb-service.$NAMESPACE.svc.cluster.local:27017',
      arbiterOnly: false,
      buildIndexes: true,
      hidden: false,
      priority: 1,
      slaveDelay: NumberLong(0),
      votes: 1
    },
    {
      _id: 2,
      host: 'mongod-configdb-2.mongodb-configdb-service.$NAMESPACE.svc.cluster.local:27017',
      arbiterOnly: false,
      buildIndexes: true,
      hidden: false,
      priority: 1,
      slaveDelay: NumberLong(0),
      votes: 1
    }
  ],
  settings: {
    chainingAllowed: true,
    heartbeatIntervalMillis: 2000,
    heartbeatTimeoutSecs: 10,
    electionTimeoutMillis: 10000,
    catchUpTimeoutMillis: 2000,
    getLastErrorModes: {

    },
    getLastErrorDefaults: {
      w: 1,
      wtimeout: 0
    }
  }
});"


# ReplicaSet은 PSS(Primary-Secondary-Secondary)로 구성
for i in $(seq 1 3) ; do
  kubectl exec mongod-shard"${i}"-0 -c mongod-shard"${i}"-container -- mongo --eval "rs.initiate({
  _id: 'Shard${i}ReplicaSet',
  version: 1,
  configsvr: false,
  members: [
    {
      _id: 0,
      host: 'mongod-shard${i}-0.mongodb-shard${i}-service.$NAMESPACE.svc.cluster.local:27017',
      arbiterOnly: false,
      buildIndexes: true,
      hidden: false,
      priority: 1,
      slaveDelay: NumberLong(0),
      votes: 1
    },
    {
      _id: 1,
      host: 'mongod-shard${i}-1.mongodb-shard${i}-service.$NAMESPACE.svc.cluster.local:27017',
      arbiterOnly: false,
      buildIndexes: true,
      hidden: false,
      priority: 1,
      slaveDelay: NumberLong(0),
      votes: 1
    },
    {
      _id: 2,
      host: 'mongod-shard${i}-2.mongodb-shard${i}-service.$NAMESPACE.svc.cluster.local:27017',
      arbiterOnly: false,
      buildIndexes: true,
      hidden: false,
      priority: 1,
      slaveDelay: NumberLong(0),
      votes: 1
    }
  ],
  settings: {
    chainingAllowed: true,
    heartbeatIntervalMillis: 2000,
    heartbeatTimeoutSecs: 10,
    electionTimeoutMillis: 10000,
    catchUpTimeoutMillis: 2000,
    getLastErrorModes: {

    },
    getLastErrorDefaults: {
      w: 1,
      wtimeout: 0
    }
  }
});"
done

echo
