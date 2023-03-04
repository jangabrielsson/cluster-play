#!/bin/bash
kubectl delete -k .
kubectl apply -k .
sleep 4
kubectl logs -f -l app=simple-service

