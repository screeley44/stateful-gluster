# gluster-statefulset
This example is initial development and research that utilizes the following:
- https://github.com/gluster/gluster-containers
- https://hub.docker.com/r/gluster/gluster-centos/
- AWS EC2




# Initial Experimentation Results
1. After initial cluster is running (make sure to give it time for liveness probe initial delay), check the TSP
```
  # oc get pods -o wide
NAME                       READY     STATUS    RESTARTS   AGE       IP             NODE
glusterfs-0                1/1       Running   0          4m        172.18.7.126   ip-172-18-7-126.ec2.internal
glusterfs-1                1/1       Running   0          4m        172.18.6.186   ip-172-18-6-186.ec2.internal
glusterfs-2                1/1       Running   0          3m        172.18.2.177   ip-172-18-2-177.ec2.internal

  # oc rsh glusterfs-0
sh-4.2# gluster peer status
Number of Peers: 2

Hostname: glusterfs-1.glusterfs.default.svc.cluster.local
Uuid: d77f225f-14f9-4028-9ed1-02eff28cbc4c
State: Peer in Cluster (Connected)

Hostname: glusterfs-2.glusterfs.default.svc.cluster.local
Uuid: 19c08924-19f1-4160-a67b-048ed3de4b4a
State: Peer in Cluster (Connected)

```

2. Next check if the volumes were created (only if the CREATE_VOLUMES switch was flipped in the StatefulSet) 
```
sh-4.2# gluster volume info
 
Volume Name: glusterfs-data0
Type: Replicate
Volume ID: 70610ade-2782-435f-a1b4-50d7f081da38
Status: Started
Snapshot Count: 0
Number of Bricks: 1 x 3 = 3
Transport-type: tcp
Bricks:
Brick1: glusterfs-0.glusterfs.default.svc.cluster.local:/mnt/storage/glusterfs-data0/brick0
Brick2: glusterfs-1.glusterfs.default.svc.cluster.local:/mnt/storage/glusterfs-data0/brick0
Brick3: glusterfs-2.glusterfs.default.svc.cluster.local:/mnt/storage/glusterfs-data0/brick0
Options Reconfigured:
transport.address-family: inet
nfs.disable: on
```

3. Check replication is working - create a file on one of the mounted storage pools
```
Login to any of the GFS pods
# oc rsh glusterfs-0

sh-4.2# mount | grep fuse
glusterfs-0.glusterfs.default.svc.cluster.local:glusterfs-data0 on /mnt/glusterfs-storage/glusterfs-data0 type fuse.glusterfs (rw,relatime,user_id=0,group_id=0,default_permissions,allow_other,max_read=131072)

sh-4.2# cd /mnt/glusterfs-storage/glusterfs-data0/
sh-4.2# touch myfile.txt
sh-4.2# exit

Login to another GFS pod
# oc rsh glusterfs-2

sh-4.2# cd /mnt/glusterfs-storage/glusterfs-data0/
sh-4.2# ls
myfile.txt
sh-4.2# exit
```



4.  Scale Up the cluster and again, check status of TSP and make sure pods are running, also check the volume info and replication
    with the new node.
```
# oc scale statefulset glusterfs --replicas=4
statefulset "glusterfs" scaled

# oc get pods -o wide
NAME                      READY     STATUS    RESTARTS   AGE       IP              NODE
glusterfs-0               1/1       Running   0          17m       172.18.7.178    ip-172-18-7-178.ec2.internal
glusterfs-1               1/1       Running   0          16m       172.18.9.67     ip-172-18-9-67.ec2.internal
glusterfs-2               1/1       Running   0          15m       172.18.11.126   ip-172-18-11-126.ec2.internal
glusterfs-3               1/1       Running   0          9m        172.18.9.44     ip-172-18-9-44.ec2.internal

# oc rsh glusterfs-0
sh-4.2# gluster volume info
 
Volume Name: glusterfs-data0
Type: Replicate
Volume ID: 1ef999b2-aa66-49c9-80cc-912a37e0c3a4
Status: Started
Snapshot Count: 0
Number of Bricks: 1 x 4 = 4
Transport-type: tcp
Bricks:
Brick1: glusterfs-0.glusterfs.default.svc.cluster.local:/mnt/storage/glusterfs-data0/brick0
Brick2: glusterfs-1.glusterfs.default.svc.cluster.local:/mnt/storage/glusterfs-data0/brick0
Brick3: glusterfs-2.glusterfs.default.svc.cluster.local:/mnt/storage/glusterfs-data0/brick0
Brick4: glusterfs-3.glusterfs.default.svc.cluster.local:/mnt/storage/glusterfs-data0/brick0
Options Reconfigured:
transport.address-family: inet
nfs.disable: on

Login to newest container and see if the file created on glusterfs-0 is replicated
# oc rsh glusterfs-3
sh-4.2# cd /mnt/glusterfs-storage/glusterfs-data0/
sh-4.2# ls
myfile.txt

```
*Note that the cluster TSP and replica count and volume bricks should have scaled up and the TSP will have each member from any of the pods
*Alost notice that Brick4 was created and joined the pool, and replicas are 1 X 4

