@echo off

for %%I in (1 2 3) do (
  docker-machine create -d virtualbox swarm-%%I
)

@FOR /f "tokens=*" %%I IN ('docker-machine env swarm-1') DO @%%I

@FOR /f %%w in ('docker-machine ip swarm-1') do set ipswarm1=%%w
docker swarm init ^
  --advertise-addr %ipswarm1%

@FOR /f %%T in ('docker swarm join-token -q manager') do set TOKEN=%%T

@FOR %%I in (2 3) do (
    @FOR /f "tokens=*" %%V IN ('docker-machine env swarm-%%I') DO @%%V
    @FOR /f %%w in ('docker-machine ip swarm-%%I') do (
        docker swarm join --token %TOKEN% ^
            --advertise-addr %%w ^
            %ipswarm1%:2377
  )
)

@FOR %%I in (1 2 3) do (
    @FOR /f "tokens=*" %%v IN ('docker-machine env swarm-%%I') DO @%%v

    docker node update ^
        --label-add env=prod ^
        swarm-%%I
)

echo ">> The swarm cluster is up and running"
