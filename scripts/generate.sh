#!/bin/sh
##
# Script to deploy a Kubernetes project with a StatefulSet running a MongoDB Sharded Cluster, to GKE.
##

NEW_PASSWORD="mongo-admin-password"
ZONE="asia-northeast3-a"
NAMESPACE="mongo"

# namespace 생성

# 1. 데몬셋으로 hostVM 의 hugepages 사용을 disable 하도록 사전 설정
echo "[GKE] hostvm-node-configurer-daemonset 배포를 시작합니다.................."
kubectl apply -f ../resources/hostvm-node-configurer-daemonset.yaml

#kubectl apply -f ../resources/gce-ssd-storageclass.yaml

# 2. GCE SSD 영구 디스크를 생성
echo
echo "[GCE] GCE disks 를 생성합니다.................."
# 2.1. ConfigDB X 3
for i in $(seq 1 3)
do
    gcloud compute disks create --size 15GB --type pd-ssd --zone $ZONE pd-ssd-disk-15g-$i
done
# 2.2. ShardDB X 3 X 3
for i in $(seq 1 9)
do
    gcloud compute disks create --size 20GB --type pd-ssd --zone $ZONE pd-ssd-disk-20g-$i
done
sleep 3

# 3. Persistent Volume 생성. 위에서 생성한 디스크를 이용하여. File System : XFS
echo
echo "[GKE] Persistent Volumes을 생성합니다. "
for i in $(seq 1 3)
do
    sed -e "s/INST/${i}/g; s/SIZE/15/g" ../resources/xfs-gce-ssd-persistentvolume.yaml > /tmp/xfs-gce-ssd-persistentvolume.yaml
    kubectl apply -f /tmp/xfs-gce-ssd-persistentvolume.yaml
done
for i in $(seq 1 9)
do
    sed -e "s/INST/${i}/g; s/SIZE/20/g" ../resources/xfs-gce-ssd-persistentvolume.yaml > /tmp/xfs-gce-ssd-persistentvolume.yaml
    kubectl apply -f /tmp/xfs-gce-ssd-persistentvolume.yaml
done
rm /tmp/xfs-gce-ssd-persistentvolume.yaml
sleep 3

# 4. 샤드 클러스터 몽고서버 간 인증을 위한 Keyfile 생성. secret
echo
echo "[GKE] Keyfile 생성하여 GKE secret을 생성합니다. "
if [ -d ../resourcs/keyfile ];
then
  mkdir ../resources/keyfile
fi
touch ../resources/keyfile/internal-auth-mongodb-keyfile
/usr/bin/openssl rand -base64 741 > ../resources/keyfile/internal-auth-mongodb-keyfile
kubectl create secret generic shared-bootstrap-data --from-file=../resources/keyfile/internal-auth-mongodb-keyfile
rm -f ../resources/keyfile/internal-auth-mongodb-keyfile

# 5. ConfigMap 생성. mongod 컨테이너에 각각 적용
echo
echo "[GKE] 각각의 mongo 인스턴스 설정 ConfigMap 을 생성합니다."
kubectl create cm cm-mongo-configdb --from-file=../resources/conf/mongo-configdb.conf
for i in $(seq 1 3);
do
  kubectl create cm cm-mongo-shard"${i}" --from-file=../resources/conf/mongo-shard"${i}".conf
done
kubectl create cm cm-mongo-router --from-file=../resources/conf/mongo-router.conf

# 6. ConfigDB StatefulSet(replica 3) 으로 배포
echo
echo "[GKE] GKE StatefulSet & Service 배포합니다. :: Config Server "
kubectl apply -f ../resources/mongodb-configdb-service.yaml

# 7. ShardDB StatefulSet(replica 3) 으로 배포 X 3
echo
echo "[GKE] GKE StatefulSet & Service 배포합니다. :: Shard Server "
for i in $(seq 1 3);
do
  sed -e "s/shardX/shard${i}/g; s/ShardX/Shard${i}/g" ../resources/mongodb-maindb-service.yaml > ../resources/shard/mongodb-maindb-service"${i}".yaml
  kubectl apply -f ../resources/shard/mongodb-maindb-service"${i}".yaml