5.  Scale down, similar to above
```
  # oc scale statefulsets glusterfs --replicas=3
statefulset "glusterfs" scaled

  # oc get pods -o wide
NAME                       READY     STATUS    RESTARTS   AGE       IP             NODE
glusterfs-0                1/1       Running   0          13m       172.18.7.126   ip-172-18-7-126.ec2.internal
glusterfs-1                1/1       Running   0          12m       172.18.6.186   ip-172-18-6-186.ec2.internal
glusterfs-2                1/1       Running   0          12m       172.18.2.177   ip-172-18-2-177.ec2.internal

  # oc rsh glusterfs-1
sh-4.2# gluster peer status
Number of Peers: 2

Hostname: glusterfs-0.glusterfs.default.svc.cluster.local
Uuid: edb18957-b7f5-468d-baf8-19e0e02d20c7
State: Peer in Cluster (Connected)

Hostname: glusterfs-2.glusterfs.default.svc.cluster.local
Uuid: 19c08924-19f1-4160-a67b-048ed3de4b4a
State: Peer in Cluster (Connected)

 # oc scale statefulset glusterfs --replicas=3
statefulset "glusterfs" scaled

 # oc get pods -o wide
NAME                      READY     STATUS    RESTARTS   AGE       IP              NODE
glusterfs-0               1/1       Running   0          30m       172.18.9.67     ip-172-18-9-67.ec2.internal
glusterfs-1               1/1       Running   0          29m       172.18.7.178    ip-172-18-7-178.ec2.internal
glusterfs-2               1/1       Running   0          28m       172.18.9.44     ip-172-18-9-44.ec2.internal

 # oc rsh glusterfs-2
sh-4.2# gluster volume info
 
Volume Name: glusterfs-data0
Type: Replicate
Volume ID: b1ebd63b-f02c-4cb1-ac5d-0bcabe9efa28
Status: Started
Snapshot Count: 0
Number of Bricks: 1 x 3 = 3
Transport-type: tcp
Bricks:
Brick1: glusterfs-0.glusterfs.default.svc.cluster.local:/mnt/storage/glusterfs-data0/brick0
Brick2: glusterfs-1.glusterfs.default.svc.cluster.local:/mnt/storage/glusterfs-data0/brick0
Brick3: glusterfs-2.glusterfs.default.svc.cluster.local:/mnt/storage/glusterfs-data0/brick0
Options Reconfigured:
transport.address-family: inet
nfs.disable: on

```
*Note that the cluster TSP and replica count and volume bricks should have scaled down
*Alost notice that Brick4 was removed and replicas are 1 X 3 now!


6.  Delete a pod - do we recover?
```
  # oc scale statefulsets glusterfs --replicas=4
statefulset "glusterfs" scaled
  
  # oc get pods -o wide
NAME                       READY     STATUS    RESTARTS   AGE       IP             NODE
glusterfs-0                1/1       Running   0          18m       172.18.7.126   ip-172-18-7-126.ec2.internal
glusterfs-1                1/1       Running   0          17m       172.18.6.186   ip-172-18-6-186.ec2.internal
glusterfs-2                1/1       Running   0          17m       172.18.2.177   ip-172-18-2-177.ec2.internal
glusterfs-3                1/1       Running   0          3m        172.18.3.111   ip-172-18-3-111.ec2.internal

  # oc rsh glusterfs-0
sh-4.2# gluster peer status
Number of Peers: 3

Hostname: glusterfs-1.glusterfs.default.svc.cluster.local
Uuid: d77f225f-14f9-4028-9ed1-02eff28cbc4c
State: Peer in Cluster (Connected)

Hostname: glusterfs-2.glusterfs.default.svc.cluster.local
Uuid: 19c08924-19f1-4160-a67b-048ed3de4b4a
State: Peer in Cluster (Connected)

Hostname: glusterfs-3.glusterfs.default.svc.cluster.local
Uuid: 55fff684-b838-4679-b590-cc5388148c8d
State: Peer in Cluster (Connected)
sh-4.2# exit


  # oc delete pod glusterfs-1
pod "glusterfs-1" deleted

  # oc get pods -o wide
NAME                       READY     STATUS    RESTARTS   AGE       IP             NODE
glusterfs-0                1/1       Running       0          21m       172.18.7.126   ip-172-18-7-126.ec2.internal
glusterfs-1                1/1       Terminating   0          20m       172.18.6.186   ip-172-18-6-186.ec2.internal
glusterfs-2                1/1       Running       0          20m       172.18.2.177   ip-172-18-2-177.ec2.internal
glusterfs-3                1/1       Running       0          6m        172.18.3.111   ip-172-18-3-111.ec2.internal

  # oc get pods -o wide
NAME                       READY     STATUS    RESTARTS   AGE       IP             NODE
glusterfs-0                1/1       Running   0          22m       172.18.7.126   ip-172-18-7-126.ec2.internal
glusterfs-1                1/1       Running   0          51s       172.18.6.186   ip-172-18-6-186.ec2.internal
glusterfs-2                1/1       Running   0          21m       172.18.2.177   ip-172-18-2-177.ec2.internal
glusterfs-3                1/1       Running   0          7m        172.18.3.111   ip-172-18-3-111.ec2.internal
```

*NOTE with the state being stored in a PVC, the peer rejected typically doesn't happen, if state is not stored in PVC but kept
      in hostPath then it will hit below status.  We should have a way to handle this condition if it does arise, although it shouldn't

```
  # oc rsh glusterfs-0
sh-4.2# gluster peer status
Number of Peers: 3

Hostname: glusterfs-1.glusterfs.default.svc.cluster.local
Uuid: d77f225f-14f9-4028-9ed1-02eff28cbc4c
State: Peer Rejected (Connected)

Hostname: glusterfs-2.glusterfs.default.svc.cluster.local
Uuid: 19c08924-19f1-4160-a67b-048ed3de4b4a
State: Peer in Cluster (Connected)

Hostname: glusterfs-3.glusterfs.default.svc.cluster.local
Uuid: 55fff684-b838-4679-b590-cc5388148c8d
State: Peer in Cluster (Connected)

```

7.  Bring a node down (in AWS set state to `stopped`), check state of the cluster


8.  Bring the cluster down (in AWS set state to `stopped`), wait some time and bring back up
All Good Here - have done this multiple times




