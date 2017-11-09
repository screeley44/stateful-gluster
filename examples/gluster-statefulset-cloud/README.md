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


# Issues
1. Node goes down, since Statefulsets keep consistent DNS naming (but not guaranteed IPs - although, so far it seems they are mostly retained)
   when we bring the node back up OR bring up a new node in it's place, what happens with the TSP?

# Experimentation
1. After initial cluster is running (make sure to give it time for liveness probe initial delay), check the TSP
`
  # oc rsh glusterfs-0
  # gluster peer status
`

