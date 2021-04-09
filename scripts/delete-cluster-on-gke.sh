#!/bin/sh
##
# Script to remove/undepoy all project resources from GKE & GCE.
##

ZONE="asia-northeast3-a"

# Delete mongos stateful set + mongod stateful set + mongodb service + secrets + host vm configurer daemonset
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
kubectl delete secret shared-bootstrap-data
kubectl delete daemonset hostvm-configurer
sleep 3

# Delete Config Map
kubectl delete cm cm-mongo-configdb
kubectl delete cm cm-mongo-router
for i in 1 2 3
do
    kubectl delete cm cm-mongo-shard$i
done

# Delete persistent volume claims
kubectl delete persistentvolumeclaims -l tier=maindb
kubectl delete persistentvolumeclaims -l tier=configdb
sleep 3


# Delete persistent volumes
for i in 1 2 3
do
    kubectl delete persistentvolumes data-volume-15g-$i
done
for i in 1 2 3 4 5 6 7 8 9
do
    kubectl delete persistentvolumes data-volume-20g-$i
done
sleep 20

# Delete GCE disks
for i in 1 2 3
do
    gcloud -q compute disks delete pd-ssd-disk-15g-$i --zone=$ZONE
done
for i in 1 2 3 4 5 6 7 8 9
do
    gcloud -q compute disks delete pd-ssd-disk-20g-$i --zone=$ZONE
done

# gcloud -q container clusters delete "<CLUSTER_NAME>"

