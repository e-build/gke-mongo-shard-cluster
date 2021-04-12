# Passmate MongoDB Sharded Cluster on GKE 

## 구동

### 1. 사전 작업

다음 라이브러리들이 작업환경에 사전에 정의되어 있어야 합니다.

1. 원하는 노드사양으로 정의된 Cluster가 생성되어 있어야 합니다. 
2. GCP’s client CLI 툴인 [gcloud](https://cloud.google.com/sdk/docs/quickstarts) SDK가 로컬의 작업환경에 설치되어 있어야 합니다.  
3. 작업 프로젝트 설정 및 접속을 위해 다음 과정과 같은 gcloud 초기화가 필요합니다.
4. kubectl을 사용하여 구축을 진행합니다. MongoDB를 구축하고자하는 클러스터의 컨텍스트에 대한 접근 권한이 필요합니다.

    ```
    $ gcloud init
    $ gcloud components install kubectl
    $ gcloud auth application-default login
    $ gcloud config set compute/zone < GKE cluster Zone to create >
    ```

**Note:** 사용가능한 zone 리스트를 먼저 확인<br> `$ gcloud compute zones list`


### 2. Deployment

    $ cd scripts
    $ ./generate.sh

### 2.1 배포 과정
   1. hostvm 생성. (Disabling Transparent Huge Pages(THP) to improve performance) 
   2. Google Compute Engine disk 생성 (config*3, shard*3*3)
   3. 2에서 생성한 disk로 GKE Persistent Volume 생성 (XFS filesystem)
   4. 몽고 클러스터 간 내부인증을 위한 secret 생성
   5. 설정 관리를 위한 ConfigMap 생성
   6. configDB 생성
   7. shardDB 생성
   8. router 생성
   9. configDB, shardDB ReplicaSet 초기화
   10. router 에 샤드 추가
   11. router 접속하여 passmate admin 계정 생성
   12. loadBanlancer 생성


### 2.2 배포 확인
[Google Cloud Platform Console](https://console.cloud.google.com)에서 배포가 정상적으로 되었는 지 확인할 수 있으며, 구동중인 mongos 라우터를 통해서 같은 k8s 클러스터 내에서 돌고 있는 "app tier" 컨테이너 어느 것에나 접근할 수 있습니다. 


   ```
   $ kubectl get all
   $ kubectl get pods
   $ kubectl exec -it svc/mongos-router-service -- mongo -u mongo-admin
   > sh.status()
   ```

### 3. 컬렉션 샤딩 테스트

샤드 클러스터가 정상적으로 동작하는 지 확인하기 위해서 router에 접속합니다. 이전에 생성한 관리자 계정으로 접속하고 특정 컬렉션을 대상으로 아래의 방법을 통해 샤딩을 진행합니다.
해당 컬렉션에 테이트 데이터를 삽입하고 상태를 확인합니다.

    $ kubectl exec -it mongos-router-0 -c mongos-container bash
    $ mongo
    > db.getSiblingDB('admin').auth("mongo-admin", "mongo-admin-password");
    > sh.enableSharding("test");
    > sh.shardCollection("test.testcoll", {"myfield": 1});
    > use test;
    > db.testcoll.insert({"myfield": "a", "otherfield": "b"});
    > db.testcoll.find();
    > sh.status();

### 4. GKE 내리고 삭제하기 

**Important:** GKE 구성요소 뿐만 아니라 compute disks 도 함께 삭제하기 때문에 기존 mongoDB의 데이터들을 백업한 이후 진행하시는 것이 좋습니다.
GKE의 일부 resource만 제거길 원한다면 delete-cluster-on-gke.sh 스크립트를 참고해주세요.

    $ ./delete.sh

완전히 제거되었는 지 여부는 [Google Cloud Platform Console](https://console.cloud.google.com) 에서 확인할 수 있습니다.

