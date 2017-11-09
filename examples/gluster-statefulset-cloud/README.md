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

# The Recipe
1. all-in-one yaml file that includes
- storageclass definition
- headless service
- statefulset definition

2. scripts to be executed for liveness probe and preStop hook in lifecycle management.