done
rm -f ../resources/shard/mongodb-maindb-service*.yaml

# 배포 완료까지 대기
echo
echo "[GKE] Shard & Config Pod 이 생성될 때까지 대기합니다. ($(date))..."
echo " (not found & connection errors 무시하고 기다립니다.)"
sleep 30
echo -n "  "
until kubectl --v=0 exec mongod-configdb-2 -c mongod-configdb-container -- mongo --quiet --eval 'db.getMongo()';
do
    sleep 5
    echo -n "  "
done

for i in $(seq 1 3);
do
  echo -n "  "
  until kubectl --v=0 exec mongod-shard"${i}"-2 -c mongod-shard"${i}"-container -- mongo --quiet --eval 'db.getMongo()'; do
      sleep 5
      echo -n "  "
  done
done
echo "configdb & shards containers are now running ($(date))"


# 8. Config 서버와 각 Shard 서버들 ReplicaSet 으로 초기화
sh ./init-replicaset.sh

# ReplicaSet 으로 초기화 대기... TODO: 이거 왜 안되는 지 확인 필요
echo "Waiting for all the MongoDB ConfigDB & Shards Replica Sets to initialise..."
kubectl exec mongod-configdb-0 -c mongod-configdb-container -- mongo --quiet --eval 'while ( rs.status().hasOwnProperty("myState") ) { print("."); sleep(1000); };'
kubectl exec mongod-configdb-0 -c mongod-configdb-container -- mongo --quiet --eval 'while ( rs.status().hasOwnProperty("myState") ) { print("."); sleep(1000); };'
for i in $(seq 1 3) ;
do
  kubectl exec mongod-shard"${i}"-0 -c mongod-shard"${i}"-container -- mongo --quiet --eval 'while ( rs.status().hasOwnProperty("myState") ) { print("."); sleep(1000); };'
done
sleep 2
echo "MongoDB Replica Sets 초기화 완료"
echo

# 9. Router StatefulSet(replica 3) 으로 배포 TODO: mongo-router.conf 에서 configDB 호스트를 세팅하기 때문에 configDB 가 다 뜨고 나서 router를 띄워야 할지도 모르겠다.
echo
echo "[GKE] GKE StatefulSet & Service 배포합니다. :: Router Server "
kubectl apply -f ../resources/mongodb-mongos-service.yaml

echo "[GKE] Router 가 생성될 때까지 대기합니다. ($(date))..."
echo " (not found & connection errors 무시하고 기다립니다.)"
echo "..."
until kubectl --v=0 exec mongos-router-0 -c mongos-container -- mongo --quiet --eval 'db.getMongo()'; do
    sleep 2
    echo "..."
done
echo "first mongos is now running ($(date))"
echo

# 10. Router 에 Shard 등록
echo
echo "Configuring ConfigDB to be aware of the 3 Shards"
for i in $(seq 1 3) ;
do
  kubectl exec mongos-router-0 -c mongos-container -- mongo --eval "sh.addShard('Shard${i}ReplicaSet/mongod-shard${i}-0.mongodb-shard${i}-service.mongo.svc.cluster.local:27017');"
done
sleep 3

# 11. Admin root 계정 생성
echo
echo "Admin user 생성"
kubectl exec mongos-router-0 -c mongos-container -- mongo --eval 'db.getSiblingDB("admin").createUser({user:"mongo-admin",pwd:"${NEW_PASSWORD}",roles:[{role:"root",db:"admin"}]});'
echo

# 12. 로드밸런서 생성 (외부접속)
echo
echo "외부접속을 위한 로드밸런서 생성. 라우터와 연결"
kubectl apply -f ../resources/mongodb-loadbalancer.yaml

# Print Summary State
kubectl get pv
echo
kubectl get pvc
echo
kubectl get cm
echo
kubectl get secret
echo
kubectl get all
echo

