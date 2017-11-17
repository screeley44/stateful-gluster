# gluster-statefulset
This example is initial development and research that utilizes the following:
- https://github.com/gluster/gluster-containers
- https://hub.docker.com/r/gluster/gluster-centos/
- AWS EC2

# The Goal
- Develop a StatefulSet that can dynamically scale and manage the Trusted Storage Pool
- Be self healing and aware of changes to the cluster and recover from such events
- Utilize K8 primitives (lifecycle and liveness hooks)
- Use PersistentVolumes and PersistentVolumeClaims
- Use StorageClasses for Dynamic volumes, bricks and maintaining state of GlusterFS pods
- Treat GlusterFS as any other Kubernetes like application that can bounce around between nodes, 
  scale up and down and maintain state

# Non-Goals
- Do not create or manage volumes in this phase (see gluster-statefulset-cloud-with-volumes)

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

3. I'm using hostNetwork because the pods can't communicate with each other, so this gives me a hostname of the node in the container rather than
   the pod name as the hostname (i.e. ip-172-18-12-34.ec2.internal vs. glusterfs-2). This makes it hard to tie the pod name back to the host.
   If I could get that info, it would help with some recovery decisions.



# Experimentation
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

2.  Scale Up the cluster and again, check status of TSP and make sure pods are running
```
  # oc scale statefulsets glusterfs --replicas=5
statefulset "glusterfs" scaled

  # oc get pods -o wide
NAME                       READY     STATUS    RESTARTS   AGE       IP             NODE
glusterfs-0                1/1       Running   0          8m        172.18.7.126   ip-172-18-7-126.ec2.internal
glusterfs-1                1/1       Running   0          7m        172.18.6.186   ip-172-18-6-186.ec2.internal
glusterfs-2                1/1       Running   0          7m        172.18.2.177   ip-172-18-2-177.ec2.internal
glusterfs-3                1/1       Running   0          1m        172.18.3.111   ip-172-18-3-111.ec2.internal
glusterfs-4                1/1       Running   0          33s       172.18.9.66    ip-172-18-9-66.ec2.internal


  # oc rsh glusterfs-0
sh-4.2# gluster peer status
Number of Peers: 4

Hostname: glusterfs-1.glusterfs.default.svc.cluster.local
Uuid: d77f225f-14f9-4028-9ed1-02eff28cbc4c
State: Peer in Cluster (Connected)

Hostname: glusterfs-2.glusterfs.default.svc.cluster.local
Uuid: 19c08924-19f1-4160-a67b-048ed3de4b4a
State: Peer in Cluster (Connected)

Hostname: glusterfs-3.glusterfs.default.svc.cluster.local
Uuid: 54b7cfc0-965e-4e4e-8491-d86df62a66fc
State: Peer in Cluster (Connected)

Hostname: glusterfs-4.glusterfs.default.svc.cluster.local
Uuid: 4076907a-f4c4-4c0a-b709-b36bf6e52644
State: Peer in Cluster (Connected)

```
*Note that the cluster TSP should have scaled up and the TSP will have each member from any of the pods

3.  Scale down, similar to above
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

4.  Delete a pod - do we recover?
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



  # oc rsh glusterfs-0
  # gluster peer status
```

5.  Bring a node down (in AWS set state to `stopped`), check state of the cluster

glusterfs-0                1/1       Running   1          15m       172.18.6.186   ip-172-18-6-186.ec2.internal
glusterfs-1                1/1       Running   0          7m        172.18.2.177   ip-172-18-2-177.ec2.internal
glusterfs-2                1/1       Running   0          13m       172.18.9.66    ip-172-18-9-66.ec2.internal



glusterfs-0                1/1       Running             1          15m       172.18.6.186   ip-172-18-6-186.ec2.internal
glusterfs-1                0/1       ContainerCreating   0          3s        172.18.7.126   ip-172-18-7-126.ec2.internal
glusterfs-2                1/1       Running             0          14m       172.18.9.66    ip-172-18-9-66.ec2.internal


Events:
  FirstSeen	LastSeen	Count	From			SubObjectPath	Type		Reason			Message
  ---------	--------	-----	----			-------------	--------	------			-------
  1m		1m		1	default-scheduler			Normal		Scheduled		Successfully assigned glusterfs-1 to ip-172-18-7-126.ec2.internal
  1m		1m		1	attachdetach				Warning		FailedAttachVolume	(Volume : "kubernetes.io/aws-ebs/aws://us-east-1d/vol-01c5a0ff0193d0bd7") from node "ip-172-18-7-126.ec2.internal" failed to attach - volume is already exclusively attached to another node
  1m		1m		1	attachdetach				Warning		FailedAttachVolume	(Volume : "kubernetes.io/aws-ebs/aws://us-east-1d/vol-0ad64695cbc556c06") from node "ip-172-18-7-126.ec2.internal" failed to attach - volume is already exclusively attached to another node
  1m		1m		1	attachdetach				Warning		FailedAttachVolume	(Volume : "kubernetes.io/aws-ebs/aws://us-east-1d/vol-08ac3c866a5ad5ad3") from node "ip-172-18-7-126.ec2.internal" failed to attach - volume is already exclusively attached to another node


6.  Bring the cluster down (in AWS set state to `stopped`), wait some time and bring back up
All Good Here - have done this multiple times




