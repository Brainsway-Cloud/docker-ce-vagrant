        #!/bin/bash -vx
        
        # Download and run scripts to configure Ubuntu and Docker
        ./ubuntu.sh # Select "keep the local version ... "
        ./docker.sh
        
        LOCAL_IP=`(curl http://169.254.169.254/latest/meta-data/local-ipv4)`
        USERNAME=$1
        PASSWORD=$2
        HASH=$3
        COOKIE=$4
        SECRET=$5      
              
        # Create a directory for hosting your DB files
        mkdir /home/ubuntu/common

        cat >/etc/docker/daemon.json <<!
        {
            "log-driver": "syslog"
        }
!
        docker swarm init
        
        # Run a CouchDB Docker Container. 
        # (Use EC2 metadata URL to get machine local IP.)
        # (password=admin. use couchdb-hash-pwd -p my-password to generate new COUCHDB_HASHED_PASSWORD)
        docker run -d --name couchdb \
          --restart always \
          -p 5984:5984 -p 5986:5986 -p 4369:4369 -p 9100-9200:9100-9200 \
          -v /home/ubuntu/common:/home/couchdb/common \
          -e COUCHDB_DATA_DIR="/home/couchdb/common/data" \
          -e COUCHDB_USER=$USERNAME \
          -e COUCHDB_HASHED_PASSWORD=$HASH\
          -e COUCHDB_COOKIE=$COOKIE \
          -e COUCHDB_SECRET=$SECRET \
          -e COUCHDB_NODE_NAME=`(curl http://169.254.169.254/latest/meta-data/local-ipv4)` \
          redgeoff/couchdb      
          
        curl -X PUT http://$USERNAME:$PASSWORD@$LOCAL_IP:5984/_users
        curl -X PUT http://$USERNAME:$PASSWORD@$LOCAL_IP:5984/_replicator
        curl -X PUT http://$USERNAME:$PASSWORD@$LOCAL_IP:5984/_global_changes
          
        docker run -it --name spiegel-install \
          -e TYPE='install' \
          -e URL=http://$USERNAME:$PASSWORD@$LOCAL_IP:5984 \
          redgeoff/spiegel
          
        docker service create \
           --name spiegel-update-listener \
           --detach=true \
           --replicas 2 \
           -e TYPE='update-listener' \
           -e URL='http://$USERNAME:$PASSWORD@$LOCAL_IP:5984' \
           redgeoff/spiegel
           
        cat >/tmp/replicator-passwords.json <<!
        {
           "$LOCAL_IP": {
                "$USERNAME": "$PASSWORD"
           }
        }
!
        docker service create \
           --name spiegel-replicator \
           --detach=true \
           --replicas 2 \
           -e URL='http://$USERNAME:$PASSWORD@$LOCAL_IP:5984' \
           --mount type=bind,source=/tmp/replicator-passwords.json,destination=/usr/src/app/passwords.json \
           -e PASSWORDS_FILE=/usr/src/app/passwords.json \
           redgeoff/spiegel
          
        # Enable CORS so that your application can communicate with the database from another domain/subdomain.
        curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
        apt-get install -y nodejs build-essential
        npm install npm -g
        npm install -g add-cors-to-couchdb
        add-cors-to-couchdb http://localhost:5984 -u $USERNAME -p $PASSWORD

        # If peer specified, create the 2-node cluster
        if [ -z ${6+x} ]
        then 
            echo ""
        else
            git clone https://github.com/redgeoff/redgeoff-couchdb-docker
            cd redgeoff-couchdb-docker
            # See https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html for how meta-data works
            ./create-cluster.sh $USERNAME $PASSWORD 5984 5986 $6 $LOCAL_IP
        fi
