# Robos

Web based controller for robots. The server reads image data from Thrift servers and feeds that to web clients, who then can control the execution via browser. Browser client supports also machine-vision teaching.

## Installation

These instructions are for setting up a **production** version to a remote server.

**NOTICE:** If you're installing Robos to run it **locally** on your own computer follow the instructions in **Development setup** found later on from this same document!

### Server requirements

Note: instructions and deploy scripts are a tad Ubuntu specific. Some of the tweaks related to `.bash_profile`, `.bash_login`, `.bashrc`, and `/etc/sudoers` may not apply to other distributions. Whatever Linux distribution you use it does need to use [Upstart](http://upstart.ubuntu.com/) though, so to be on the safe side is best to use Ubuntu.

It is advisable to create a separate user account that will run the service, and that will have only limited rights in sudoers. The commands needed to execute are grouped with either `As admin:` or `As user:` where admin is an account that has sudo rights, and user is the account that will be running the service (i.e. user defined in `config/deploy.rb`)

* As admin:
  * Install OpenSSH server: `sudo apt-get install openssh-server`. Edit `/etc/ssh/sshd_config` and comment out lines starting with `ListenAddress`. Run `sudo restart ssh`
  * Install other needed tools: `sudo apt-get install git build-essential libyaml-0-2 libyaml-dev libssl-dev libgdbm-dev libncurses5-dev libffi-dev bison`
  * Install Thrift:

            wget http://mirrors.koehn.com/apache/thrift/0.9.1/thrift-0.9.1.tar.gz
            gunzip thrift-0.9.1.tar.gz
            tar xf thrift-0.9.1.tar
            cd thrift-0.9.1
            ./configure --without-java --without-ruby
            make
            sudo make install

  * Install MongoDB:

            sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10
            echo 'deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen' | sudo tee /etc/apt/sources.list.d/10gen.list
            sudo apt-get update
            sudo apt-get install mongodb-10gen
            wget http://docs.mongodb.org/10gen-gpg-key.asc
            sudo apt-key add 10gen-gpg-key.asc

* As user:
  * Install node.js *v0.10.x* for the account running the service
      * `git clone https://github.com/creationix/nvm.git ~/nvm`
      * `source ~/nvm/nvm.sh`
      * Add `source ~/nvm/nvm.sh` to `~/.bashrc`
      * `nvm install v0.10`
          * If you had NVM installed already (check by running `nvm list`) and if you have some old Node version in use (see the output of previous command) you will likely want to run `nvm alias default 0.10` and then `nvm use default` to get the freshly installed v0.10.x in use
  * Install Ruby *1.9.x* for the account running the service
      * `curl -L https://get.rvm.io | bash`
      * `source ~/.bash_profile`
      * `rvm install 1.9.3`
      * Move the line `[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm"` from `~/.bash_profile` to `~/.bashrc`
  * Comment out first line of `~/.bashrc` which says something like

                  # If not running interactively, don't do anything
                  [ -z "$PS1" ] && return

  * Create file `~/.bash_profile` and add the following lines to it to make `su` work:

                  if [ -f ~/.bashrc ]; then
                    . ~/.bashrc
                  fi

  * Install Foreman: `gem install foreman`
  * Create a symbolic link to the binary so admin does not need to edit sudoers file if you upgrade Ruby: ```ln -s `which foreman` ~/foreman```

* As admin:
  * Set up `/etc/sudoers` since Foreman exports the init script for `upstart`. Add the following lines

            # Disable the secure_path which prevents keeping user $PATH even if it is set in env_keep
            Defaults:USER_NAME !secure_path
            # Keep some environment variables when running commands with sudo
            Defaults:USER_NAME env_keep+="PATH GEM_PATH MY_RUBY_HOME IRBRC GEM_HOME"
            # Create a command alias that includes all commands needed with Foreman
            Cmnd_Alias ROBOIO = /PATH/TO/FOREMAN export upstart /etc/init*, /sbin/start your.domain.com, /sbin/stop your.domain.com, /sbin/restart your.domain.com
            # Allow running the commands above without a password
            USER_NAME ALL=ROBOIO, NOPASSWD: ROBOIO

      * where `USER_NAME` is the user running the service and thus the deploy commands on the server, and `/PATH/TO/FOREMAN` is the path to `foreman` executable. If you used `rvm` for the normal user and created the symblic link it's good to point

  * Create `/etc/logrotate.d/roboio` with following contents:

            APP_PATH/shared/log/*.log {
              compress
              copytruncate
              daily
              dateext
              delaycompress
              missingok
              rotate 30
            }

      * where `APP_PATH` is the path set in `config/deploy/production.rb`s `deploy_to` variable, e.g. `/home/user/sites/your.domain.com`.

#### Running service from port 80/443

We use nginx as reverse proxy to make Robos accessible from port 80/443. You will need nginx 1.4 or later, and thus we're now installing from Launchpad instead of official Ubuntu repositories.

* `wget http://nginx.org/keys/nginx_signing.key`
* `sudo apt-key add nginx_signing.key`
* `echo "deb http://nginx.org/packages/ubuntu/ precise nginx" | sudo tee /etc/apt/sources.list.d/nginx-stable-precise.list`
  * NOTE: This is for Ubuntu 12.04 e.g. precise. Replace the text precise from the repository URL with your Ubuntu version
* `sudo apt-get update`
* `sudo apt-get install nginx`
* `sudo mkdir -p /etc/nginx/sites-available`
* `sudo mkdir -p /etc/nginx/sites-enabled`
* `sudo rm /etc/nginx/conf.d/default.conf`
* `sudo rm /etc/nginx/conf.d/example_ssl.conf`

Replace file `/etc/nginx/nginx.conf` with this:

    user  nginx;
    worker_processes  4;

    error_log  /var/log/nginx/error.log warn;
    pid        /var/run/nginx.pid;

    events {
        worker_connections  1024;
    }

    http {
        sendfile on;
        tcp_nopush on;
        tcp_nodelay on;
        keepalive_timeout 65;
        types_hash_max_size 2048;

        include       /etc/nginx/mime.types;
        default_type  application/octet-stream;

        log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                          '$status $body_bytes_sent "$http_referer" '
                          '"$http_user_agent" "$http_x_forwarded_for"';

        access_log  /var/log/nginx/access.log  main;

        gzip on;
        gzip_disable "msie6";

        include /etc/nginx/conf.d/*.conf;
        include /etc/nginx/sites-enabled/*;
    }

Create file `/etc/nginx/sites-available/your.domain.com` with the following content:

    server {
      server_name your.domain.com;
      listen 80;
      ##listen 443 ssl;

      ##ssl_certificate
      /home/roboio/certs/your.domain.com-chain.pem;
      ##ssl_certificate_key   /home/roboio/certs/your.domain.com.key;

      ##location ^~ /login {
      ##  if ($scheme = http) {
      ##    rewrite ^ https://$server_name$request_uri? permanent;
      ##  }
      ##  try_files $uri @node;
      ##}

      # Change if deployed to another path
      root /home/roboio/sites/your.domain.com/current/public;

      gzip on;
      gzip_http_version 1.1;
      gzip_vary on;
      gzip_proxied any;
      gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;
      gzip_buffers 16 8k;
      client_max_body_size 4M;
      client_body_buffer_size 128k;

      # Disable gzip for old IEs
      gzip_disable "MSIE [1-6].(?!.*SV1)";

      add_header 'X-UA-Compatible' 'IE=Edge';

      location ~ ^/(js/|css/|img/|fonts/) {
        expires max;
        add_header Pragma public;
        add_header Cache-Control "public, proxy-revalidate";
      }

      # This is a group specific route. When adding new groups to
      # robo-io's settings.json add a handler here as well if you wish
      # to force http usage
      location ^~ /robots {
        ##if ($scheme = https) {
        ##  rewrite ^ http://$server_name$request_uri? permanent;
        ##}
        try_files $uri @node;
      }

      location / {
        try_files $uri @node;
      }

      location @node {
        proxy_pass http://localhost:3120;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Server $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP $remote_addr;

        # WebSocket support (nginx 1.4)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
      }
    }

Then symlink properly and restart:

* `cd /etc/nginx/sites-enabled`
* `sudo ln -s ../sites-available/your.domain.com`
* `sudo service nginx restart`

##### SSL Certificates #####

If you wish to use SSL (recommended for the login page), you will need to obtain and create valid certificate chains. This is a bit cumbersome but follow the instructions and you should be fine. We are executing the following commands in folder `/home/roboio/certs` to have the certificates where the above provided nginx configuration expects them to be. Feel free to place somewhere else.

* Generate private key: `openssl genrsa 1024 > your.domain.com.key`
* Generate certificate request: `openssl req -new -key your.domain.com.key > your.domain.com.csr`
* Fill in the certificate information:
  * Country name: `<country code here>`
  * State name: `.`
  * Locality name: `Your City`
  * Organization name: `Your Organization`
  * Organizational unit name: `.`
  * Common name: `your.domain.com`
  * Email address: any address if you wish
  * A challenge password: anything you like
  * An optional company name: `.`

Get it signed in **PEM** format. Save it under name `your.domain.com.pem`. Place the certificate to the same folder where the request and key are. Download CA from your signer and setup valid certificate chain for nginx.

Now, put this all together to form a valid certificate chain:

1. `cp your.domain.pem your.domain.com-chain.pem`
2. `cat "<your_signer_certificate_chain>.crt" >> your.domain-chain.pem` (repeat this step for all certs in chain)

Now you can edit `/etc/nginx/sites-available/your.domain.com` and uncomment those double commented lines to have the SSL functionality enabled. Save, and run `sudo service nginx restart`. You should now be redirected to use SSL when entering the login page, and otherwise use plain HTTP.

### Deployer requirements

The service is deployed using Capistrano which makes deploying web applications quite easy. It is a Ruby application so you'll need to do the following:

* Install required packages: `sudo apt-get install openssh-client git build-essential libyaml-0-2 libyaml-dev libssl-dev libgdbm-dev libncurses5-dev libffi-dev`
* Install Ruby *1.9.x*
      * `curl -L https://get.rvm.io | bash`
      * `source ~/.bash_profile`
      * `rvm install 1.9.3`
* If you have restricted access to the git repository you will need an SSH key. Generate a key by running `ssh-keygen`
* Copy the key to the remote server to allow (passwordless) access: `ssh-copy-id USER_NAME@SERVER` where `USER_NAME` is the account running the service on `SERVER`
* It is recommended to use SSH agent forwarding so the user running the service does not have SSH keys with which someone could access git with restricted access. See if your key is server by ssh-agent by doing to following:
    * Run `ssh-add -L`
    * If you get an error about not being able to connect, run `ssh-agent`. Then run `ssh-add -L` again. If you still get the error run `exec ssh-agent /bin/bash`. Then run `ssh-add -L` again. If you still get the error you'll need some Googling skills.
    * If `ssh-add -L` says `The agent has no identities`, run `ssh-add` to add your current identity to the agent.
* Configure deployment scripts:
    * Set server address and port to `config/deploy/production.rb`. `:app_port` holds the port in which the service will be run, and `server` takes the server address as first parameter
    * Set user name and TeamForge repository address to `config/deploy.rb`. The user name needs to be set to both `:user` and `ssh_options[:user]`. `:repository` holds address to the git repository, place the git url address here.
* Then deploy:
    * `cap production deploy:setup`
    * `cap production deploy`

Later on when you want to deploy an updated version you'll just need to run `cap production deploy`. If it doesn't work out you can roll back to previous version with `cap production deploy:rollback`. Settings file is updated by running `cap production deploy:settings`. **Notice:** this will upload the settings file from **your** computer, not from git! **Notice:** make sure that you have the LDAP **`adminPassword`** set when deploying, otherwise login will not succeed!

## Settings file

The settings file consists of the following sections:

* `ldap`: Settings for LDAP authentication. Please do not commit password to Git, just remeber to set it when deploying new version of settings file. This section should not need much updating.
* `lock_timeout`: Variable defining how many minutes a robot is kept locked for a user who is not sending any commands to the robot
* `admins`: List of email addresses who are considered as admins. Some controls are available only to admins.
* `groups`: Groups are arbitarily named collections of "robots".
* `duts`: Contains test run settings that are DUT specific.

In general the settings are quite straightforward. A few words are needed related to `jenkins.params` section of robots, and for the `duts` section.

The `duts` is simple. Currently it is a list of objects each with a `name` that **must** match a name in Jenkins.

The `jenkins.params` section is an object whose keys are Jenkins job parameters, and value is the default value set in the test run tab. 

Then the keys of `jenkins.params` are checked and for every key found the matching row is shown. This is how you configure what fields are shown in the tab for each robot - if the key exists in `jenkins.params` the field is shown, and vice versa.

The default values defined for each parameter are, obviously, used to populate the fields in the tab. If a value is falsy (empty, false, null, etc.) the input field in question will be left empty, unchecked, or no changes made (radio buttons - for these the falsy one needs to be set `checked="checked"` in the Jade template). The template fields have some linking features which are documented in the Jade template, so when adding new fields look for the instructions there.

## Development setup

**NOTICE:** This sections is for users who

1. Want to run Robos locally on their own computer
1. Are developing the service

If you are deploying Robos to **production** you will **not** need to follow these steps.

First install MongoDB:

    sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10
    echo 'deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen' | sudo tee /etc/apt/sources.list.d/10gen.list
    sudo apt-get update
    sudo apt-get install mongodb-10gen

Notice: If apt-key command fails to download the key e.g. due to corporate proxy, you can download the key manually from MongoDB and then install it:

    wget http://docs.mongodb.org/10gen-gpg-key.asc
    sudo apt-key add 10gen-gpg-key.asc

Then, install Thrift - see Server requirements for details.

Now, Install node.js.

* `git clone https://github.com/creationix/nvm.git ~/nvm`
* add `source ~/nvm/nvm.sh` to `~/.bashrc`
* `source ~/.bashrc`
* `nvm install v0.10`

Then in Robos repository, run `npm install` to install required packages. Check `settings.json`, it may contain production information. Finally, launch the needed scripts in **separate** shell windows:

* `cd tests/servers && python testservice.py`
* `npm run-script grunt` to get Stylus/Coffeescript compiled
  * Notice: `grunt.coffee` defines a livereload server to run on `6001` and proxy requests to `3120`. This is also taken into account in `src/coffee/app.coffee` so that websocket connection is not proxied. If you change the port numbers you need to update `app.coffee` as well if you want to take advantage of livereload.
  * Notice: If you're not developing but just running Robos locally you can shut this down once it is in state `Waiting...` - the files have been compiled and now Grunt is just waiting for changes in the files so it can recompile them.
* `npm run-script dev-start` to get the server running
* Then, go to `http://localhost:6001` on your browser **unless** you just shut down the `npm run-script grunt` command. If you did, or are not actually developing but just running the service, go to `http://localhost:3120`

### Developer overview

**NOTICE:** This is just a brief overview of the system. Any information below is not needed if you just wish to run the service!

The backend service is written in [CoffeeScript](http://coffeescript.org/) which is a language that is compiled into JavaScript. It uses [Express](http://expressjs.com/) framework which takes care of e.g. rendering HTML and handling routes. For communication between the robots [Thrift](http://thrift.apache.org/) is used, and communication between the web clients and the Express backend is handled over [WebSocket](http://en.wikipedia.org/wiki/WebSocket).

When you run `npm start` or `npm run-script dev-start` the following is done:

* `./robo-io-server.coffee` is executed by node. It contains the "main" function.
* In main, settings file is read, logger is initialized, some required ENV variables are checked, and then `RoboIO` service from `./src/server/roboio.coffee` is started.
* `RoboIO` creates and initializes the Express application, and starts the WebSocket server. It also reads all the configured robots from settings file and instantiates required amount of `Robot`s from `./src/server/robot.coffee`.

The main controlling logic happens between the the web client, a `Robot` instance, and the actual robots. When a web client connects, the connection is accepted by `RoboIO` because it holds the WebSocket server. However, `RoboIO` only checks with which `Robot` the clients wants to communicate, and passes the connection to the robot instance. The robot instance then takes care of delivering messages from client(s) to the roboservice, and also to other clients. It also passes the data it receives from roboservice to the web clients. So in general, if you wish to extend the functionality etc., `./src/server/robot.coffee` is probably the place to look into.

Naturally if new things are added client side changes are needed as well. The `main.coffee` just configures [RequireJS](http://requirejs.org/) and loads `app.coffee`, which initializes the state machine and attaches event handlers. `robofsm.coffee` contains the state machine implementation which also handles incoming messages, `ui.coffee` methods for controlling the UI, `ws.coffee` sends commands to backend, and `utils.coffee` contains some utility methods. RequireJS is a library that can load JavaScript modules written to match [AMD API](https://github.com/amdjs/amdjs-api/wiki/AMD) which basically means that it provides you means to split code into meaningful modules and have the dependencies handled.

The actual sources can mostly be found from folder `src`. The subfolders are:

* `coffee`: Client-side coffee script (compiled by Grunt in development environment, and compiled to JavaScript when deploying to production)
* `jade`:   Templates. These are handled by the Express server which renders them and serves as HTML to the web clients.
* `server`: Server-side coffee script. The heart and soul of the application.
* `stylus`: Stylesheets (compiled by Grunt in development, and compiled to CSS when deploying to production`
* `thrift`: Thrift descriptions from RATA repository
