#!/bin/bash
kubectl delete -k .
sleep 4
kubectl apply -k .
sleep 1
kubectl logs -f --tail=-1 --all-containers=true -l app=sequencetest

