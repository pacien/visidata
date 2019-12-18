#!/usr/bin/env bash
set -e

KEY_FILE=/tmp/gitcrypt.key
DOCKER_REGISTRY=docker.k8s.visidata.org
VDWWW_IMAGE=$DOCKER_REGISTRY/vdwww/vdwww:latest
VDHUB_IMAGE=$DOCKER_REGISTRY/vdwww/vdhub:latest

sudo apt-get install git-crypt kubectl

# Setup git-crypt to provide access to secure credentials
echo "Unlocking secure credentials with git-crypt..."
echo $GITCRYPT_KEY | base64 -d > $KEY_FILE
git-crypt unlock $KEY_FILE

# Parse the Docker Registry credentials from the k8s setup
json=$(
  cat k8s/secrets.tf |
  grep $DOCKER_REGISTRY |
  sed 's/default =//' |
  sed 's/\\//g' |
  sed 's/"//' |
  sed 's/"$//g'
)
registry_user=$(echo $json | jq ".auths[\"$DOCKER_REGISTRY\"].username" | sed 's/"//g')
registry_password=$(echo $json | jq ".auths[\"$DOCKER_REGISTRY\"].password" | sed 's/"//g')

# Build the VisiData Docker image
pushd vd
docker build -t vdwww .
popd

# Build the Hub Docker image
pushd hub
docker build -t vdhub .
popd

# Quick test
docker run --rm -d -p 9000:9000 vdwww
sleep 1
[ $(curl -LI localhost:9000 -o /dev/null -w '%{http_code}\n' -s) == "200" ]

# Push the images so k8s can pull it for the deploy
docker login $DOCKER_REGISTRY --username $registry_user --password $registry_password
docker tag vdwww $VDWWW_IMAGE
docker push $VDWWW_IMAGE
docker tag vdhub $VDHUB_IMAGE
docker push $VDHUB_IMAGE

# Deploy
config="--kubeconfig k8s/ci_user.k8s_config --context ci"
kubectl $config rollout restart deployment/visidata
