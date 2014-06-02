set :app_name,   "robo-io-web"
set :app_domain, "<your.domain.com>"
set :app_port,   3120

set :application, app_domain
set :deploy_to, "/home/roboio/sites/#{application}"
set :node_env, "production"

ssh_options[:port] = 22

server "<your.domain.com>, :app, :web, :db, :primary => true
