#!/bin/bash

# command: bash secret.sh ${DOCKER_KEY}

PASSWORD=$1
echo ${PASSWORD}
kubectl create secret docker-registry imagepullsecret \
    --docker-server=docker.io \
    --docker-username=oshadmon \
    --docker-password=${PASSWORD} \
    --docker-email=ori@anylog.co
