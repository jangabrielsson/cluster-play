#!/bin/bash
VERS="9"
APP="app:v$VERS"
docker image build -t $APP .
docker image tag $APP localhost:7888/$APP
docker image push localhost:7888/$APP
