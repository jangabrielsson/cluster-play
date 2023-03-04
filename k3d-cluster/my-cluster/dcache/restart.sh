#!/bin/bash
kubectl delete -f dcache-replica.yaml
kubectl create -f dcache-replica.yaml
sleep 2
kubectl logs -f -l app=dcache

