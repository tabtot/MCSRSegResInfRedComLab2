# MCSRSegResInfRedComLab2 - Hardening e Resiliência de Serviços Críticos com Docker Swarm

## 📋 Índice
1. [Preparação do Ambiente](#1-preparação-do-ambiente)
2. [Configuração do Swarm](#2-configuração-do-swarm)
3. [Deploy da Stack](#3-deploy-da-stack)
4. [Limpeza do Ambiente](#4-limpeza-do-ambiente)
 
---

## 1. Preparação do Ambiente

### 1.1 Verificar instalação do Docker
```bash
docker --version
docker-compose --version
```

### 1.2 Criar estrutura do projeto
```bash
mkdir ~/lab-swarm
cd ~/lab-swarm
mkdir logs
mkdir scripts
```

### 1.3 Verificar IP da máquina
```bash
ip addr show | grep inet
# ou
hostname -i
```

---

## 2. Configuração do Swarm

### 2.1 Inicializar Docker Swarm
```bash

docker swarm init --advertise-addr <IP>
```

**Exemplo de output:**
```
Swarm initialized: current node (xyz123) is now a manager.
To add a worker to this swarm, run the following command:
    docker swarm join --token SWMTKN-1-xxx <IP>:2377
```

### 2.2 Verificar status do Swarm
```bash
docker node ls
docker info | grep Swarm
```

### 2.3 Adicionar Worker Nodes com Docker-in-Docker

**1. Criar rede para o swarm**
```bash
docker network create --driver overlay swarm-network
```

**2. Criar workers simulados com Docker-in-Docker**
```bash
# Worker 1
docker run -d --privileged --name worker1 \
  --hostname worker1 \
  -p 2376:2376 \
  docker:dind

# Worker 2
docker run -d --privileged --name worker2 \
  --hostname worker2 \
  -p 2377:2376 \
  docker:dind

# Worker 3 (opcional)
docker run -d --privileged --name worker3 \
  --hostname worker3 \
  -p 2378:2376 \
  docker:dind

# Aguardar inicialização
sleep 10
```

**3. Obter token de join**
```bash
# Guardar token do worker
WORKER_TOKEN=$(docker swarm join-token worker -q)
MANAGER_IP=$(hostname -I | awk '{print $1}')

echo "Worker Token: $WORKER_TOKEN"
echo "Manager IP: $MANAGER_IP"
```

**4. Juntar workers ao swarm**
```bash
# Juntar worker1
docker exec worker1 docker swarm join \
  --token $WORKER_TOKEN \
  ${MANAGER_IP}:2377

# Juntar worker2
docker exec worker2 docker swarm join \
  --token $WORKER_TOKEN \
  ${MANAGER_IP}:2377

# Juntar worker3 (opcional)
docker exec worker3 docker swarm join \
  --token $WORKER_TOKEN \
  ${MANAGER_IP}:2377
```

**5. Verificar nodes**
```bash
docker node ls
```

Output esperado:
```
ID                            HOSTNAME   STATUS    AVAILABILITY   MANAGER STATUS   ENGINE VERSION
abc123def456... *             manager    Ready     Active         Leader           24.0.7
ghi789jkl012...               worker1    Ready     Active                          24.0.7
mno345pqr678...               worker2    Ready     Active                          24.0.7
```

### 2.4 Gerir Nodes do Swarm

**Listar nodes**
```bash
docker node ls
```

**Inspecionar node específico**
```bash
docker node inspect worker1 --pretty
```
**Drenar node (tirar tasks)**
```bash
docker node update --availability drain worker1
```

**Reativar node**
```bash
docker node update --availability active worker1
```
## 3 Deploy da Stack
## 3.1 Deploy inicial
```bash
docker stack deploy -c docker-compose.yml resiliencia
```

### 3.2 Verificar deployment
```bash
# Listar stacks
docker stack ls

# Listar serviços
docker service ls

# Detalhar serviço
docker service ps resiliencia_web

# Inspecionar serviço
docker service inspect resiliencia_web --pretty
```

### 3.3 Testar acesso ao serviço
```bash
# Testar endpoint principal
curl http://localhost:8080

# Testar healthcheck endpoint
curl http://localhost:8080/health

# Teste de carga simples
for i in {1..10}; do curl -s http://localhost:8080/health; done
```

### 3.4 Verificar logs
```bash
# Logs do serviço
docker service logs resiliencia_web --tail 50

# Logs em tempo real
docker service logs -f resiliencia_web
```
### 3.5 Observar ambiente docker - Portainer

docker service create --name portainer --publish 9000:9000 --constraint 'node.role == manager' --mount type=bind,src=//var/run/docker.sock,dst=/var/run/docker.sock portainer/portainer
Aceder via http://<IP>:9000

## 4. Limpeza do Ambiente

### 4.1 Remover stack
```bash
# Remover stack resiliencia
docker stack rm resiliencia

# Remover stack de monitorização
docker stack rm monitoring

# Aguardar remoção completa
sleep 10

# Verificar
docker service ls
docker ps
```

### 4.2 Remover workers
```bash

docker rm -f worker1 worker2 worker3

# Limpar nodes do swarm
docker node ls --format "{{.ID}} {{.Hostname}}" | grep worker | awk '{print $1}' | xargs -r docker node rm --force

```

### 4.3 Sair do swarm 
```bash
docker swarm leave --force
```

### 4.4 Limpeza geral
```bash
# Remover volumes órfãos
docker volume prune -f

# Remover redes não utilizadas
docker network prune -f

# Remover imagens não utilizadas
docker image prune -a -f
```

