require "bundler/capistrano"
require 'sidekiq/capistrano'

set :application, "inav"
set :app_user, "inav"
set :nginx_user, "nginx"
set :deploy_user, "outman"

set :scm, :git
set :branch, "master"
set :repository,  "git@bitbucket.org:mangege/inav.git"
set :deploy_via, :remote_cache
set :deploy_to, "/home/#{deploy_user}/apps/#{application}"

set :use_sudo, false
default_run_options[:shell] = "bash -l"
default_run_options[:pty] = true

role :web, "h-jm.mangege.com"                          # Your HTTP server, Apache/etc
role :app, "h-jm.mangege.com"                          # This may be the same as your `Web` server
role :db,  "h-jm.mangege.com", :primary => true # This is where Rails migrations will run

namespace :deploy do
  task :start, :roles => :app do
    desc "start puma"
    run "cd #{current_path}; rvmsudo -u #{app_user} bundle exec puma -e production -b 'unix://#{shared_path}/tmp/sockets/puma.sock' -S #{shared_path}/tmp/sockets/puma.state --control 'unix://#{shared_path}/tmp/sockets/pumactl.sock' >> #{shared_path}/log/puma.log 2>&1 &", :pty => false
  end

  desc "stop puma"
  task :stop, :roles => :app do
    run "cd #{current_path} ; rvmsudo -u #{app_user} bundle exec pumactl -S #{shared_path}/tmp/sockets/puma.state stop"
  end

  desc "restar puma"
  task :restart, :roles => :app do
    run "cd #{current_path} ; rvmsudo -u #{app_user} bundle exec pumactl -S #{shared_path}/tmp/sockets/puma.state restart"
  end
end

task :init_shared_path, :roles => :app do
  run "mkdir -p #{deploy_to}/shared/config"

  run "mkdir -p #{deploy_to}/shared/tmp"
  %w[cache pids sessions sockets].each do |dir_name|
    run "mkdir -p #{deploy_to}/shared/tmp/#{dir_name}"
  end
end

task :link_shared_files, :roles => :app do
  run "ln -sf #{deploy_to}/shared/config/*.yml #{latest_release}/config/"

  run "rm -rf #{latest_release}/tmp"
  run "ln -sf #{deploy_to}/shared/tmp #{latest_release}/tmp"
end

task :set_home_acl, :roles => :app do
  run "setfacl -m u:#{app_user}:x /home/#{deploy_user}"
  run "setfacl -m u:#{nginx_user}:x /home/#{deploy_user}"
end

#设置app user和deploy user所拥有的文件的权限
def _set_dir_acl(dir, dir_cmd, file_cmd)
  run "find #{dir} -user #{deploy_user} -type d -print0 | xargs --no-run-if-empty -0 #{dir_cmd}"
  run "find #{dir} -user #{deploy_user} -type f -print0 | xargs --no-run-if-empty -0 #{file_cmd}"
  run "rvmsudo -u #{app_user} sh -c \"cd #{dir}; find #{dir} -user #{app_user} -type d -print0 | xargs --no-run-if-empty -0 #{dir_cmd}\""
  run "rvmsudo -u #{app_user} sh -c \"cd #{dir}; find #{dir} -user #{app_user} -type f -print0 | xargs --no-run-if-empty -0 #{file_cmd}\""
end
#sudo运行服务前后需要设置权限
task :set_app_acl, :roles => :app do
  #app user,rw
  _set_dir_acl(deploy_to, "setfacl -m u:#{app_user}:rwx", "xargs -0 setfacl -m u:#{app_user}:rw")

  #deploy user,rw
  _set_dir_acl(deploy_to, "setfacl -m u:#{deploy_user}:rwx", "xargs -0 setfacl -m u:#{deploy_user}:rw")

  #nginx user,r
  _set_dir_acl(deploy_to, "setfacl -m u:#{nginx_user}:rx", "xargs -0 setfacl -m u:#{nginx_user}:r")

  #app user, x
  _set_dir_acl("#{deploy_to}/shared/bundle/ruby/1.9.1/bin", "> /dev/null", "setfacl -m u:#{app_user}:rwx")

  #other user, -rwx
  _set_dir_acl(deploy_to, "chmod o-rwx", "chmod o-rwx")
end

desc "upload assets"
task :upload_assets_to_oss, :roles => :app do
  run "cd #{latest_release}; bundle exec rake assets:oss:upload"
end

["deploy:start", "deploy:stop", "deploy:restart"].each do |p_name|
  before p_name, :set_app_acl
  after p_name, :set_app_acl
end
after "deploy:setup", :init_shared_path, :set_home_acl
before "deploy:assets:precompile", :link_shared_files #after deploy:update_code
after "deploy:assets:precompile", :upload_assets_to_oss
