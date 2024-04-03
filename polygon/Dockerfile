# Use a base image that includes Ubuntu with necessary tools
FROM ubuntu:20.04

# Avoid prompts from apt 
ENV DEBIAN_FRONTEND=noninteractive

# Set work directory
WORKDIR /root

# Install dependencies
RUN apt-get update && \
    apt-get install -y curl git jq lz4 build-essential sudo wget gnupg apt-transport-https erlang && \
    rm -rf /var/lib/apt/lists/*


# Install Go
RUN wget https://raw.githubusercontent.com/maticnetwork/node-ansible/master/go-install.sh && \
    bash go-install.sh && \
    ln -nfs ~/.go/bin/go /usr/bin/go


# Install Erlang from Erlang Solutions
RUN curl -fsSL https://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/erlang_solutions.gpg && \
    echo "deb https://packages.erlang-solutions.com/ubuntu focal contrib" > /etc/apt/sources.list.d/erlang_solutions.list && \
    apt-get update && \
    apt-get install -y erlang

# Install RabbitMQ 3.10.8
RUN wget https://github.com/rabbitmq/rabbitmq-server/releases/download/v3.10.8/rabbitmq-server_3.10.8-1_all.deb && \
    apt-get install -y logrotate && \
    dpkg -i rabbitmq-server_3.10.8-1_all.deb && \
    rm rabbitmq-server_3.10.8-1_all.deb

# Setting up environment variables
ARG MONIKER=my-validator-node

# Install Heimdall  
RUN curl -L https://github.com/maticnetwork/heimdall/releases/download/v1.0.3/heimdalld-v1.0.3-amd64.deb -o heimdalld.deb && \
    dpkg -i heimdalld.deb && \
    rm heimdalld.deb

# Install Bor
RUN curl -L https://github.com/maticnetwork/bor/releases/download/v1.1.0/bor-v1.1.0-amd64.deb -o bor.deb && \
    dpkg -i bor.deb && \
    rm bor.deb


# Initialize Heimdall
RUN heimdalld init

# Configure Heimdall
RUN sed -i 's/seeds = ""/seeds = "1500161dd491b67fb1ac81868952be49e2509c9f@52.78.36.216:26656,dd4a3f1750af5765266231b9d8ac764599921736@3.36.224.80:26656,8ea4f592ad6cc38d7532aff418d1fb97052463af@34.240.245.39:26656,e772e1fb8c3492a9570a377a5eafdb1dc53cd778@54.194.245.5:26656,6726b826df45ac8e9afb4bdb2469c7771bd797f1@52.209.21.164:26656"/' /root/.heimdalld/config/config.toml && \
    sed -i 's/pex = ""/pex = true/' /root/.heimdalld/config/config.toml && \
    sed -i 's/prometheus = ""/prometheus = true/' /root/.heimdalld/config/config.toml && \
    sed -i 's/max_open_connections = ""/max_open_connections = 100/' /root/.heimdalld/config/config.toml

# Configure Bor
RUN bor dumpconfig > /root/.bor/config.toml && \
    sed -i 's/bootnodes = \[\]/bootnodes = ["enode:\/\/b8f1cc9c5d4403703fbf377116469667d2b1823c0daf16b7250aa576bacf399e42c3930ccfcb02c5df6879565a2b8931335565f0e8d3f8e72385ecf4a4bf160a@3.36.224.80:30303","enode:\/\/8729e0c825f3d9cad382555f3e46dcff21af323e89025a0e6312df541f4a9e73abfa562d64906f5e59c51fe6f0501b3e61b07979606c56329c020ed739910759@54.194.245.5:30303"]/' /root/.bor/config.toml

# Copy start script
COPY start_polygon.sh /usr/local/bin/start_polygon.sh
RUN chmod +x /usr/local/bin/start_polygon.sh

# Expose ports
EXPOSE 26656 26657 30303 8545

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/start_polygon.sh"]
