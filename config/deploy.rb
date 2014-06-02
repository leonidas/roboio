# RoboIO, Web UI for test robots
# Copyright (c) 2014, Intel Corporation.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms and conditions of the GNU Lesser General Public License,
# version 2.1, as published by the Free Software Foundation.
#
# This program is distributed in the hope it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for
# more details.

# Must be set before requiring multistage
set :default_stage, "production"
require 'capistrano/ext/multistage'
require 'json'

# User running the service
set :user, "roboio"
set :use_sudo, false
set :copy_compression, :zip

default_run_options[:shell] = '/bin/bash'

set :scm, :git
set :repository, "ssh://<your.git.repository>"
set :deploy_via, :remote_cache

set :public_children, %w(img css js fonts)
set :settings_file, "settings.json"

# Makes possible to use your own private keys for git checkout without deploying them to server
ssh_options[:forward_agent] = true

after "deploy:setup", "deploy:settings"
after "deploy:finalize_update", "deploy:install_node_packages"
after "deploy:symlink", "deploy:settingsfile:symlink"
after "deploy:update", "deploy:foreman:export"
after "deploy:update", "deploy:compile_static_assets"
after "deploy:compile_static_assets", "deploy:version_assets"

namespace :deploy do
  desc "Deploy settings"
  task :settings, :roles => :app do
    deploy.settingsfile.update
  end

  namespace :settingsfile do
    desc "Setup settings file and upload to shared folder"
    task :setup do
      settings = File.read("./#{settings_file}")
      put settings, "#{shared_path}/#{settings_file}"
    end

    desc "Symlink settings from shared folder"
    task :symlink do
      run "rm -f #{current_path}/#{settings_file} && ln -nfs #{shared_path}/#{settings_file} #{current_path}/#{settings_file}"
    end

    desc "Update settings file"
    task :update do
      deploy.settingsfile.setup
      deploy.settingsfile.symlink
      deploy.foreman.restart
    end
  end

  desc "Restart the app server"
  task :restart, :roles => :app do
    deploy.foreman.restart
  end

  desc "Start the app server"
  task :start, :roles => :app do
    deploy.foreman.start
  end

  desc "Stop the app server"
  task :stop, :roles => :app do
    deploy.foreman.stop
  end

  desc "Install node packages"
  task :install_node_packages, :roles => :app do
    run "cd #{release_path} && npm install --production"
  end

  desc "Compile static assets"
  task :compile_static_assets, :roles => :app do
    run "cd #{release_path} && npm run-script compile-assets"
  end

  desc "Version static assets"
  task :version_assets, :roles => :app do
    run "cd #{release_path} && npm run-script version-assets"
  end

  # Using foreman requires a bunch of stuff on the server. Check readme
  namespace :foreman do
    desc "Export upstart scripts to /etc/init"
    task :export, :roles => :app do
      #run "cd #{release_path} && sudo env PATH=$PATH /home/#{user}/foreman export upstart /etc/init -a #{app_domain} -p #{app_port} -u #{user} -l #{shared_path}/log -t #{release_path}/config/foreman.templates -e #{release_path}/config/foreman.#{node_env}.env"
      run "cd #{release_path} && sudo /home/#{user}/foreman export upstart /etc/init -a #{app_domain} -p #{app_port} -u #{user} -l #{shared_path}/log -t #{release_path}/config/foreman.templates -e #{release_path}/config/foreman.#{node_env}.env"
    end
    desc "Start the application services"
    task :start, :roles => :app do
      sudo "sudo /sbin/start #{app_domain}"
    end

    desc "Stop the application services"
    task :stop, :roles => :app do
      sudo "sudo /sbin/stop #{app_domain}"
    end

    desc "Restart the application services"
    task :restart, :roles => :app do
      run "sudo /sbin/start #{app_domain} || sudo /sbin/restart #{app_domain}"
    end
  end

end
