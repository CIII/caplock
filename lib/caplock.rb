require 'capistrano'

module Capistrano
  module Caplock
  
    @@username = `whoami`.strip
    @@git_hash = `git rev-parse HEAD`.strip  

    # Returns Boolean indicating the result of +filetest+ on +full_path+ on the server, evaluated by shell on
    # the server (usually bash or something roughly compatible).
    def remote_filetest_passes?(filetest, full_path)
      'true' ==  top.capture("if [ #{filetest} #{full_path} ]; then echo 'true'; fi").strip
    end

    # Checks if a symlink exists on the remote machine.
    def remote_symlink_exists?(full_path)
      remote_filetest_passes?('-L', full_path)
    end

    # Returns Boolean value indicating whether file exists on server
    def remote_file_exists?(full_path)
      remote_filetest_passes?('-e', full_path)
    end

    # Returns Boolean value indicating whether the file at +full_path+ matches +content+.  Checks if file
    # is equivalent to content by checking whether or not the MD5 of the remote content is the same as the
    # MD5 of the String in +content+.
    def remote_file_content_same_as?(full_path, content)
      Digest::MD5.hexdigest(content) == top.capture("md5sum #{full_path} | awk '{ print $1 }'").strip
    end

    # Returns Boolean indicating whether the remote file is present and has the same contents as
    # the String in +content+.
    def remote_file_differs?(full_path, content)
      !remote_file_exists?(full_path) || remote_file_exists?(full_path) && !remote_file_content_same_as?(full_path, content)
    end

    def self.load_into(configuration)
      configuration.load do
        set :lockfile, "cap.lock"

        namespace :lock do
          desc "check lock"
          task :check, :roles => :app do
            if caplock.remote_file_exists?("#{deploy_to}/#{lockfile}")
              run "cat %s" % "#{deploy_to}/#{lockfile}"
              abort "\n\n\n\e[0;31m A Deployment is already in progress\n Remove #{deploy_to}/#{lockfile} to unlock  \e[0m\n\n\n"
            end
          end

          desc "create lock"
          task :create, :roles => :app do

            lock_message = "user=#{@@username}:destination=#{deploy_to}:commit_hash=#{@@git_hash}:status=started"
            put lock_message, "#{deploy_to}/#{lockfile}", :mode => 0644
            run "cat #{deploy_to}/#{lockfile} | logger -t Capistrano" 
          end

          desc "release lock"
          task :release, :roles => :app do
            run "rm -f #{deploy_to}/#{lockfile}"
          end
          
          desc "add finish syslog msg"
          task :finish, :roles => :app do
            run "echo \"user=#{@@username}:destination=#{deploy_to}:commit_hash=#{@@git_hash}:status=finished\" | logger -t Capistrano"
          end
          
          desc "add rollback syslog msg"
          task :fail, :roles => :app do
            run "echo \"user=#{@@username}:destination=#{deploy_to}:commit_hash=#{@@git_hash}:status=failed\" | logger -t Capistrano"
          end
          
        end

        # Deployment
        before "deploy", "lock:check"
        after "lock:check", "lock:create"
        after "deploy", "lock:finish"
        after "lock:finish", "lock:release"
        

        # Rollback
        before "deploy:rollback", "lock:check"
        after "deploy:rollback", "lock:fail"
        after "lock:fail", "lock:release"

      end
    end

    Capistrano.plugin :caplock, Caplock

  end
end

if Capistrano::Configuration.instance
  Capistrano::Caplock.load_into(Capistrano::Configuration.instance)
end
