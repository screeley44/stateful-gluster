# gluster-statefulset
This example is initial development and research that utilizes the following:
- https://github.com/gluster/gluster-containers
- https://hub.docker.com/r/gluster/gluster-centos/
- AWS EC2

# The Goal
- Develop a StatefulSet that can dynamically scale and manage the Trusted Storage Pool, Volumes and Bricks to prove distributed replication between pods
- Develop an initial script to help facilitate the PoC
- Be self healing and aware of changes to the cluster and recover from such events
- Utilize K8 primitives (lifecycle and liveness hooks)
- Use PersistentVolumes and PersistentVolumeClaims
- Use StorageClasses for Dynamic volumes, bricks and maintaining state of GlusterFS pods
- Treat GlusterFS as any other Kubernetes like application that can bounce around between nodes, 
  scale up and down and maintain state

# Non-Goals
- Do not create anything complicated in terms of CRD, Kuberentes Operators or other external/internal code added to kubernetes, just simple proof of concept using simple bash

# Phase 1 Status - Initializing and Managing TSP
- [x] Create running and healthy GlusterFS StatefulSet
- [x] Create initial Trusted Storage Pool
- [x] Happy Path - Scale Up and Down with Trusted Storage Pool intact
- [x] Recovery - delete a pod, should recover
- [x] Recovery - stop a node, pod should go to next available node with TSP intact
- [x] Recovery - stop the cluster

# Phase 2 Status - Phase 1 + Create Volumes and Bricks
- [x] Create Trusted Storage Pool AND Initial Volume with Bricks
- [x] Verify replication is working on initial GFS cluster
- [x] Scale Up, does the volume expand to the new node and GFS pod
- [ ] Scale Down, does the volume shrink to the new number of replicas
- [ ] TSP and Volume/Brick/Replication All Good?

# Phase 3 Status - Using the Solution
- [ ] Can I create pods that use the solution?
- [ ] Can I dynamically provision clusters or volumes?
- [ ] General Investigation

# Phase 4 Status - Experimenting with different approaches
- [ ] Investigate Kube Operators?
- [ ] Investigate CRD?
- [ ] Investigate 3rdParty Resources
- [ ] Investigate specialized plugins/provisioners (external or internal)
- [ ] Investigate replacing shell script functionality with other technology

# The Recipe
1. all-in-one yaml file that includes
- storageclass definition
- headless service
- statefulset definition

2. liveness probe script (gluster-post.sh).
- liveness probe will execute 2 minutes after a pod is running and then every 30 seconds (these can be adjusted).
- script should be able to figure out state of the cluster and take appropriate action.
- nodes are workers, so when a new pod is added (scaled up) one of the existing nodes will pick up
  on this and add to the TSP.  Same is true of scaling down
- TBD: What about failure recovery (pod is killed by user, node goes down, etc...)

3. lifecycle mgmt probe - preStop hook
- The idea behind this is before a pod is terminated we can remove from the TSP - the liveness probe does that today
  but wondering about what happens when a pod is killed by a user - not sure the liveness probe can recover from that


# Potential and Real Issues
1. Node goes down, since Statefulsets keep consistent DNS naming (but not guaranteed IPs - although, so far it seems they are mostly retained)
   when we bring the node back up OR bring up a new node in it's place, what happens with the TSP?

2. Best way to handle the `peer rejected` status, which happens when you delete a pod outside of the normal healthy scale up or down.
- We could maybe use a lifecycle hook for preStop which fires before termination to remove from TSP and let the normal liveness probe add back in
- Add another condition to our liveness probe to remedy the situation (about 6 steps)
- (Resolved) storing glusterfs state in PV/PVC model seems to eliminate this risk

3. Currently using hostNetwork - will this be an issue or is this expected that we use that? The pods couldn't communicate with each
   other when I didn't use hostNetwork. Maybe could remedy this by tweaking something, just not sure what?

4. Deploying and using a bash script to manage GlusterFS is not ideal, need to investigate more industry hardened techniques
- Next steps should we use Golang or some other language to have more powerful control and features?
- Does CustomResourceDefinitions (CRD) handle this type of stuff?
- Another 3rdParty type of resource to handle gluster-post.sh?

5. This is cool, that we can easily and quickly deploy a distributed and replicated glusterfs set across our nodes, and easily scale up and down, but it
   doesn't address how to use this dynamically? Is the approach (which might be fine), that each user requests and/or deploys their own StatefulSet
   essentially owning and deploying their own gluster cluster? If they choose to share it, meaning allow other users and pods to connect to their existing
   PV and PVCs then that is fine, but a user can't easily request dynamic provisioning of glusterfs volume (like current model pvc --> storageclass --> pv).
   But again, to use this, it needs to be deployed and then pvc's given to other users/pods to use.
- Could an provisioner/plugin automatically generate a custom cluster per user request? Meaning automatically deploy a GFS cluster on the fly incorporating
  this statefulset experimentation. So rather than just creating a single volume per cluster when a user requests storage, we would have a single cluster with
  it's own TSP...kinda interesting to think about it this way??

6. Can we have multiple GFS clusters running as their own StatefulSets in a single OCP/Kube cluster?

7. When resizing/scaling do we delete bricks and volumes?  How best to do that?


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

```

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




