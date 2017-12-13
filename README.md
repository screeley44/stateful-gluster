# stateful-gluster
A work in progress repo utilizing K8 Statefulsets with GlusterFS.

# Goal
- Utilize latest upstream docker image for centos-gluster containers
- Develop all-in-one examples and various approaches on how best to take advantage of StatefulSets utilizing built-in Kubernetes primitives
- Phase 1.1 will be to use in cloud environment (AWS, GCE) and manage TSP.
- Phase 1.2 will be to use in cloud environment and manage TSP + Volumes and Bricks
- Phase 1.3 will be to use the solution with real pods/containers (show some examples and PoC)
- Phase 1.4 will be to explore other approaches and how to make more industrialized

# Phase 1.1 Status - Initializing and Managing TSP
- [x] Create running and healthy GlusterFS StatefulSet
- [x] Create initial Trusted Storage Pool
- [x] Happy Path - Scale Up and Down with Trusted Storage Pool intact
- [x] Recovery - delete a pod, should recover
- [x] Recovery - stop a node, pod should go to next available node with TSP intact
- [x] Recovery - stop the cluster

# Phase 1.2 Status - Phase 1 + Create Volumes and Bricks
- [x] Create Trusted Storage Pool AND Initial Volume with Bricks
- [x] Verify replication is working on initial GFS cluster
- [x] Scale Up, does the volume expand to the new node and GFS pod
- [ ] Scale Down, does the volume shrink to the new number of replicas
- [ ] TSP and Volume/Brick/Replication All Good?

# Phase 1.3 Status - Using the Solution
- [ ] Can I create pods that use the solution?
- [ ] Can I dynamically provision clusters or volumes?
- [ ] General Investigation

# Phase 1.4 Status - Experimenting with different approaches
- [ ] Investigate Kube Operators?
- [ ] Investigate CRD?
- [ ] Investigate 3rdParty Resources
- [ ] Investigate specialized plugins/provisioners (external or internal)
- [ ] Investigate replacing shell script functionality with other technology


# Current Issues or ToDo's:
- script can be hardened, admittedley not the best bash shell script person :-)
- 



# See readme and examples for more detail and PoC



 
