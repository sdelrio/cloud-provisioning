#!/usr/bin/env bash

docker network create --driver overlay proxy

docker network create --driver overlay go-demo

docker service create --name proxy \
    -p 80:80 \
    -p 443:443 \
    --reserve-memory 10m \
    --network proxy \
    --replicas 3 \
    -e MODE=swarm \
    -e LISTENER_ADDRESS=swarm-listener \
    vfarcic/docker-flow-proxy

docker service create --name swarm-listener \
    --network proxy \
    --reserve-memory 10m \
    --mount "type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock" \
    -e DF_NOTIF_CREATE_SERVICE_URL=http://proxy:8080/v1/docker-flow-proxy/reconfigure \
    -e DF_NOTIF_REMOVE_SERVICE_URL=http://proxy:8080/v1/docker-flow-proxy/remove \
    --constraint 'node.role==manager' \
    vfarcic/docker-flow-swarm-listener

while true; do
    REPLICAS=$(docker service ls | grep proxy | awk '{print $3}')
    REPLICAS_NEW=$(docker service ls | grep proxy | awk '{print $4}')
    if [[ $REPLICAS == "3/3" || $REPLICAS_NEW == "3/3" ]]; then
        break
    else
        echo "Waiting for the proxy service..."
        sleep 10
    fi
done

docker service create --name go-demo-db \
    --reserve-memory 100m \
    --network go-demo \
    mongo:3.2.10

while true; do
    REPLICAS=$(docker service ls | grep go-demo-db | awk '{print $3}')
    REPLICAS_NEW=$(docker service ls | grep go-demo-db | awk '{print $4}')
    if [[ $REPLICAS == "1/1" || $REPLICAS_NEW == "1/1" ]]; then
        break
    else
        echo "Waiting for the go-demo-db service..."
        sleep 10
    fi
done

docker service create --name go-demo \
    -e DB=go-demo-db \
    --reserve-memory 10m \
    --network go-demo \
    --network proxy \
    --replicas 3 \
    --label com.df.notify=true \
    --label com.df.distribute=true \
    --label com.df.servicePath=/demo \
    --label com.df.port=8080 \
    vfarcic/go-demo:1.2

echo ""
echo ">> The scheduled services will be up-and-running soon"
