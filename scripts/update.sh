#!/bin/sh

kubectl delete statefulsets mongos-router
kubectl delete services mongos-router-service
kubectl delete statefulsets mongod-shard1
kubectl delete services mongodb-shard1-service
kubectl delete statefulsets mongod-shard2
kubectl delete services mongodb-shard2-service
kubectl delete statefulsets mongod-shard3
kubectl delete services mongodb-shard3-service
kubectl delete statefulsets mongod-configdb
kubectl delete services mongodb-configdb-service

kubectl delete cm cm-mongo-configdb
kubectl delete cm cm-mongo-router

for i in 1 2 3
do
    kubectl delete cm cm-mongo-shard$i
done

sleep 30

echo
echo "[GKE] 각각의 mongo 인스턴스 설정 ConfigMap 을 생성합니다."
kubectl create cm cm-mongo-configdb --from-file=../resources/conf/mongo-configdb.conf
for i in $(seq 1 3);
do
  kubectl create cm cm-mongo-shard"${i}" --from-file=../resources/conf/mongo-shard"${i}".conf
done
kubectl create cm cm-mongo-router --from-file=../resources/conf/mongo-router.conf

kubectl apply -f ../resources/mongodb-configdb-service.yaml
echo
for i in $(seq 1 3);
do
  sed -e "s/shardX/shard${i}/g; s/ShardX/Shard${i}/g" ../resources/mongodb-maindb-service.yaml > ../resources/shard/mongodb-maindb-service"${i}".yaml
  kubectl apply -f ../resources/shard/mongodb-maindb-service"${i}".yaml
done
rm -f ../resources/shard/mongodb-maindb-service*.yaml
kubectl apply -f ../resources/mongodb-mongos-service.yaml
