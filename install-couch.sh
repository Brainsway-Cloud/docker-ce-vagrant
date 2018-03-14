        #!/bin/bash -vx
        
        # Download and run scripts to configure Ubuntu and Docker
        ./ubuntu.sh # Select "keep the local version ... "
        ./docker.sh
        
        # Create a directory for hosting your DB files
        mkdir /home/ubuntu/common
        
        # Run a CouchDB Docker Container. 
        # (Use EC2 metadata URL to get machine local IP.)
        # (password=admin. use couchdb-hash-pwd -p my-password to generate new COUCHDB_HASHED_PASSWORD)
        docker run -d --name couchdb \
          --restart always \
          -p 5984:5984 -p 5986:5986 -p 4369:4369 -p 9100-9200:9100-9200 \
          -v /home/ubuntu/common:/home/couchdb/common \
          -e COUCHDB_DATA_DIR="/home/couchdb/common/data" \
          -e COUCHDB_USER='admin' \
          -e COUCHDB_HASHED_PASSWORD='-pbkdf2-b1eb7a68b0778a529c68d30749954e9e430417fb,4da0f8f1d98ce649a9c5a3845241ae24,10' \
          -e COUCHDB_COOKIE='mycookie' \
          -e COUCHDB_SECRET='mysecret' \
          -e COUCHDB_NODE_NAME=`(curl http://169.254.169.254/latest/meta-data/local-ipv4)` \
          redgeoff/couchdb
          
        LOCAL_IP=`(curl http://169.254.169.254/latest/meta-data/local-ipv4)`
          
        docker run -it --name spiegel-install \
          -e TYPE='install' \
          -e URL=http://admin:admin@$LOCAL_IP:5984 \
          redgeoff/spiegel
          
        docker service create \
           --name update-listener \
           --detach=true \
           --replicas 2 \
           -e TYPE='update-listener' \
           -e URL='http://admin:admin@localhost:5984' \
           redgeoff/spiegel
          
        # Enable CORS so that your application can communicate with the database from another domain/subdomain.
        curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
        apt-get install -y nodejs build-essential
        npm install npm -g
        npm install -g add-cors-to-couchdb
        add-cors-to-couchdb http://localhost:5984 -u admin -p admin

        # If peer specified, create the 2-node cluster
        if [ -z ${1+x} ]
        then 
            echo ""
        else
            git clone https://github.com/redgeoff/redgeoff-couchdb-docker
            cd redgeoff-couchdb-docker
            # See https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html for how meta-data works
            ./create-cluster.sh admin admin 5984 5986 $1 $LOCAL_IP
        fi
