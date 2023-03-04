apiVersion: apps/v1
kind: Deployment
metadata:
  name: replica-deployment
  labels:
    name: redis-replica
spec:
  replicas: 2 
  selector:
    matchLabels:
      name: redis-replica
  template:
    metadata:
      labels:
        name: redis-replica
    spec:
      subdomain: replica
      containers:
      - name: redis
        image: arm64v8/redis:alpine 
        command:
          - "redis-server"
        args:
          - "--slaveof"
          - "primary.default.svc.cluster.local"
          - "6379"
          - "--protected-mode"
          - "no"   
        ports:
        - containerPort: 6379