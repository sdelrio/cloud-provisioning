@echo off

@FOR /f "tokens=*" %%I IN ('docker-machine env swarm-1') DO @%%I

setlocal ENABLEDELAYEDEXPANSION
set CURRENTDIR=%cd:\=/%
set CURRENTDIR=%CURRENTDIR::=%
if "%CURRENTDIR:~0,1%" == "C" set DRIVE=c
if "%CURRENTDIR:~0,1%" == "D" set DRIVE=d
if "%CURRENTDIR:~0,1%" == "E" set DRIVE=e
if "%CURRENTDIR:~0,1%" == "F" set DRIVE=f
set CURRENTDIR=/%DRIVE%%CURRENTDIR:~1%

docker service create --name registry ^
    -p 5000:5000 ^
    --reserve-memory 100m ^
    --mount "type=bind,source=%CURRENTDIR%,target=/var/lib/registry" ^
    registry:2.5.0

docker network create --driver overlay proxy

docker network create --driver overlay go-demo

PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& wget https://raw.githubusercontent.com/vfarcic/docker-flow-proxy/master/docker-compose.yml -outfile docker-compose-proxy.yml"

@FOR /f %%I in ('docker-machine ip swarm-1') do set DOCKER_IP=%%I

docker-compose -f docker-compose-proxy.yml ^
    up -d consul-server

@FOR /f %%I in ('docker-machine ip swarm-1') do set CONSUL_SERVER_=%%I

@FOR %%I in (2 3) do (
    @FOR /f "tokens=*" %%V IN ('docker-machine env swarm-%%I') DO @%%V

    @FOR /f %%S in ('docker-machine ip swarm-%%I') do set DOCKER_IP=%%S

    docker-compose -f docker-compose-proxy.yml ^
        up -d consul-agent
)

rm -f docker-compose-proxy.yml

@FOR %%I in (1 2 3) do (
    @FOR /f %%J in ('docker-machine ip swarm-%%I') do set ipswarm%%I=%%J
)

docker service create --name proxy ^
    -p 80:80 ^
    -p 443:443 ^
    -p 8090:8080 ^
    --network proxy ^
    -e MODE=swarm ^
    --replicas 3 ^
    -e CONSUL_ADDRESS="%ipswarm1%:8500,%ipswarm2%:8500,%ipswarm3%:8500" ^
    --reserve-memory 50m ^
    vfarcic/docker-flow-proxy

docker service create --name go-demo-db ^
    --network go-demo ^
    --reserve-memory 150m ^
    mongo:3.2.10

:loopproxy
    docker service ls | grep proxy | grep "3/3"
    if %ERRORLEVEL% EQU 0 goto endloopproxy
    echo "Waiting for the proxy service..."
    sleep 10
    goto loopproxy
:endloopproxy

:loopgodemodb
    docker service ls | grep go-demo-db | grep "1/1"
    if %ERRORLEVEL% EQU 0 goto endloopgodemodb
    echo "Waiting for the go-demo-db service..."
    sleep 10
    goto loopgodemodb
:endloopgodemodb

docker service create --name go-demo ^
    -e DB=go-demo-db ^
    --network go-demo ^
    --network proxy ^
    --replicas 3 ^
    --reserve-memory 50m ^
    --update-delay 5s ^
    vfarcic/go-demo:1.0

:loopgodemo
    docker service ls | grep vfarcic/go-demo | grep "3/3"
    if %ERRORLEVEL% EQU 0 goto endloopgodemo
    echo "Waiting for the go-demo service..."
    sleep 10
    goto loopgodemo
:endloopgodemo

@FOR /f %%I in ('docker-machine ip swarm-1') do set ipswarm1=%%I

echo wget "%ipswarm1%:8090/v1/docker-flow-proxy/reconfigure?serviceName=go-demo&servicePath=/demo&port=8080&distribute=true" -outfile output.json > command.ps1
PowerShell -NoProfile -ExecutionPolicy Bypass -File command.ps1
cat output.json
del output.json
del command.ps1

echo ""
echo ">> The services are up and running inside the swarm cluster"
