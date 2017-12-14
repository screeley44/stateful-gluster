# gluster-statefulset-cloud-aws
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


## See scripts-and-yaml/scratch-pad-results for inital testing and validation of this project

